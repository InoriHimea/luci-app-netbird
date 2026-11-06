// SPDX-License-Identifier: Apache-2.0
import { aggregate, reconcile } from '../../luci-app-netbird/root/usr/share/netbird/health/model.uc';

let assertions = 0;
function check(value, message) {
    assertions++;
    if (!value) die('FAIL: ' + message + '\n');
}
function result(id, status, vantage, severity) {
    return { id, status, vantage, severity: severity || 'critical', required: true,
        executed: true, fresh: true, code: status == 'PASS' ? 'OK' : 'NATIVE_RULE_DRIFT' };
}
let missing = aggregate([
    result('control', 'PASS', 'local_structure'),
    result('rule', 'FAIL', 'local_structure'),
    result('forward', 'FAIL', 'forward_lookup')
], {});
check(missing.overall == 'unhealthy', 'A01 Connected must not hide missing rules and WAN forwarding');
check(missing.coverage.lan_probe == 'unknown', 'A01 route query does not prove LAN traffic');
let fallback = aggregate([
    result('rule', 'FAIL', 'local_structure', 'warning'),
    result('forward', 'PASS', 'forward_lookup'),
    result('service', 'PASS', 'router_probe')
], {});
check(fallback.overall == 'degraded', 'A02 passing fallback cannot hide native drift');
check(fallback.coverage.router_probe == 'healthy' && fallback.coverage.lan_probe == 'unknown', 'A02 keep probe perspectives separate');
let absent = aggregate([result('control', 'PASS', 'local_structure')], {});
check(absent.overall == 'unknown', 'A10 no LAN probe cannot be globally healthy');
check(absent.coverage.local_structure == 'healthy', 'A10 local health still reported');
let intent = [result('first', 'PASS', 'local_structure'), result('second', 'PASS', 'lan_probe')];
let actual = [result('first', 'PASS', 'local_structure')];
let reconciled = reconcile(intent, actual);
let incomplete = aggregate(reconciled, {});
check(length(reconciled) == 2 && reconciled[1].status == 'UNKNOWN' && !reconciled[1].executed, 'missing observation remains an unexecuted UNKNOWN');
check(incomplete.expected_count == 2 && incomplete.executed_count == 1 && incomplete.unknown_count == 1, 'unexecuted checks retain denominator');
check(intent[1].status == 'PASS', 'reconciliation must not alter approved intent');
let stale = result('lan', 'PASS', 'lan_probe'); stale.fresh = false;
check(aggregate([stale], {}).overall == 'unknown', 'stale success cannot keep green');
let healthy = [result('local', 'PASS', 'local_structure'), result('lan', 'PASS', 'lan_probe')];
check(aggregate(healthy, {}).overall == 'healthy', 'fresh local and actual LAN success can be green');
check(aggregate(healthy, { stale: true }).overall == 'unknown', 'stale run overrides previous green');
check(aggregate(healthy, { maintenance: true }).flags.maintenance, 'maintenance remains separate from measured health');
check(aggregate(healthy, { enabled: false }).overall == 'disabled', 'explicit disabled intent is not a fault');
let optional = result('optional', 'UNKNOWN', 'external_observer'); optional.required = false;
check(aggregate([...healthy, optional], {}).overall == 'healthy', 'optional observer gap does not invalidate required local/LAN checks');
check(aggregate([], {}).overall == 'unknown', 'empty run is not success');
let na = result('lan', 'NOT_APPLICABLE', 'lan_probe');
check(aggregate([na], {}).overall == 'unknown', 'not applicable is not LAN proof');
let duplicate_rejected = false;
try { reconcile(intent, [actual[0], actual[0]]); } catch (e) { duplicate_rejected = true; }
check(duplicate_rejected, 'duplicate observations must be rejected, not counted twice');
let critical_intent = [result('critical-path', 'PASS', 'local_structure')];
let downgraded = result('critical-path', 'FAIL', 'local_structure', 'warning');
check(aggregate(reconcile(critical_intent, [downgraded]), {}).overall == 'unhealthy',
    'observation cannot downgrade approved critical failure');
for (let excluded in ['DISABLED', 'NOT_APPLICABLE']) {
    let hidden = result('critical-path', excluded, 'local_structure'); hidden.executed = false;
    let protected = reconcile(critical_intent, [hidden]);
    check(protected[0].status == 'UNKNOWN' && aggregate([...healthy, ...protected], {}).overall == 'unknown',
        'observation cannot invent an approved exclusion: ' + excluded);
}
let disabled_intent = [result('critical-path', 'DISABLED', 'local_structure')];
check(reconcile(disabled_intent, [downgraded])[0].status == 'DISABLED',
    'observations cannot re-enable an explicitly disabled expectation');
printf('PASS health model: %d assertions\n', assertions);
