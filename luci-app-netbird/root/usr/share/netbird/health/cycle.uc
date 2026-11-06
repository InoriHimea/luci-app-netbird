// SPDX-License-Identifier: Apache-2.0
import { open } from 'fs';
import { collect } from './collect.uc';
import { run_probe } from './probe.uc';
import { monotonic_ms } from './runner.uc';
import { evaluate_path } from './evaluate.uc';
import { aggregate } from './model.uc';
import { difference } from './boundary.uc';
import { read_json, atomic_json, private_dir, keep_history } from './storage.uc';
const ROOT = '/tmp/netbird-health';
if (!private_dir(ROOT)) exit(2);
// Separate from the supervisor lock: a replacement supervisor cannot overlap
// a still-bounded worker orphaned by its predecessor's crash.
let lock = open(ROOT + '/cycle.lock', 'a', 0600);
if (!lock || !lock.lock('xn')) exit(3);
let config = read_json('/etc/netbird-health/config.json', 65536);
if (config?.monitor?.enabled !== true || type(config.paths) != 'array' || length(config.paths) > 64 ||
    type(config.endpoints) != 'array' || length(config.endpoints) > 16) exit(2);
let budget = config.monitor.cycle_timeout;
if (type(budget) != 'int' || budget < 1 || budget > 20) exit(2);
if (type(config.node?.stable_node_id) != 'string' ||
    !match(config.node.stable_node_id, /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}$/) ||
    type(config.revision) != 'int' || config.revision < 0 || config.revision > 2147483647) exit(2);
let started_at = time(), started = monotonic_ms(), deadline = started + budget * 1000;
let snapshot = collect(null, config.paths), probes = [], checks = [];
if (type(snapshot.boot_id) != 'string' || !match(snapshot.boot_id, /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}$/)) exit(4);
for (let endpoint in config.endpoints) {
    if (endpoint.enabled !== true) {
        push(probes, { endpoint_id: endpoint.id, path_id: endpoint.path_id, state: 'DISABLED',
            reason: 'DISABLED', vantage: endpoint.vantage, source_ip: null, destination_ip: null,
            attribution: 'cause_undetermined' });
        continue;
    }
    let remaining = int(deadline - monotonic_ms() - 150);
    if (remaining < 1) {
        push(probes, { endpoint_id: endpoint.id, path_id: endpoint.path_id, state: 'UNKNOWN',
            reason: 'CYCLE_DEADLINE', vantage: 'router_probe', source_ip: null, destination_ip: null,
            attribution: 'cause_undetermined' });
        continue;
    }
    push(probes, run_probe(endpoint, min(remaining, 2000)));
}
for (let path in config.paths) {
    let evaluated = evaluate_path(path, snapshot, snapshot.lookups[path.id], time(), config.exceptions || []);
    for (let check in evaluated.checks) push(checks, check);
}
for (let i = 0; i < length(probes); i++) {
    let probe = probes[i], endpoint = config.endpoints[i], sampled_at = time();
    push(checks, { id: 'endpoint:' + endpoint.id, category: 'endpoint', status: probe.state,
        code: probe.reason || 'PROBE_PASS', severity: 'critical', expected: endpoint.protocol,
        observed: substr(sprintf('%J', probe), 0, 4096), vantage: endpoint.vantage,
        source: probe.source_ip || '', target: endpoint.host, evidence_ref: null,
        sampled_at, last_success_at: probe.state == 'PASS' ? sampled_at : null,
        fresh: true, retryable: probe.state == 'UNKNOWN', required: endpoint.required !== false,
        executed: index(['DISABLED', 'EXTERNAL_VANTAGE_REQUIRED', 'CYCLE_DEADLINE', 'ENDPOINT_INVALID'], probe.reason) < 0,
        duration_ms: probe.duration_ms || 0, exit_code: probe.exit_code ?? null,
        parse_status: probe.state == 'UNKNOWN' ? 'unsupported' : 'ok' });
}
let sampled_at = time();
push(checks, { id: 'node:collection', category: 'collection',
    status: snapshot.complete ? 'PASS' : 'UNKNOWN', code: snapshot.reason || 'COLLECTION_COMPLETE',
    severity: 'critical', expected: 'stable read-only collection', observed: null,
    vantage: 'local_structure', source: 'router', target: 'local', evidence_ref: null,
    sampled_at, last_success_at: snapshot.complete ? sampled_at : null,
    fresh: true, retryable: !snapshot.complete, required: true, executed: true,
    duration_ms: snapshot.duration_ms, exit_code: null, parse_status: snapshot.complete ? 'ok' : 'unsupported' });
let run = aggregate(checks, { maintenance: snapshot.boundaries?.before?.maintenance?.state == 'active' });
run.schema_version = 1;
run.node_id = config.node.stable_node_id;
run.boot_id = snapshot.boot_id;
run.run_id = snapshot.boot_id + ':' + started;
run.generation = snapshot.generation || '';
run.started_at = started_at;
run.finished_at = time();
run.monotonic_duration_ms = monotonic_ms() - started;
run.config_revision = config.revision;
run.checks = checks;
run.events_cursor = null;
run.delivery_state = 'not_requested';
let previous = read_json(ROOT + '/latest.json', 524288);
let sequence = type(previous?.sequence) == 'int' && previous.sequence < 9999999999 ? previous.sequence + 1 : 1;
let result = { sequence, sampled_at, duration_ms: run.monotonic_duration_ms,
    baseline_revision: config.node.baseline_revision, snapshot, run, probes,
    attribution: 'cause_undetermined' };
result.boundary = difference(previous, result);
let limit = config.monitor.history_limit;
limit = type(limit) == 'int' && limit >= 1 && limit <= 1000 ? limit : 20;
// Reserve one maximum-sized publication before any crashable rename. A crash
// after history rename but before pruning cannot grow retained history forever.
if (!keep_history(ROOT, limit - 1, 4194304 - 524288)) exit(4);
if (!atomic_json(ROOT, 'latest.json', result)) exit(4);
if (run.overall == 'healthy') atomic_json(ROOT, 'recent-success.json', result);
if (run.overall != 'healthy' && run.overall != 'disabled' &&
    (!previous?.run || previous.run.overall == 'healthy')) atomic_json(ROOT, 'first-failure.json', result);
if (!atomic_json(ROOT, sprintf('history-%010d.json', sequence), result)) exit(4);
keep_history(ROOT, limit);
