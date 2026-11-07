// SPDX-License-Identifier: Apache-2.0
// Destructive integration companion: only scripts/test-network-recovery-matrix.sh in a disposable guest.
import { readfile } from 'fs';
import { parse_ip } from '/usr/share/netbird/health/parsers.uc';
import { run_command, monotonic_ms } from '/usr/share/netbird/health/runner.uc';
import { lookup_path } from '/usr/share/netbird/health/lookup.uc';
import { evaluate_path } from '/usr/share/netbird/health/evaluate.uc';
import { aggregate } from '/usr/share/netbird/health/model.uc';
import { difference } from '/usr/share/netbird/health/boundary.uc';
import { read_json, atomic_json } from '/usr/share/netbird/health/storage.uc';
let root = '/etc/nbh-e05-matrix', stage = ARGV[0], expected = ARGV[1];
function require(value, message) { if (!value) die('MATRIX_ASSERTION: ' + stage + ': ' + message + '\n'); }
require(match(stage || '', /^[a-z_]+$/), 'invalid stage');
let now = time(), mono = monotonic_ms();
let path = { id: 'e05-isolated', enabled: true, required: true,
    approval: { approved: true, baseline_revision: 1 }, source_ip: '192.0.2.10',
    ingress_interface: 'e05-lan', destination: '10.40.1.2', expected_prefix: '10.40.0.0/16',
    allowed_egress: ['e05-mesh'], optional_mark: null,
    routing: { tables: ['9911'], native_priorities: [105, 110],
        primary_peer: '100.64.0.1', backup_peers: [], mark_reference: null, query_limitations: [] } };
function command(args) { return run_command(args, 3000); }
function capture() {
    let out = {};
    for (let kind in ['rules', 'routes', 'links']) {
        let args = kind == 'rules' ? ['-4', 'rule', 'show'] :
            kind == 'routes' ? ['-4', 'route', 'show', 'table', 'all'] : ['link', 'show'];
        let argv = ['/sbin/ip', '-d', '-j'];
        for (let arg in args) push(argv, arg);
        let raw = command(argv);
        out[kind] = raw.ok ? parse_ip(kind, raw.stdout, 'json') : { ok: false, reason: raw.reason };
        require(out[kind].ok, 'native capture failed: ' + kind);
    }
    let pid = trim(readfile('/var/run/e05-agent.pid') || '');
    let stat = readfile('/proc/' + pid + '/stat');
    let fields = stat == null ? [] : split(stat, /\s+/);
    out.processes = { fixture_pid: pid, start_ticks: fields[21] ?? null,
        provenance: 'inert procd fixture, NOT a NetBird engine' };
    return out;
}
let before = capture(), lookup = lookup_path(path, command, '/sbin/ip', before.rules), after = capture();
let stable = sprintf('%J', [before.rules, before.routes, before.links]) ==
    sprintf('%J', [after.rules, after.routes, after.links]);
let boot = trim(readfile('/proc/sys/kernel/random/boot_id'));
let snapshot = { complete: stable, boot_id: boot, generation: boot + ':' + mono,
    rules: before.rules, routes: before.routes, links: before.links,
    boundaries: { before, after } };
lookup.evidence = { kind: 'forward_lookup', path_id: path.id, path_source: path.source_ip,
    iif: path.ingress_interface, destination: path.destination, baseline_revision: 1,
    generation: snapshot.generation, sampled_at: now, expires_at: now + 60 };
let evaluated = evaluate_path(path, snapshot, lookup, now);
let current = { sampled_at: now, monotonic_ms: mono, snapshot };
let previous = read_json(root + '/previous.json', 524288), boundary = difference(previous, current);
let forward = null;
for (let check in evaluated.checks) if (check.category == 'forward') forward = check;
require(stable && forward != null, 'unstable or missing forward evidence');
if (expected == 'red') require(forward.status == 'FAIL', 'Connected fixture must not hide failed forwarding');
else if (expected == 'green') require(forward.status == 'PASS', 'restored structure must select approved forwarding path');
else require(expected == 'unknown', 'invalid expectation');
if (stage == 'rules_deleted') {
    require(boundary.boot_changed === false, 'running deletion must not look like a reboot');
    require(before.processes.fixture_pid == previous?.snapshot?.boundaries?.after?.processes?.fixture_pid,
        'rule deletion unexpectedly changed fixture daemon PID');
}
if (stage == 'after_boot') {
    require(boundary.boot_changed === true, 'whole-guest reboot must change the real kernel boot ID');
    for (let rule in before.rules.records)
        require(index([105, 110, 12100], rule.priority) < 0, 'temporary rule survived reboot');
}
require(boundary.engine == 'UNKNOWN' && boundary.attribution == 'cause_undetermined',
    'correlation must not invent engine identity or a deleting actor');
let result = { stage, expectation: expected, sampled_at: now, monotonic_ms: mono, boot_id: boot,
    control_plane: { state: 'Connected', provenance: 'explicit fixture; NOT an actual VPN connection' },
    snapshot, lookup, checks: evaluated.checks, overall: aggregate(evaluated.checks), boundary,
    collection_gap: previous == null ? null : { previous_boot: previous.snapshot.boot_id,
        current_boot: boot, same_boot: previous.snapshot.boot_id == boot,
        wall_seconds: now - previous.sampled_at,
        monotonic_ms: previous.snapshot.boot_id == boot ? mono - previous.monotonic_ms : null },
    limits: ['engine lifecycle UNKNOWN', 'no actual NetBird connection',
        'source/iif route lookup is NOT real user LAN traffic', 'kernel event text is NOT actor attribution'] };
require(atomic_json(root, stage + '.json', result), 'stage evidence publication failed');
require(atomic_json(root, 'previous.json', current), 'previous snapshot publication failed');
printf('%J\n', result);
