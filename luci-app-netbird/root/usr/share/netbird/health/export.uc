// SPDX-License-Identifier: Apache-2.0
import { open, lstat, lsdir, unlink, rename } from 'fs';
import { private_dir, read_json, atomic_json } from './storage.uc';
import { opaque_id } from './jobs.uc';
import { monotonic_ms, run_command } from './runner.uc';
const CHECK_FIELDS = ['id', 'category', 'status', 'severity', 'code', 'expected', 'observed', 'vantage',
    'source', 'target', 'evidence_ref', 'sampled_at', 'last_success_at', 'fresh', 'retryable', 'required',
    'executed', 'duration_ms', 'exit_code', 'parse_status'];
const RUN_FIELDS = ['schema_version', 'run_id', 'node_id', 'boot_id', 'generation', 'started_at', 'finished_at',
    'monotonic_duration_ms', 'config_revision', 'overall', 'delivery_state', 'expected_count', 'executed_count',
    'pass_count', 'fail_count', 'unknown_count', 'not_applicable_count', 'disabled_count'];
function scalar(value, identity) {
    if (value == null || type(value) == 'bool' || type(value) == 'int' || type(value) == 'double') return value;
    if (type(value) != 'string') return '[STRUCTURED_VALUE_OMITTED]';
    // Observed text is not a trusted structured credential container. Keep only
    // bounded diagnostic prose; credential-shaped or encoded material is omitted.
    if (match(value, /token|secret|authorization|private[ _-]?key|session|cookie|bearer|password|setup[ _-]?key|api[ _-]?key|-----BEGIN|\\u[0-9a-f]{4}/i) ||
        (!identity && match(value, /[A-Za-z0-9_+\/=\-]{32,}/))) return '[REDACTED]';
    return substr(value, 0, 512);
}
function fields(source, allowed) {
    let output = {};
    for (let key in allowed) if (source && key in source) {
        let identity = index(['id', 'run_id', 'node_id', 'boot_id', 'generation'], key) >= 0 &&
            type(source[key]) == 'string' && match(source[key], /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$/);
        output[key] = scalar(source[key], identity);
    }
    return output;
}
function evidence(result) {
    if (type(result?.run?.checks) != 'array') return null;
    let run = fields(result.run, RUN_FIELDS), checks = [];
    for (let item in slice(result.run.checks, 0, 64)) push(checks, fields(item, CHECK_FIELDS));
    run.checks = checks;
    if (result.run.observer) run.observer = fields(result.run.observer,
        ['state', 'failure', 'run_id', 'boot_id', 'sampled_at', 'config_revision', 'node_id']);
    if (result.run.alert) {
        let source = result.run.alert;
        run.alert = fields(source, ['owner', 'state', 'reason', 'failures', 'successes', 'episode_id',
            'first_run_id', 'pending', 'dropped_events', 'upstream_down', 'aggregation', 'run_id', 'boot_id',
            'sampled_at', 'config_revision', 'delivery_state', 'receipt_verified', 'delivery_problem',
            'retry_risk', 'ownership_takeover']);
        run.alert.categories = map(slice(source.categories || [], 0, 7), value => scalar(value, false));
        run.alert.recent = source.recent ? fields(source.recent,
            ['id', 'kind', 'state', 'delivery_state', 'attempts', 'error', 'http_status', 'receipt_verified']) : null;
    }
    return { schema_version: 1, content: 'sampled_original_not_current_health_proof',
        sampled_at: result.sampled_at, sequence: result.sequence, sampled_run: run,
        included_checks: length(checks), total_checks: length(result.run.checks),
        truncated: length(checks) < length(result.run.checks),
        collection: fields(result.snapshot, ['complete', 'consistency', 'address_family', 'reason', 'duration_ms', 'attribution']),
        diagnostics_policy: 'Allowlisted original codes and bounded diagnostic text; raw CLI stderr was not retained by the collector.' };
}
function create_exports(root, clock) {
    clock ??= monotonic_ms;
    function names() { return filter(lsdir(root) || [], name => match(name, /^export-[0-9a-f]{32}\.json$/)); }
    function create(result) {
        let data = evidence(result);
        if (!data) return { ok: false, reason: 'NO_RESULT' };
        let payload = sprintf('%J\n', data);
        if (length(payload) > 196608) return { ok: false, reason: 'EXPORT_TOO_LARGE' };
        if (!private_dir(root)) return { ok: false, reason: 'STORAGE_UNAVAILABLE' };
        let lock = open(root + '/exports.lock', 'a', 0600);
        if (!lock || !lock.lock('xn')) { if (lock) lock.close(); return { ok: false, reason: 'EXPORT_BUSY' }; }
        let response, staging = root + '/payload.new';
        try {
            let stale = lstat(staging);
            if (stale && (stale.type != 'file' || stale.uid != 0 || stale.mode != 0600 || !unlink(staging)))
                response = { ok: false, reason: 'STORAGE_UNAVAILABLE' };
            let file = response ? null : open(staging, 'wx', 0600);
            if (!response && !file) response = { ok: false, reason: 'STORAGE_UNAVAILABLE' };
            if (file) {
                let written = file.write(payload); file.close();
                let hash = written == length(payload) ? run_command(['/bin/busybox', 'sha256sum', staging], 1000) : null;
                let match_hash = hash?.ok ? match(hash.stdout, /^([0-9a-f]{64}) /) : null;
                if (!match_hash) response = { ok: false, reason: 'HASH_UNAVAILABLE' };
                else {
                    let retained = [];
                    for (let name in names()) {
                        let old = read_json(root + '/' + name, 524288);
                        push(retained, { name, created_ms: old?.created_ms || 0 });
                    }
                    sort(retained, (a, b) => a.created_ms - b.created_ms);
                    while (length(retained) >= 4)
                        if (!unlink(root + '/' + shift(retained).name)) { response = { ok: false, reason: 'STORAGE_UNAVAILABLE' }; break; }
                    let id = opaque_id(), now = clock();
                    if (!response && !id) response = { ok: false, reason: 'ID_UNAVAILABLE' };
                    if (!response) {
                        let item = { id, payload, sha256: match_hash[1], created_ms: now, expires_ms: now + 600000 };
                        // One fixed metadata stage, then an opaque final name. A
                        // crash cannot accumulate an unissued random-ID .new file.
                        if (!atomic_json(root, 'export-stage.json', item) ||
                            !rename(root + '/export-stage.json', root + '/export-' + id + '.json'))
                            response = { ok: false, reason: 'STORAGE_UNAVAILABLE' };
                        else response = { ok: true, id, size: length(payload), sha256: item.sha256,
                            expires_in_ms: 600000, chunk_size: 16384, encoding: 'base64' };
                    }
                }
            }
        }
        catch (e) { response = { ok: false, reason: 'EXPORT_FAILED' }; }
        unlink(staging); lock.close(); return response;
    }
    function get(id, offset) {
        if (type(id) != 'string' || !match(id, /^[0-9a-f]{32}$/)) return { ok: false, reason: 'EXPORT_INVALID' };
        let item = read_json(root + '/export-' + id + '.json', 524288);
        if (!item || item.id != id) return { ok: false, reason: 'EXPORT_UNKNOWN' };
        let now = clock();
        if (now < item.created_ms || now > item.expires_ms) return { ok: false, reason: 'EXPORT_EXPIRED' };
        if (type(item.payload) != 'string' || type(offset) != 'int' || offset < 0 || offset > length(item.payload))
            return { ok: false, reason: 'OFFSET_INVALID' };
        let end = min(offset + 16384, length(item.payload));
        return { ok: true, id, size: length(item.payload), sha256: item.sha256, offset,
            content_base64: b64enc(substr(item.payload, offset, end - offset)), encoding: 'base64',
            next_offset: end, has_more: end < length(item.payload) };
    }
    return { create, get };
}
function prepare_export(args) {
    let exports = create_exports('/tmp/netbird-health/exports');
    if (args.id) return exports.get(args.id, args.offset ?? 0);
    if (args.offset != null) return { ok: false, reason: 'EXPORT_INVALID' };
    return exports.create(read_json('/tmp/netbird-health/latest.json', 524288));
}
export { evidence, create_exports, prepare_export };
