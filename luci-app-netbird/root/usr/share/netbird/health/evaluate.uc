// SPDX-License-Identifier: Apache-2.0
// Pure IPv4 semantics. Unknown evidence never creates an approved path.
function ip_number(value) {
    if (type(value) != 'string') return null;
    let parts = split(value, '.');
    if (length(parts) != 4) return null;
    let n = 0;
    for (let part in parts) {
        if (!match(part, /^(0|[1-9][0-9]{0,2})$/) || int(part) > 255) return null;
        n = n * 256 + int(part);
    }
    return n;
}
function prefix(value) {
    if (value == 'all' || value == 'default') return { address: 0, bits: 0, size: 4294967296 };
    if (type(value) != 'string') return null;
    let parts = split(value, '/'), n = ip_number(parts[0]);
    if (n == null || length(parts) > 2 || (length(parts) == 2 && !match(parts[1], /^(0|[1-9][0-9]?)$/))) return null;
    let bits = length(parts) == 2 ? int(parts[1]) : 32, size = 1;
    if (bits > 32) return null;
    for (let i = bits; i < 32; i++) size *= 2;
    return { address: n, bits, size };
}
function contains(cidr, address) {
    let p = prefix(cidr), n = ip_number(address);
    return p != null && n != null && int(p.address / p.size) == int(n / p.size);
}
function table_id(value) {
    if (value == null || value == 'main') return '254';
    if (value == 'local') return '255';
    if (value == 'default') return '253';
    return '' + value;
}
function allowed_table(path, value) {
    for (let table in path.routing.tables) if (table_id(table) == table_id(value)) return true;
    return false;
}
function selector(rule, key, len) {
    let value = rule[key] ?? 'all';
    return rule[len] != null && value != 'all' && index(value, '/') < 0 ? value + '/' + rule[len] : value;
}
function mark_number(value) {
    if (type(value) == 'int') return value >= 0 && value <= 4294967295 ? value : null;
    if (type(value) != 'string' || !match(value, /^(0x[0-9a-fA-F]{1,8}|[0-9]{1,10})$/)) return null;
    let n = substr(value, 0, 2) == '0x' ? int(substr(value, 2), 16) : int(value);
    return n >= 0 && n <= 4294967295 ? n : null;
}
function rule_matches(rule, path) {
    let matches = contains(selector(rule, 'src', 'srclen'), path.source_ip) && contains(selector(rule, 'dst', 'dstlen'), path.destination);
    if (rule.iif != null && rule.iif != path.ingress_interface) matches = false;
    // Forwarded route queries have no output-interface selector supplied.
    if (rule.oif != null) matches = false;
    if (rule.fwmark != null) {
        let mark = mark_number(rule.fwmark), mask = rule.fwmask == null ? 4294967295 : mark_number(rule.fwmask);
        if (mark == null || mask == null) return null;
        if (((path.optional_mark ?? 0) & mask) != (mark & mask)) matches = false;
    }
    return rule.not === true ? !matches : matches;
}
function best_route(routes, table, destination) {
    let best = null, bits = -1, metric = 0, ambiguous = false;
    for (let route in routes) {
        if (table_id(route.table) != table_id(table) || !contains(route.dst, destination)) continue;
        let length = prefix(route.dst).bits, cost = route.metric ?? 0;
        if (length > bits || (length == bits && cost < metric)) {
            best = route; bits = length; metric = cost; ambiguous = false;
        }
        else if (length == bits && cost == metric) ambiguous = true;
    }
    return { route: best, ambiguous };
}
function trace_path(path, rules, routes) {
    let ordered = sort(slice(rules), (a, b) => a.priority - b.priority);
    for (let i = 1; i < length(ordered); i++)
        if (ordered[i].priority == ordered[i - 1].priority)
            return { reason: 'AMBIGUOUS_RULE' };
    for (let rule in ordered) {
        let matches = rule_matches(rule, path);
        if (matches == null) return { reason: 'CAPABILITY_MISSING' };
        if (!matches) continue;
        if (rule.action != null && index(['lookup', 'to_tbl', 'unicast'], rule.action) < 0) {
            if (index(['blackhole', 'unreachable', 'prohibit'], rule.action) >= 0) return { rule, blocked: true };
            return { reason: 'CAPABILITY_MISSING' };
        }
        let selected = best_route(routes, rule.table, path.destination);
        if (selected.ambiguous) return { reason: 'AMBIGUOUS_ROUTE' };
        let route = selected.route;
        if (!route || route.type == 'throw') continue;
        if (route.type != null && route.type != 'unicast') return { rule, route, blocked: true };
        if (rule.suppress_prefixlength != null && prefix(route.dst).bits <= rule.suppress_prefixlength) continue;
        return { rule, route, blocked: route.type != null && route.type != 'unicast' };
    }
    return { reason: 'RULE_MISSING' };
}
// Internal producer contract, not authentication: callers must verify probe origin.
function evidence_bound(e, path, snapshot, kind, now) {
    return type(e) == 'object' && e.kind == kind && e.path_id == path.id
        && e.path_source == path.source_ip && e.iif == path.ingress_interface && e.destination == path.destination
        && e.baseline_revision == path.approval.baseline_revision
        && type(snapshot.generation) == 'string' && length(snapshot.generation) > 0 && e.generation == snapshot.generation
        && type(e.sampled_at) == 'int' && type(e.expires_at) == 'int'
        && e.sampled_at >= 0 && e.sampled_at <= now && e.expires_at > now
        && e.expires_at - e.sampled_at <= 300;
}
function route_permitted(path, table, route, exceptions, now) {
    if (!route || (route.type && route.type != 'unicast')) return false;
    if (allowed_table(path, table) && index(path.allowed_egress, route.dev) >= 0) return true;
    for (let exception in exceptions || []) {
        let scope = exception.route, p = prefix(scope?.prefix);
        if (exception.object_id != path.id || type(exception.authorization) != 'string' || !length(exception.authorization)
            || type(exception.expires_at) != 'int' || exception.expires_at <= now
            || scope?.baseline_revision != path.approval.baseline_revision
            || !p || p.address % p.size != 0 || scope.prefix != route.dst
            || !contains(scope.prefix, path.destination) || table_id(scope.table) != table_id(table)
            || scope.egress != route.dev) continue;
        return true;
    }
    return false;
}
function evaluate_path(path, snapshot, lookup, now, exceptions) {
    let checks = [], attribution = 'UNKNOWN';
    function add(category, status, code, severity, observed, vantage) {
        push(checks, { id: path.id + ':' + category, category, status, code, severity,
            expected: path.expected_prefix, observed: observed == null ? null : substr(sprintf('%J', observed), 0, 4096),
            vantage: vantage || 'local_structure', source: path.source_ip, target: path.destination,
            evidence_ref: null, sampled_at: now, last_success_at: status == 'PASS' ? now : null,
            fresh: true, retryable: status == 'UNKNOWN', required: path.required !== false,
            executed: status != 'DISABLED' && code != 'NOT_CONFIGURED', duration_ms: 0, exit_code: null,
            parse_status: status == 'UNKNOWN' ? 'unsupported' : 'ok' });
    }
    let routing = path.routing;
    let expected_prefix = prefix(path.expected_prefix);
    let configured = path.approval?.approved === true && type(routing?.tables) == 'array' && length(routing.tables)
        && type(routing.native_priorities) == 'array' && length(routing.native_priorities)
        && ip_number(path.source_ip) != null && ip_number(path.destination) != null && expected_prefix != null
        && expected_prefix.address % expected_prefix.size == 0 && contains(path.expected_prefix, path.destination);
    let ready = configured && snapshot.complete === true && snapshot.rules?.ok && snapshot.routes?.ok && snapshot.links?.ok;
    if (path.enabled === false) {
        for (let category in ['rules', 'routes', 'peer', 'forward', 'router', 'lan'])
            add(category, 'DISABLED', 'DISABLED', 'info', null, category == 'forward' ? 'forward_lookup' : category == 'router' ? 'router_probe' : category == 'lan' ? 'lan_probe' : null);
        return { checks, attribution };
    }
    if (!ready) {
        let reason = !configured ? 'INTENT_UNVERIFIED' : snapshot.reason || 'GENERATION_UNAVAILABLE';
        for (let category in ['rules', 'routes']) add(category, 'UNKNOWN', reason, 'critical', null);
    }
    else {
        let trace = trace_path(path, snapshot.rules.records, snapshot.routes.records);
        let permitted = trace.route && !trace.blocked && route_permitted(path, trace.rule.table, trace.route, exceptions, now);
        let native = true;
        for (let priority in routing.native_priorities) {
            let found = false;
            for (let rule in snapshot.rules.records)
                if (rule.priority == priority && allowed_table(path, rule.table) && rule_matches(rule, path) === true) found = true;
            if (!found) native = false;
        }
        if (trace.reason && trace.reason != 'RULE_MISSING') add('rules', 'UNKNOWN', trace.reason, 'critical', trace);
        else if (!permitted) {
            let present = false;
            for (let rule in snapshot.rules.records) if (allowed_table(path, rule.table) && rule_matches(rule, path) === true) present = true;
            add('rules', 'FAIL', present ? 'RULE_SHADOWED' : 'RULE_MISSING', 'critical', trace);
        }
        else add('rules', native ? 'PASS' : 'FAIL', native ? 'RULE_CHAIN_VALID' : 'NATIVE_RULE_DRIFT', native ? 'info' : 'warning', trace);
        let expected = prefix(path.expected_prefix), installed = false, shadowed = false, invalid_link = false, ambiguous = false;
        for (let table in routing.tables) {
            for (let route in snapshot.routes.records) {
                let p = prefix(route.dst);
                if (table_id(route.table) == table_id(table) && p && p.bits == expected.bits && p.address == expected.address
                    && index(path.allowed_egress, route.dev) >= 0 && (!route.type || route.type == 'unicast')) installed = true;
            }
            let best = best_route(snapshot.routes.records, table, path.destination);
            if (best.ambiguous) ambiguous = true;
            if (!best.route) continue;
            if (!route_permitted(path, table, best.route, exceptions, now)) shadowed = true;
            let up = false;
            for (let link in snapshot.links.records)
                if (link.ifname == best.route.dev && index(link.flags || [], 'UP') >= 0) up = true;
            if (!up || index(best.route.flags || [], 'linkdown') >= 0) invalid_link = true;
        }
        add('routes', ambiguous ? 'UNKNOWN' : !installed || shadowed || invalid_link ? 'FAIL' : 'PASS',
            ambiguous ? 'AMBIGUOUS_ROUTE' : !installed ? 'ROUTE_MISSING' : shadowed ? 'ROUTE_SHADOWED' : invalid_link ? 'INTERFACE_DOWN' : 'ROUTE_VALID',
            'critical', { installed, shadowed, invalid_link });
    }
    let peer = snapshot.selected_peer;
    if (!ready || peer?.verified !== true || !evidence_bound(peer.evidence, path, snapshot, 'route_selection', now))
        add('peer', 'UNKNOWN', 'PEER_SELECTION_UNVERIFIED', 'warning', null);
    else if (peer.address == routing.primary_peer) add('peer', 'PASS', 'PRIMARY_SELECTED', 'info', { address: peer.address });
    else if (index(routing.backup_peers || [], peer.address) >= 0) add('peer', 'FAIL', 'BACKUP_TAKEOVER', 'warning', { address: peer.address });
    else add('peer', 'FAIL', 'UNAPPROVED_PEER', 'critical', { address: peer.address });
    let bound = ready && lookup?.ok && lookup.source == path.source_ip && lookup.iif == path.ingress_interface
        && lookup.destination == path.destination && lookup.mark == path.optional_mark
        && evidence_bound(lookup.evidence, path, snapshot, 'forward_lookup', now);
    if (!bound) add('forward', 'UNKNOWN', lookup?.reason || 'LOOKUP_UNVERIFIED', 'critical', null, 'forward_lookup');
    else if (length(routing.query_limitations || [])) add('forward', 'UNKNOWN', 'QUERY_LIMITED', 'critical', routing.query_limitations, 'forward_lookup');
    else {
        let best = best_route(snapshot.routes.records, lookup.table, path.destination);
        let valid = !best.ambiguous && best.route?.dev == lookup.dev
            && route_permitted(path, lookup.table, best.route, exceptions, now);
        add('forward', valid ? 'PASS' : 'FAIL', valid ? 'FORWARD_LOOKUP_VALID' : 'FORWARD_LOOKUP_MISMATCH', 'critical',
            { from: lookup.source, iif: lookup.iif, destination: lookup.destination, table: lookup.table, dev: lookup.dev, mark: lookup.mark }, 'forward_lookup');
    }
    for (let vantage in ['router', 'lan']) {
        let probe = snapshot.probes?.[vantage];
        let verified = ready && probe?.fresh === true && index(['PASS', 'FAIL'], probe.status) >= 0
            && evidence_bound(probe.evidence, path, snapshot, vantage + '_probe', now);
        add(vantage, verified ? probe.status : 'UNKNOWN', verified ? (probe.status == 'PASS' ? 'PROBE_PASS' : 'ENDPOINT_FAILURE_CAUSE_UNKNOWN') : 'NOT_CONFIGURED',
            'critical', verified ? { status: probe.status } : null, vantage == 'lan' ? 'lan_probe' : 'router_probe');
    }
    return { checks, attribution };
}
export { evaluate_path, contains, ip_number };
