// SPDX-License-Identifier: Apache-2.0
function failure() { return { ok: false, reason: 'PARSE_ERROR' }; }
function text(v, max) { return type(v) == 'string' && length(v) > 0 && length(v) <= max && !match(v, /[[:cntrl:]]/); }
// This adapter collects ip -4; unsupported address families cannot be
// normalized into IPv4 evidence. Configuration validation is separate.
function address(v, prefix) {
    if (!text(v, 64)) return false;
    if (prefix && (v == 'all' || v == 'default')) return true;
    let parts = split(v, '/');
    if (length(parts) > (prefix ? 2 : 1)) return false;
    let octets = split(parts[0], '.');
    if (length(octets) != 4) return false;
    for (let octet in octets)
        if (!match(octet, /^(0|[1-9][0-9]{0,2})$/) || int(octet) > 255) return false;
    return length(parts) == 1 || (match(parts[1], /^(0|[1-9][0-9]?)$/) && int(parts[1]) <= 32);
}
function parse_agent(raw) {
    if (type(raw) != 'string' || length(raw) >= 65536) return failure();
    try {
        let s = json(raw);
        if (type(s) != 'object' || !text(s.daemonVersion, 64) || !text(s.daemonStatus, 64)
            || type(s.management?.connected) != 'bool' || type(s.signal?.connected) != 'bool'
            || type(s.peers?.details) != 'array' || length(s.peers.details) > 512)
            return failure();
        if ('usesKernelInterface' in s && type(s.usesKernelInterface) != 'bool') return failure();
        let data = { daemon_version: s.daemonVersion, daemon_status: s.daemonStatus,
            management: s.management.connected, signal: s.signal.connected,
            backend: type(s.usesKernelInterface) != 'bool' ? 'unknown' : (s.usesKernelInterface ? 'kernel' : 'userspace'),
            peers: [] };
        for (let peer in s.peers.details) {
            if (type(peer) != 'object' || !address(peer.netbirdIp, false) || !text(peer.status, 64)) return failure();
            // Idle is an observation, never inferred as a disconnected failure.
            push(data.peers, { address: peer.netbirdIp, status: peer.status });
        }
        return { ok: true, data };
    }
    catch (e) { return failure(); }
}
function select_peer(agent, approved_address) {
    if (!address(approved_address, false)) return { ok: false, reason: 'INVALID_PEER_SELECTOR' };
    if (!agent?.ok || type(agent.data?.peers) != 'array') return { ok: false, reason: 'PEER_EVIDENCE_UNAVAILABLE' };
    let found = null;
    for (let peer in agent.data.peers) {
        if (peer.address != approved_address) continue;
        if (found) return { ok: false, reason: 'AMBIGUOUS_PEER' };
        found = peer;
    }
    return found ? { ok: true, peer: { address: found.address, status: found.status } }
        : { ok: false, reason: 'PEER_NOT_OBSERVED' };
}
const FIELDS = {
    rules: ['priority', 'src', 'srclen', 'dst', 'dstlen', 'iif', 'oif', 'table', 'fwmark', 'fwmask', 'not', 'action', 'suppress_prefixlength', 'protocol'],
    routes: ['dst', 'dev', 'gateway', 'prefsrc', 'protocol', 'scope', 'table', 'type', 'flags', 'metric', 'multipath'],
    links: ['ifindex', 'ifname', 'flags', 'mtu', 'operstate', 'link_type', 'master', 'linkinfo'],
};
function normalize(kind, rows) {
    if (type(rows) != 'array' || length(rows) > 1024 || (kind != 'routes' && !length(rows))) return failure();
    let records = [];
    for (let row in rows) {
        if (type(row) != 'object') return failure();
        if (kind == 'rules') {
            if (type(row.priority) != 'int' || row.priority < 0) return failure();
            let terminal = index(['blackhole', 'unreachable', 'prohibit'], row.action) >= 0;
            if (!terminal && row.table == null) return failure();
            if (terminal && row.table != null) return failure();
            if (row.fwmask != null && row.fwmark == null) return failure();
        }
        if (kind == 'routes' && !address(row.dst, true)) return failure();
        if (kind == 'links' && (type(row.ifindex) != 'int' || row.ifindex < 1 || !text(row.ifname, 64))) return failure();
        let out = {};
        for (let key in FIELDS[kind]) {
            if (!(key in row)) continue;
            if (row[key] == null) return failure();
            let value = row[key];
            if (key == 'table') {
                if (type(value) == 'int' ? value < 0 || value > 4294967295 : !text(value, 64) || !match(value, /^[a-zA-Z0-9_.-]+$/)) return failure();
                out[key] = '' + value;
            }
            else if (key == 'not') {
                if (type(value) != 'bool') return failure();
                out[key] = value;
            }
            else if (key == 'fwmark' || key == 'fwmask') {
                if (type(value) != 'int' && (type(value) != 'string' || !match(value, /^(0x[0-9a-fA-F]{1,8}|[0-9]{1,10})$/))) return failure();
                if (int(value) < 0 || int(value) > 4294967295) return failure();
                out[key] = value;
            }
            else if (key == 'flags') {
                if (type(value) != 'array' || length(value) > 32) return failure();
                for (let flag in value) if (!text(flag, 64)) return failure();
                out[key] = value;
            }
            else if (key == 'linkinfo') {
                if (type(value) != 'object') return failure();
                out[key] = {};
                for (let k in ['info_kind', 'info_slave_kind']) {
                    if (value[k] == null) continue;
                    if (!text(value[k], 64)) return failure();
                    out[key][k] = value[k];
                }
            }
            else if (key == 'multipath') {
                // Unsupported next-hop semantics must never collapse to a single path.
                return { ok: false, reason: 'CAPABILITY_MISSING' };
            }
            else if (index(['priority', 'srclen', 'dstlen', 'suppress_prefixlength', 'ifindex', 'mtu', 'metric'], key) >= 0) {
                if (type(value) != 'int' || value < 0 || value > 4294967295) return failure();
                if (index(['srclen', 'dstlen', 'suppress_prefixlength'], key) >= 0 && value > 32) return failure();
                out[key] = value;
            }
            else {
                if (!text(value, 128)) return failure();
                if (index(['src', 'dst'], key) >= 0 && !address(value, true)) return failure();
                if (index(['gateway', 'prefsrc'], key) >= 0 && !address(value, false)) return failure();
                out[key] = value;
            }
        }
        // Unknown selectors or forwarding semantics must never disappear.
        if (kind == 'rules' || kind == 'routes')
            for (let key in row)
                if (index(FIELDS[kind], key) < 0) return { ok: false, reason: 'CAPABILITY_MISSING' };
        push(records, out);
    }
    return { ok: true, records };
}
function parse_text(kind, raw) {
    let rows = [];
    for (let line in split(trim(raw), '\n')) {
        if (!length(trim(line))) continue;
        let tokens = split(trim(line), /\s+/), row = {}, i = 0;
        if (kind == 'rules') {
            if (!match(tokens[0], /^[0-9]+:$/)) return failure();
            row.priority = int(tokens[0]);
            i = 1;
        }
        else if (kind == 'routes') {
            if (index(['blackhole', 'unreachable', 'prohibit', 'throw', 'local', 'broadcast', 'multicast', 'unicast'], tokens[0]) >= 0)
                row.type = tokens[i++];
            row.dst = tokens[i++];
        }
        else return { ok: false, reason: 'CAPABILITY_MISSING' };
        while (i < length(tokens)) {
            let key = tokens[i++];
            let mapped = ({ from: 'src', to: 'dst', lookup: 'table', via: 'gateway', proto: 'protocol', src: 'prefsrc' })[key] || key;
            if (key == 'linkdown' && kind == 'routes') {
                if ('flags' in row) return failure();
                row.flags = ['linkdown']; continue;
            }
            if (kind == 'rules' && key == 'not') {
                if ('not' in row) return failure();
                row.not = true; continue;
            }
            if (kind == 'rules' && index(['blackhole', 'unreachable', 'prohibit'], key) >= 0) {
                if ('action' in row) return failure();
                row.action = key; continue;
            }
            if (mapped in row || index(FIELDS[kind], mapped) < 0 || i >= length(tokens)) return failure();
            let val = tokens[i++];
            if (index(['metric', 'suppress_prefixlength'], mapped) >= 0) {
                if (!match(val, /^[0-9]+$/)) return failure();
                val = int(val);
            }
            if (kind == 'rules' && mapped == 'fwmark' && index(val, '/') >= 0) {
                let parts = split(val, '/');
                if (length(parts) != 2 || 'fwmask' in row) return failure();
                val = parts[0]; row.fwmask = parts[1];
            }
            row[mapped] = val;
        }
        push(rows, row);
    }
    return normalize(kind, rows);
}
function parse_ip(kind, raw, format) {
    if (!FIELDS[kind] || type(raw) != 'string' || length(raw) >= 65536) return failure();
    try {
        if (format == 'json') return normalize(kind, json(raw));
        if (format == 'text') return parse_text(kind, raw);
    }
    catch (e) { return failure(); }
    return failure();
}
export { parse_agent, parse_ip, select_peer };
