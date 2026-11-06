// SPDX-License-Identifier: Apache-2.0
import { access, open } from 'fs';
import { run_command, monotonic_ms } from './runner.uc';
import { parse_agent, parse_ip } from './parsers.uc';
import { lookup_path } from './lookup.uc';

function executable(candidates) {
    for (let p in candidates) if (access(p, 'x')) return p;
    return candidates[0]; // runner reports TOOL_MISSING, never silent fallback success
}
function boot_id() {
    let f = open('/proc/sys/kernel/random/boot_id', 'r');
    if (!f) return null;
    let id = trim(f.read(64) || '');
    f.close();
    return match(id, /^[0-9a-f-]{36}$/) ? id : null;
}
function process_identity(raw) {
    if (type(raw) != 'string' || length(raw) > 256 || !match(trim(raw), /^[0-9]+( +[0-9]+)*$/)) return null;
    let pids = split(trim(raw), / +/), result = [];
    if (length(pids) > 16) return null;
    for (let pid in sort(pids)) {
        if (int(pid) <= 1 || int(pid) > 4194304) return null;
        let f = open('/proc/' + pid + '/stat', 'r');
        if (!f) return null;
        let raw_stat = f.read(4096) || ''; f.close();
        let stat = match(raw_stat, /^[0-9]+ \(.*\) (.*)$/);
        let fields = stat ? split(trim(stat[1]), / +/) : [];
        if (length(fields) < 20 || !match(fields[19], /^[0-9]+$/)) return null;
        push(result, { pid: int(pid), start_ticks: fields[19] });
    }
    return result;
}
function unknown(reason) { return { ok: false, reason }; }
// Internal injection seam for deterministic command/error/generation scenarios;
// never exposed as an RPC command or UCI-configured executable.
function collect(execute, paths) {
    execute ??= run_command;
    let started = monotonic_ms(), deadline = started + 20000, remaining_bytes = 262144;
    let ip = executable(['/sbin/ip', '/usr/sbin/ip', '/bin/ip', '/usr/bin/ip']);
    let nft = executable(['/usr/sbin/nft', '/sbin/nft']);
    let before_boot = boot_id();
    function command(argv) {
        let remaining = int(deadline - monotonic_ms());
        if (remaining <= 0) return unknown('COMMAND_TIMEOUT');
        if (remaining_bytes <= 0) return unknown('OUTPUT_LIMIT');
        let result = execute(argv, min(remaining, 2000));
        remaining_bytes -= result.output_bytes ?? length(result.stdout || '');
        if (remaining_bytes < 0) return unknown('OUTPUT_LIMIT');
        if (monotonic_ms() >= deadline) return unknown('COMMAND_TIMEOUT');
        if (!result.ok) return { ok: false,
            reason: ({ TIMEOUT: 'COMMAND_TIMEOUT', TOOL_MISSING: 'CAPABILITY_MISSING' })[result.reason] || result.reason || 'COMMAND_FAILED',
            json_unsupported: result.reason == 'COMMAND_FAILED' && result.json_unsupported === true };
        return result;
    }
    function ip_data(kind) {
        let suffix = kind == 'rules' ? ['-4', 'rule', 'show'] : kind == 'routes' ? ['-4', 'route', 'show', 'table', 'all'] : ['-d', 'link', 'show'];
        let argv = [ip, '-j'];
        for (let arg in suffix) push(argv, arg);
        let r = command(argv);
        if (r.ok) return parse_ip(kind, r.stdout, 'json');
        // Only unsupported-command failures may use text. Timeouts, truncated
        // and malformed successful JSON cannot turn into apparently good data.
        if (!r.json_unsupported) return r;
        argv = [ip];
        for (let arg in suffix) push(argv, arg);
        r = command(argv);
        return r.ok ? parse_ip(kind, r.stdout, 'text') : r;
    }
    function firewall_inventory() {
        let firewall = command([nft, '-j', 'list', 'tables']);
        if (!firewall.ok) return firewall;
        try {
            let data = json(firewall.stdout), tables = [];
            if (type(data.nftables) != 'array' || length(data.nftables) > 256) die('invalid');
            for (let entry in data.nftables) {
                if (type(entry) != 'object' || length(keys(entry)) != 1) die('invalid');
                if ('metainfo' in entry) {
                    if (type(entry.metainfo) != 'object') die('invalid');
                    continue;
                }
                let table = entry.table;
                if (type(table?.family) != 'string' || type(table?.name) != 'string'
                    || !match(table.family, /^[a-z]+$/) || !match(table.name, /^[a-zA-Z0-9_.-]{1,64}$/)
                    || type(table.handle) != 'int' || table.handle < 0) die('invalid');
                push(tables, { family: table.family, name: table.name, handle: table.handle });
            }
            firewall = { ok: true, tables };
        }
        catch (e) { firewall = unknown('PARSE_ERROR'); }
        return firewall;
    }
    function snapshot() {
        let pid = command(['/bin/busybox', 'pidof', 'netbird']);
        return { processes: pid.ok ? process_identity(pid.stdout) : null,
            rules: ip_data('rules'), routes: ip_data('routes'), links: ip_data('links'), firewall: firewall_inventory() };
    }
    let before = snapshot();
    let status = command(['/usr/bin/netbird', 'status', '--json']);
    let agent = status.ok ? parse_agent(status.stdout) : status;
    let lookups = {}, lookup_input_valid = paths == null || (type(paths) == 'array' && length(paths) <= 64);
    if (lookup_input_valid && paths != null) {
        for (let path in paths) {
            if (type(path?.id) != 'string' || !match(path.id, /^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,95}$/) || path.id in lookups) {
                lookup_input_valid = false; break;
            }
            lookups[path.id] = lookup_path(path, command, ip, before.rules);
        }
    }
    let firewall = before.firewall;
    let after = snapshot();
    let generation_available = before_boot != null && before.processes != null && after.processes != null
        && before.rules.ok && after.rules.ok && before.routes.ok && after.routes.ok && before.links.ok && after.links.ok
        && before.firewall.ok && after.firewall.ok;
    let stable = generation_available && boot_id() == before_boot && sprintf('%J', before) == sprintf('%J', after);
    let expired = monotonic_ms() >= deadline;
    let complete = stable && agent.ok && !expired && lookup_input_valid;
    if (!stable || expired || !lookup_input_valid)
        for (let id in lookups) lookups[id] = unknown(expired ? 'COMMAND_TIMEOUT' : !lookup_input_valid ? 'INTENT_UNVERIFIED' : 'GENERATION_CHANGED');
    let generation = complete ? before_boot + ':' + started : null;
    let sampled_at = time();
    if (complete) for (let path in paths || []) {
        if (!lookups[path.id]?.ok) continue;
        lookups[path.id].evidence = { kind: 'forward_lookup', path_id: path.id, path_source: path.source_ip,
            iif: path.ingress_interface, destination: path.destination, baseline_revision: path.approval?.baseline_revision,
            generation, sampled_at, expires_at: sampled_at + 30 };
    }
    return { complete, consistency: 'endpoint_comparison', address_family: 'ipv4',
        reason: expired ? 'COMMAND_TIMEOUT' : !generation_available ? 'GENERATION_UNAVAILABLE' : !stable ? 'GENERATION_CHANGED' : complete ? null : 'COLLECTION_INCOMPLETE',
        boot_id: before_boot, duration_ms: monotonic_ms() - started,
        generation,
        agent, rules: before.rules, routes: before.routes, links: before.links, firewall, lookups };
}
export { collect };
