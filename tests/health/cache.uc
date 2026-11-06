// SPDX-License-Identifier: Apache-2.0
import { cached_view, refresh_page } from '../../luci-app-netbird/root/usr/share/netbird/health/cache.uc';
let n = 0;
function check(ok, label) { if (!ok) die(label + '\n'); n++; }
let config = { revision: 3, node: { baseline_revision: 2 }, monitor: { enabled: true, interval: 30, cycle_timeout: 2 } };
let cached = { sampled_at: 100, baseline_revision: 2, snapshot: { boot_id: 'boot-a' },
    run: { boot_id: 'boot-a', config_revision: 3, run_id: 'run-one', checks: [
        { id: 'lan', status: 'PASS', severity: 'critical', vantage: 'lan_probe', executed: true, fresh: true, required: true },
        { id: 'off', status: 'DISABLED', severity: 'critical', vantage: 'router_probe', executed: false, fresh: true, required: false }
    ] } };
let fresh = cached_view(cached, config, 'boot-a', 110, null);
check(fresh.ok && fresh.run.overall == 'healthy' && fresh.run.expected_count == 2 && fresh.run.disabled_count == 1,
    'fresh cached evidence retains full approved sampled denominator');
let stale = cached_view(cached, config, 'boot-a', 200, null);
check(stale.ok && stale.run.overall == 'unknown' && stale.run.unknown_count == 1 && stale.run.disabled_count == 1 &&
    stale.run.checks[0].status == 'UNKNOWN' && stale.reason == 'STALE', 'expired evidence cannot retain green summary or detail');
check(cached.run.checks[0].status == 'PASS', 'view never rewrites original diagnostic evidence');
check(cached_view(cached, config, 'boot-b', 110, null).reason == 'BOOT_BOUNDARY', 'boot boundary invalidates cached proof');
check(cached_view(cached, config, 'boot-a', 99, null).reason == 'CLOCK_BOUNDARY', 'backwards wall clock invalidates proof');
config.revision = 4;
let changed = cached_view(cached, config, 'boot-a', 110, null);
check(changed.reason == 'CONFIG_CHANGED' && changed.run.overall == 'unknown' && changed.scope == 'previous_approved_baseline',
    'old configuration cannot masquerade as current baseline proof');
config.monitor.enabled = false;
check(cached_view(cached, config, 'boot-a', 110, null).run.overall == 'disabled', 'disabled monitor is not healthy');
check(cached_view(null, config, 'boot-a', 110, null).reason == 'NO_RESULT', 'missing cached result explicit');
config.revision = 3; config.monitor.enabled = true;
let page = { ok: true, items: cached.run.checks, total: 7, offset: 2, has_more: true, next_cursor: 'opaque',
    metadata: { run_id: 'run-one', config_revision: 3, baseline_revision: 2, boot_id: 'boot-a',
        sampled_at: 100, max_age: 62, fresh: true, reason: null, scope: 'full_approved_baseline' } };
let old_page = refresh_page(page, config, 'boot-a', 200);
check(old_page.items[0].status == 'UNKNOWN' && old_page.metadata.reason == 'STALE' && !old_page.metadata.fresh,
    'continued page cannot retain sampled green after evidence expires');
check(old_page.total == 7 && old_page.offset == 2 && old_page.next_cursor == 'opaque' && old_page.items[1].status == 'DISABLED',
    'effective freshness preserves frozen denominator, cursor, ordering and disabled status');
check(page.items[0].status == 'PASS' && page.metadata.fresh, 'refresh never modifies stored sampled page');
config.revision = 4;
let new_scope = refresh_page(page, config, 'boot-a', 110);
check(new_scope.items[0].status == 'UNKNOWN' && new_scope.metadata.current_config_revision == 4 &&
    new_scope.metadata.scope == 'previous_approved_baseline' && new_scope.metadata.reason == 'CONFIG_CHANGED',
    'continuation rechecks configuration without replacing frozen rows');
check(refresh_page(page, config, 'boot-b', 110).items[0].status == 'UNKNOWN', 'configuration boundary remains conservative across boot');
config.revision = 3;
check(refresh_page(page, config, 'boot-b', 110).metadata.reason == 'BOOT_BOUNDARY', 'continued page rechecks boot');
check(refresh_page(page, config, 'boot-a', 99).metadata.reason == 'CLOCK_BOUNDARY', 'continued page rejects backwards clock');
check(refresh_page(page, null, 'boot-a', 110).reason == 'CONFIG_UNAVAILABLE', 'configuration loss never serves unvalidated green');
print('cache: ', n, ' assertions passed\n');
