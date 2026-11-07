// SPDX-License-Identifier: Apache-2.0
import * as uloop from 'uloop';
import { read_config } from './settings.uc';
import { read_json } from './storage.uc';
import { evidence } from './export.uc';
import { create_recovery_jobs } from './recovery-jobs.uc';
import { recovery_eligibility } from './recovery-policy.uc';
let jobs = create_recovery_jobs(), workers = {};
function valid_args(args, allowed) {
    if (type(args) != 'object') return false;
    for (let key in keys(args)) if (key != 'ubus_rpc_session' && index(allowed, key) < 0) return false;
    return true;
}
function prepare_recovery(args, actor) {
    if (!valid_args(args, ['expected_revision']) || type(args.expected_revision) != 'int')
        return { ok: false, reason: 'RECOVERY_ARGUMENT_INVALID' };
    let config = read_config();
    if (!config) return { ok: false, reason: 'CONFIG_UNAVAILABLE' };
    if (config.revision != args.expected_revision) return { ok: false, reason: 'CONFIG_CHANGED' };
    if (config.monitor.enabled !== true) return { ok: false, reason: 'MONITOR_DISABLED' };
    let policy = recovery_eligibility(false);
    if (!policy.ok) return policy;
    let snapshot = evidence(read_json('/tmp/netbird-health/latest.json', 524288));
    if (!snapshot) return { ok: false, reason: 'RECOVERY_EVIDENCE_UNAVAILABLE' };
    let prepared = jobs.prepare(actor, config.revision);
    if (!prepared.ok) return prepared;
    prepared.evidence = snapshot;
    prepared.impact = 'The managed NetBird service restarts once. Mesh transport, including this browser connection, may disconnect. No down/up or credential login is issued. Unverified LAN remains unverified.';
    prepared.retention = 'Latest two claimed jobs; explicit result query never repeats an action.';
    return prepared;
}
function start_recovery(args, actor) {
    if (!valid_args(args, ['id', 'expected_revision', 'confirmed']) || args.confirmed !== true ||
        type(args.expected_revision) != 'int') return { ok: false, reason: 'RECOVERY_CONFIRMATION_REQUIRED' };
    // A retransmitted confirmation is a query, not another launch, even while
    // the first worker holds maintenance or after its result becomes unknown.
    let prior = jobs.get(args.id, actor);
    if (prior.ok) { prior.coalesced = true; return prior; }
    if (prior.reason != 'JOB_UNKNOWN') return prior;
    let config = read_config();
    if (!config || config.revision != args.expected_revision) return { ok: false, reason: 'CONFIG_CHANGED' };
    if (config.monitor.enabled !== true) return { ok: false, reason: 'MONITOR_DISABLED' };
    let policy = recovery_eligibility(false);
    if (!policy.ok) return policy;
    let claimed = jobs.claim(args.id, actor, config.revision, args.confirmed,
        read_json('/tmp/netbird-health/latest.json', 524288));
    if (!claimed.ok || claimed.coalesced) return claimed;
    return dispatch_recovery(claimed);
}
function dispatch_recovery(claimed) {
    let id = claimed.job.id;
    try {
        uloop.init();
        workers[id] = uloop.process('/usr/bin/ucode', ['/usr/share/netbird/health/recovery-host.uc', id,
            '' + (claimed.job.created_ms + 45000)], null,
            () => { delete workers[id]; });
    }
    catch (e) { workers[id] = null; }
    // Losing a launch acknowledgement must never turn into an automatic retry.
    // A claimed but unobserved worker is retired to UNKNOWN by the job deadline.
    claimed.dispatch = workers[id] ? 'submitted' : 'unknown';
    return claimed;
}
function get_recovery_job(args, actor) {
    return valid_args(args, ['id']) ? jobs.get(args.id, actor) : { ok: false, reason: 'RECOVERY_ARGUMENT_INVALID' };
}
export { prepare_recovery, start_recovery, get_recovery_job, dispatch_recovery };
