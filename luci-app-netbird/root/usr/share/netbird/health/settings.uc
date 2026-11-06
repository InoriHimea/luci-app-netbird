// SPDX-License-Identifier: Apache-2.0
import * as uci from 'uci';
import { open } from 'fs';
import { private_dir } from './storage.uc';
import { validate_config } from './config.uc';
function create_settings(config_dir, root) {
    function read_config() {
        try {
            // Use a private savedir, not another client's uncommitted /tmp/.uci.
            let cursor = uci.cursor(config_dir, root + '/uci');
            let raw = cursor.get('netbird_health', 'main', 'approved_config');
            if (type(raw) != 'string' || length(raw) > 65536) return null;
            let config = json(raw);
            return validate_config(config).ok ? config : null;
        }
        catch (e) { return null; }
    }
    function save_config(config, expected_revision) {
        let valid = validate_config(config);
        if (!valid.ok) return valid;
        if (type(expected_revision) != 'int' || expected_revision < 0 || expected_revision >= 2147483647)
            return { ok: false, reason: 'REVISION_INVALID' };
        if (!private_dir(root) || !private_dir(root + '/uci')) return { ok: false, reason: 'STORAGE_UNAVAILABLE' };
        let lock = open(root + '/config.lock', 'a', 0600);
        if (!lock || !lock.lock('xn')) { if (lock) lock.close(); return { ok: false, reason: 'CONFIG_BUSY' }; }
        let result;
        try {
            let current = read_config();
            if (!current) result = { ok: false, reason: 'CONFIG_UNAVAILABLE' };
            else if (current.revision != expected_revision || config.revision != expected_revision)
                result = { ok: false, reason: 'REVISION_CONFLICT', revision: current.revision };
            else {
                let next = json(sprintf('%J', config));
                next.revision = expected_revision + 1;
                let cursor = uci.cursor(config_dir, root + '/uci');
                let committed = cursor.set('netbird_health', 'main', 'approved_config', sprintf('%J', next)) && cursor.commit('netbird_health');
                result = committed ? { ok: true, revision: next.revision } : { ok: false, reason: 'CONFIG_COMMIT_FAILED' };
            }
        }
        catch (e) { result = { ok: false, reason: 'CONFIG_COMMIT_FAILED' }; }
        lock.close();
        return result;
    }
    return { read_config, save_config };
}
let settings = create_settings('/etc/config', '/tmp/netbird-health');
let read_config = settings.read_config, save_config = settings.save_config;
export { create_settings, read_config, save_config };
