// SPDX-License-Identifier: Apache-2.0
import { readfile } from 'fs';
import { contains, ip_number } from './evaluate.uc';

// This bounded subset implements the shipped, local schema. It never fetches a
// schema or resolves references supplied by a caller.
function schema_error(value, spec, path) {
    let kind = type(value), kinds = type(spec.type) == 'array' ? spec.type : [spec.type];
    if (spec.type != null) {
        let actual = value == null ? 'null' : (({ int: 'integer', double: 'number', bool: 'boolean' })[kind] || kind);
        if (index(kinds, actual) < 0) return path;
    }
    if ('const' in spec && value !== spec.const) return path;
    if (spec.enum && index(spec.enum, value) < 0) return path;
    if (kind == 'int' || kind == 'double') {
        if (spec.minimum != null && value < spec.minimum || spec.maximum != null && value > spec.maximum) return path;
    }
    if (kind == 'string') {
        if (spec.minLength != null && length(value) < spec.minLength || spec.maxLength != null && length(value) > spec.maxLength) return path;
        // JSON Schema patterns spell CR/LF escapes; POSIX ERE otherwise reads
        // them as the ordinary letters r/n rather than control characters.
        let pattern = spec.pattern && replace(replace(spec.pattern, '\\r', '\r'), '\\n', '\n');
        if (pattern && !match(value, regexp(pattern))) return path;
    }
    if (kind == 'array') {
        if (spec.minItems != null && length(value) < spec.minItems || spec.maxItems != null && length(value) > spec.maxItems) return path;
        let seen = {};
        for (let i = 0; i < length(value); i++) {
            if (spec.uniqueItems) {
                let key = sprintf('%J', value[i]);
                if (key in seen) return path;
                seen[key] = true;
            }
            if (spec.items) {
                let error = schema_error(value[i], spec.items, path + '[' + i + ']');
                if (error) return error;
            }
        }
    }
    if (kind == 'object') {
        for (let key in spec.required || []) if (!(key in value)) return path + '.' + key;
        for (let key in value) {
            if (!(key in (spec.properties || {}))) {
                if (spec.additionalProperties === false) return path + '.unknown';
                continue;
            }
            let error = schema_error(value[key], spec.properties[key], path + '.' + key);
            if (error) return error;
        }
    }
    for (let clause in spec.allOf || []) {
        let apply = !clause.if || !schema_error(value, clause.if, path);
        if (apply) {
            let error = schema_error(value, clause.then || clause, path);
            if (error) return error;
        }
    }
    return null;
}
function fail(reason, field) { return { ok: false, reason, field }; }
function plain(value) { return type(value) == 'string' && !match(value, /[[:cntrl:]<>]/); }
function network(value, canonical) {
    if (type(value) != 'string') return null;
    let parts = split(value, '/'), address = ip_number(parts[0]);
    if (length(parts) != 2 || address == null || !match(parts[1], /^(0|[1-9][0-9]?)$/) || int(parts[1]) > 32) return null;
    let bits = int(parts[1]), size = 1;
    for (let i = bits; i < 32; i++) size *= 2;
    if (canonical && address % size != 0) return null;
    return { address: address - address % size, bits };
}
function permitted_address(value) {
    let n = ip_number(value);
    if (n == null) return false;
    for (let reserved in ['0.0.0.0/8', '127.0.0.0/8', '169.254.0.0/16', '224.0.0.0/4', '240.0.0.0/4'])
        if (contains(reserved, value)) return false;
    return true;
}
function hostname(value) {
    if (type(value) != 'string' || length(value) > 253) return false;
    if (ip_number(value) != null) return permitted_address(value);
    // Require a DNS name, never libc's legacy numeric or abbreviated IP syntax.
    if (!match(value, /[a-zA-Z]/) || index(value, '.') < 0) return false;
    let labels = split(value, '.');
    for (let label in labels)
        if (!match(label, /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/)) return false;
    return !match(value, /^(0[xX][0-9a-fA-F]+|[0-9.]+)$/);
}
function validate_config(config, supplied_schema) {
    let schema = supplied_schema;
    if (!schema) {
        try { schema = json(readfile('/usr/share/netbird/health/config.schema.json')); }
        catch (e) { return fail('SCHEMA_UNAVAILABLE', 'config'); }
    }
    let error = schema_error(config, schema, 'config');
    if (error) return fail('CONFIG_INVALID', error);
    if (length(sprintf('%J', config)) > 65536) return fail('CONFIG_TOO_LARGE', 'config');
    let paths = {}, endpoints = {}, exceptions = {};
    for (let path in config.paths) {
        let field = 'paths.' + path.id, raw = network(path.raw_cidr, false), normalized = network(path.normalized_cidr, true);
        if (path.id in paths) return fail('DUPLICATE_ID', field);
        paths[path.id] = path;
        if (!raw || !normalized || raw.address != normalized.address || raw.bits != normalized.bits || !network(path.expected_prefix, true))
            return fail('CIDR_INVALID', field);
        if (!permitted_address(path.source_ip) || !permitted_address(path.destination)
            || !contains(path.expected_prefix, path.destination)) return fail('ADDRESS_SCOPE_INVALID', field);
        if (!plain(path.approval.approved_by)) return fail('AUDIT_IDENTITY_INVALID', field);
        for (let address in path.routing.backup_peers)
            if (!permitted_address(address)) return fail('PEER_INVALID', field);
        if (path.routing.primary_peer != null && !permitted_address(path.routing.primary_peer)) return fail('PEER_INVALID', field);
    }
    for (let endpoint in config.endpoints) {
        let field = 'endpoints.' + endpoint.id, path = paths[endpoint.path_id];
        if (endpoint.id in endpoints) return fail('DUPLICATE_ID', field);
        endpoints[endpoint.id] = true;
        if (!path || !path.approval.approved) return fail('PATH_UNAPPROVED', field);
        if (!hostname(endpoint.host)) return fail('HOST_INVALID', field);
        for (let address in endpoint.allowed_addresses)
            if (!permitted_address(address) || !contains(path.expected_prefix, address)) return fail('ADDRESS_SCOPE_INVALID', field);
        if (ip_number(endpoint.host) != null && index(endpoint.allowed_addresses, endpoint.host) < 0)
            return fail('ADDRESS_PIN_REQUIRED', field);
        // No redirects are followed. Paths are credential-free origin-form,
        // with no encoded separators/control characters or traversal segments.
        let url = endpoint.http_path;
        if (substr(url, 0, 2) == '//' || match(url, /[[:cntrl:][:space:]?#]/) || index(url, '\\') >= 0
            || index(url, '%') >= 0 || match(url, /(^|\/)\.\.?(\/|$)/)) return fail('HTTP_PATH_INVALID', field);
    }
    for (let exception in config.exceptions) {
        if (exception.id in exceptions) return fail('DUPLICATE_ID', 'exceptions');
        exceptions[exception.id] = true;
        if (!plain(exception.reason) || !plain(exception.authorization)) return fail('TEXT_INVALID', 'exceptions');
        if (exception.route && !network(exception.route.prefix, true)) return fail('CIDR_INVALID', 'exceptions');
    }
    return { ok: true };
}
export { validate_config, permitted_address, hostname };
