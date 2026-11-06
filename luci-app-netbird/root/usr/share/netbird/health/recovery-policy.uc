// SPDX-License-Identifier: Apache-2.0
import * as uci from 'uci';
import { lstat } from 'fs';
import { private_dir } from './storage.uc';
import { maintenance_state } from './maintenance.uc';
import { run_command } from './runner.uc';
function recovery_eligibility(held) {
    let state = maintenance_state();
    if (state.state == 'unknown' || state.markers.update_settings || state.markers.settings ||
        !held && state.markers.binary_operation || state.transaction_phase != null &&
        index(['committed', 'rolled_back', 'aborted', 'idle'], state.transaction_phase) < 0)
        return { ok: false, reason: 'ACTION_MAINTENANCE_CONFLICT' };
    // A check-only shell guard is not a lease. Do not silently disable, rewrite,
    // or race an existing user's independently scheduled recovery script.
    if (lstat('/root/ztn-watchdog.sh')) return { ok: false, reason: 'EXTERNAL_RECOVERER_CONFLICT' };
    let listed = run_command(['/bin/ubus', '-t', '1', 'call', 'service', 'list',
        '{"name":"luci-netbird-watchdog"}'], 1500), services;
    try { services = listed.ok ? json(listed.stdout) : null; } catch (e) {}
    if (type(services) != 'object') return { ok: false, reason: 'RECOVERER_STATE_UNKNOWN' };
    let watchdog = services['luci-netbird-watchdog'];
    if (watchdog != null) {
        if (type(watchdog.instances) != 'object') return { ok: false, reason: 'RECOVERER_STATE_UNKNOWN' };
        for (let name in keys(watchdog.instances)) {
            let instance = watchdog.instances[name];
            if (instance.running !== false) return { ok: false, reason: 'WATCHDOG_RECOVERER_CONFLICT' };
        }
    }
    if (!private_dir('/tmp/netbird-health') || !private_dir('/tmp/netbird-health/recovery-uci'))
        return { ok: false, reason: 'RECOVERY_STORAGE_UNAVAILABLE' };
    let cursor = uci.cursor('/etc/config', '/tmp/netbird-health/recovery-uci');
    if (cursor.get('netbird', 'settings') == null) return { ok: false, reason: 'AGENT_SETTINGS_UNKNOWN' };
    if (cursor.get('netbird', 'settings', 'service_enabled') != '1')
        return { ok: false, reason: 'AGENT_SERVICE_DISABLED' };
    if (cursor.get('netbird', 'runtime', 'desired_connected') == '0')
        return { ok: false, reason: 'AGENT_INTENTIONALLY_DISCONNECTED' };
    return { ok: true };
}
export { recovery_eligibility };
