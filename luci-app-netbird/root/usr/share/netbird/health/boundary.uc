// SPDX-License-Identifier: Apache-2.0
import { maintenance_identity } from './maintenance.uc';
function difference(previous, current) {
    let before = previous?.snapshot, after = current?.snapshot;
    let fields = ['processes', 'rules', 'routes', 'links', 'firewall', 'maintenance'];
    let changes = [];
    for (let field in fields) {
        let a = before?.boundaries?.after?.[field], b = after?.boundaries?.before?.[field];
        // The transient binary-operation lease is evidence, not a generation change.
        if (field == 'maintenance') { a = maintenance_identity(a); b = maintenance_identity(b); }
        push(changes, { field, state: a == null || b == null ? 'UNKNOWN' :
            sprintf('%J', a) == sprintf('%J', b) ? 'UNCHANGED' : 'CHANGED' });
    }
    return { boot_changed: before?.boot_id == null || after?.boot_id == null ? null : before.boot_id != after.boot_id,
        engine: 'UNKNOWN', engine_reason: 'ENGINE_IDENTITY_UNAVAILABLE',
        wall_clock_reversed: previous?.sampled_at != null && current?.sampled_at < previous.sampled_at,
        changes, attribution: 'cause_undetermined' };
}
function freshness(result, boot_id, now, max_age) {
    if (result?.snapshot?.boot_id == null || boot_id == null || result.snapshot.boot_id != boot_id)
        return { fresh: false, reason: 'BOOT_BOUNDARY' };
    if (type(now) != 'int' || type(result.sampled_at) != 'int' || now < result.sampled_at)
        return { fresh: false, reason: 'CLOCK_BOUNDARY' };
    return { fresh: now - result.sampled_at <= max_age, reason: now - result.sampled_at <= max_age ? null : 'STALE' };
}
export { difference, freshness };
