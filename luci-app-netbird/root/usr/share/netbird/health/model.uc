// SPDX-License-Identifier: Apache-2.0
// Pure result model: observations never change the approved monitoring set.
const vantages = ['local_structure', 'forward_lookup', 'router_probe', 'lan_probe', 'external_observer'];
const statuses = ['PASS', 'FAIL', 'UNKNOWN', 'NOT_APPLICABLE', 'DISABLED'];

function reconcile(expected, observed) {
    let by_id = {};
    for (let item in observed) {
        if (!item.id || by_id[item.id] != null) die('Duplicate or empty observation ID');
        by_id[item.id] = item;
    }
    let result = [];
    let seen = {};
    for (let item in expected) {
        if (!item.id || seen[item.id]) die('Duplicate or empty expected ID');
        seen[item.id] = true;
        let observation = by_id[item.id];
        let entry = {};
        for (let key, value in item) entry[key] = value;
        if (observation) {
            for (let key, value in observation) entry[key] = value;
            // Identity, obligation and expectation belong to administrator intent.
            entry.required = item.required;
            entry.vantage = item.vantage;
            entry.expected = item.expected;
            entry.severity = item.severity;
            if ((observation.status == 'DISABLED' || observation.status == 'NOT_APPLICABLE') &&
                observation.status != item.status) {
                entry.status = 'UNKNOWN';
                entry.code = 'INTENT_MISMATCH';
            }
        }
        else {
            entry.status = 'UNKNOWN';
            entry.code = 'NOT_EXECUTED';
            entry.executed = false;
            entry.fresh = false;
            entry.observed = null;
        }
        if (item.status == 'DISABLED' || item.status == 'NOT_APPLICABLE') {
            entry.status = item.status;
            entry.executed = false;
        }
        push(result, entry);
    }
    return result;
}

function aggregate(checks, options) {
    options = options || {};
    let output = { overall: 'unknown', coverage: {},
        flags: { checking: !!options.checking, maintenance: !!options.maintenance, stale: !!options.stale },
        expected_count: length(checks), executed_count: 0, pass_count: 0, fail_count: 0,
        unknown_count: 0, not_applicable_count: 0, disabled_count: 0 };
    let counts = { PASS: 'pass_count', FAIL: 'fail_count', UNKNOWN: 'unknown_count',
        NOT_APPLICABLE: 'not_applicable_count', DISABLED: 'disabled_count' };
    let groups = {};
    for (let vantage in vantages) groups[vantage] = { pass: 0, unknown: 0, warning: 0, critical: 0 };
    let required = { pass: 0, unknown: 0, warning: 0, critical: 0 };
    let seen = {};
    for (let item in checks) {
        if (!item.id || seen[item.id]) die('Duplicate or empty check ID');
        seen[item.id] = true;
        if (index(statuses, item.status) < 0 || !groups[item.vantage]) die('Invalid check status or vantage');
        let status = item.status;
        if (!item.executed || !item.fresh || options.stale) {
            if (status == 'PASS' || status == 'FAIL') status = 'UNKNOWN';
        }
        output[counts[status]]++;
        if (item.executed) output.executed_count++;
        let bucket = status == 'PASS' ? 'pass' : status == 'FAIL' ?
            (item.severity == 'critical' ? 'critical' : 'warning') : status == 'UNKNOWN' ? 'unknown' : null;
        if (bucket) {
            groups[item.vantage][bucket]++;
            if (item.required !== false) required[bucket]++;
        }
    }
    function health(group) {
        if (group.critical) return 'unhealthy';
        if (group.warning) return 'degraded';
        if (group.unknown || !group.pass) return 'unknown';
        return 'healthy';
    }
    for (let vantage in vantages) output.coverage[vantage] = health(groups[vantage]);
    output.overall = health(required);
    // Router-originated probes and route lookups are not LAN end-to-end proof.
    if (output.overall == 'healthy' && output.coverage.lan_probe != 'healthy') output.overall = 'unknown';
    if (options.enabled === false) output.overall = 'disabled';
    return output;
}

export { reconcile, aggregate };
