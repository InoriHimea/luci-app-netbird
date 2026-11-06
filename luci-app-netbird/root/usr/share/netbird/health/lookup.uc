// SPDX-License-Identifier: Apache-2.0
import { ip_number } from './evaluate.uc';
function unknown(reason) { return { ok: false, reason }; }
function identifier(v) { return type(v) == 'string' && match(v, /^[a-zA-Z0-9_.:-]{1,15}$/); }
function uint32(value) {
    if (type(value) == 'string' && !match(value, /^(0x[0-9a-fA-F]+|[0-9]+)$/)) return null;
    if (type(value) != 'string' && type(value) != 'int') return null;
    let n = type(value) == 'string' && substr(value, 0, 2) == '0x' ? int(substr(value, 2), 16) : int(value);
    return n >= 0 && n <= 4294967295 ? n : null;
}
// Evidence is bound to the exact approved query, not inferred from route dumps.
// An omitted table remains unknown: do not invent the matched policy table.
function parse_lookup(raw, format, path) {
    if (type(raw) != 'string' || length(raw) >= 65536) return unknown('PARSE_ERROR');
    let row;
    try {
        if (format == 'json') {
            let rows = json(raw);
            if (type(rows) != 'array' || length(rows) != 1 || type(rows[0]) != 'object') return unknown('PARSE_ERROR');
            row = rows[0];
            for (let key in row)
                if (index(['dst', 'from', 'dev', 'table', 'gateway', 'prefsrc', 'flags', 'cache', 'iif', 'uid', 'mark', 'type'], key) < 0)
                    return unknown('CAPABILITY_MISSING');
            if ('flags' in row && (type(row.flags) != 'array' || length(row.flags))) return unknown('CAPABILITY_MISSING');
            if ('cache' in row && (type(row.cache) != 'array' || length(row.cache))) return unknown('CAPABILITY_MISSING');
        }
        else if (format == 'text') {
            let tokens = split(trim(raw), /\s+/), i = 0;
            row = {};
            if (tokens[0] == 'local') row.type = tokens[i++];
            row.dst = tokens[i++];
            while (i < length(tokens)) {
                let key = tokens[i++];
                if (key == 'cache') {
                    if (i != length(tokens)) return unknown('CAPABILITY_MISSING');
                    break;
                }
                key = ({ via: 'gateway', src: 'prefsrc' })[key] || key;
                if (index(['from', 'dev', 'table', 'gateway', 'prefsrc', 'iif', 'uid', 'mark'], key) < 0)
                    return unknown('CAPABILITY_MISSING');
                if (key in row || i >= length(tokens)) return unknown('PARSE_ERROR');
                row[key] = tokens[i++];
            }
        }
        else return unknown('PARSE_ERROR');
        if (row.dst != path.destination || ('from' in row && row.from != path.source_ip)
            || ('iif' in row && row.iif != path.ingress_interface)) return unknown('LOOKUP_BINDING_MISMATCH');
        if (!identifier(row.dev)) return unknown('PARSE_ERROR');
        for (let key in ['gateway', 'prefsrc'])
            if (key in row && ip_number(row[key]) == null) return unknown('PARSE_ERROR');
        if ('type' in row && row.type != 'unicast') return unknown('CAPABILITY_MISSING');
        if (row.table == null) return unknown('LOOKUP_TABLE_UNAVAILABLE');
        if (type(row.table) == 'int' ? row.table < 0 || row.table > 4294967295
            : type(row.table) != 'string' || !match(row.table, /^[a-zA-Z0-9_.-]{1,64}$/)) return unknown('PARSE_ERROR');
        if ('mark' in row && (uint32(row.mark) == null || uint32(row.mark) != (path.optional_mark ?? 0))) return unknown('LOOKUP_BINDING_MISMATCH');
        return { ok: true, source: path.source_ip, iif: path.ingress_interface,
            destination: path.destination, mark: path.optional_mark, table: '' + row.table, dev: row.dev,
            gateway: row.gateway, evidence: 'kernel_route_get' };
    }
    catch (e) { return unknown('PARSE_ERROR'); }
}
function mark_verified(path, rules) {
    let ref = path.routing?.mark_reference, mark = uint32(path.optional_mark);
    if (type(ref) != 'object' || mark == null || !rules?.ok
        || uint32(ref.mark) == null || uint32(ref.mask) == null
        || (mark & ref.mask) != (ref.mark & ref.mask)) return false;
    let found = null;
    for (let rule in rules.records) {
        if (rule.priority != ref.priority) continue;
        if (found != null) return false;
        found = rule;
    }
    return found != null && '' + found.table == ref.table && found.not !== true
        && (!found.action || found.action == 'lookup')
        && uint32(found.fwmark) == ref.mark && uint32(found.fwmask ?? 4294967295) == ref.mask;
}
function lookup_path(path, command, ip, rules) {
    if (path?.enabled === false) return unknown('DISABLED');
    if (path?.approval?.approved !== true || ip_number(path.source_ip) == null
        || ip_number(path.destination) == null || !identifier(path.ingress_interface)) return unknown('INTENT_UNVERIFIED');
    // Resolve the approved reference against this collection's observed rules.
    // This proves query provenance, not that real packets receive the mark.
    if (path.optional_mark != null && !mark_verified(path, rules)) return unknown('MARK_PROVENANCE_UNVERIFIED');
    let suffix = ['-4', 'route', 'get', path.destination, 'from', path.source_ip, 'iif', path.ingress_interface];
    if (path.optional_mark != null) { push(suffix, 'mark'); push(suffix, '' + path.optional_mark); }
    let argv = [ip, '-d', '-j'];
    for (let arg in suffix) push(argv, arg);
    let result = command(argv);
    if (result.ok) return parse_lookup(result.stdout, 'json', path);
    if (!result.json_unsupported) return result;
    argv = [ip, '-d'];
    for (let arg in suffix) push(argv, arg);
    result = command(argv);
    return result.ok ? parse_lookup(result.stdout, 'text', path) : result;
}
export { lookup_path, parse_lookup };
