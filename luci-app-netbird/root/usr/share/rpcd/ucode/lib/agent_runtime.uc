// SPDX-License-Identifier: Apache-2.0
// Platform adapter. Status is from the daemon, never the downloaded file version.
import { readfile, writefile, rename, access, stat } from 'fs';
import * as uci from 'uci';
function create(ctx) {
    const run = ctx.run;
    const q = ctx.quote;
    const guard = '[ ! -f /etc/netbird-update/transaction.json ] && [ ! -d /tmp/nb-binop.lock ] || NB_AGENT_WORKER=1 ucode /usr/share/netbird/agent-update-worker.uc guard >/dev/null 2>&1 || exit 0';
    function process() {
        let r = run('ubus call service list \'{"name":"netbird"}\'');
        try {
            let instances = json(r.out).netbird.instances;
            let result = null;
            for (let key, item in instances) if (item.running && item.pid > 0) {
                if (result) return null;
                result = item;
            }
            return result;
        } catch (e) { return null; }
    }
    let default_path = '';
    let default_stamp = '';
    function profile_file(proc) {
        if (!proc) return '';
        let args = proc.command || [];
        let path = '';
        for (let i = 0; i < length(args); i++) {
            if (args[i] == '--config' || args[i] == '-c') path = args[i + 1] || '';
            else if (index(args[i], '--config=') == 0) path = substr(args[i], 9);
        }
        if (path) return path;
        let env = split(readfile('/proc/' + proc.pid + '/environ') || '', '\x00');
        // Environment overrides are explicit. Unknown/dynamic profiles fail closed.
        for (let v in env) if (index(v, 'NB_CONFIG=') == 0) path = substr(v, 10);
        if (path) return path;
        let binary = stat('/usr/bin/netbird');
        let stamp = binary ? '' + binary.ino + ':' + binary.mtime : '';
        if (stamp != default_stamp) {
            let help = run('/usr/bin/netbird service run --help 2>/dev/null');
            let m = match(help.out, /--config string[^\n]*\(default "([^"\n]+)"\)/);
            default_path = m ? m[1] : '';
            default_stamp = stamp;
        }
        return default_path;
    }
    function real(path) { let r = run('readlink -f ' + q(path)); return r.code == 0 ? trim(r.out) : ''; }
    function profile_matches(path) {
        let proc = process();
        let file = profile_file(proc);
        if (!file || !match(file, /^\/[A-Za-z0-9_./-]+$/)) return false;
        let parent = replace(file, /\/[^/]+$/, '');
        return !!real(path) && real(path) == real(parent);
    }
    function sample() {
        let proc = process();
        if (!proc) return { ok: false };
        let status = ctx.status_json('/usr/bin/netbird');
        if (!status.ok || !status.data) return { ok: false, pid: '' + proc.pid };
        let js = status.data;
        let file = profile_file(proc);
        // Active profile switches are not compatible with an in-flight update.
        if (js.profileName && match(js.profileName, /^[A-Za-z0-9_.-]+$/) && file)
            file = replace(file, /\/[^/]+$/, '/' + js.profileName + '.json');
        let dns = null;
        try { let profile = json(readfile(file) || 'null'); dns = profile ? profile.DisableDNS : null; }
        catch (e) { return { ok: false, pid: '' + proc.pid }; }
        if (type(dns) != 'bool') return { ok: false, pid: '' + proc.pid };
        let resolver = run('sha256sum /etc/resolv.conf 2>/dev/null');
        let m = resolver.code == 0 ? match(resolver.out, /^([0-9a-f]{64})/) : null;
        if (!m) return { ok: false, pid: '' + proc.pid };
        return { ok: true, pid: '' + proc.pid, version: js.daemonVersion || '',
            public_key: js.publicKey || '', mesh_ip: js.netbirdIp || '',
            management_url: js.management ? js.management.url || '' : '',
            management_connected: !!(js.management && js.management.connected),
            signal_connected: !!(js.signal && js.signal.connected),
            dns_fingerprint: sprintf('%J', { disable_dns: dns,
                servers: js.dnsServers || [], resolver_sha256: m[1] }) };
    }
    function probe(url) {
        // No redirects, credentials, insecure TLS, retries, or proxy bypass of the
        // selected Mesh service. 2xx/3xx reachable endpoint, 4xx/5xx are unhealthy.
        if (!match(url || '', /^https?:\/\/[A-Za-z0-9][A-Za-z0-9.:-]*(\/[A-Za-z0-9_./?=&%:+~-]*)?$/)) return false;
        let iface = uci.cursor().get('netbird', 'settings', 'interface_name') || 'wt0';
        if (!match(iface, /^[A-Za-z0-9_.-]{1,15}$/)) return false;
        let r = run('/usr/bin/curl --noproxy "*" --interface ' + q(iface) + ' --silent --show-error --fail --connect-timeout 3 --max-time 5 --output /dev/null -- ' + q(url));
        return r.code == 0;
    }
    function external_guarded() {
        let text = readfile('/root/ztn-watchdog.sh') || '';
        let lines = split(text, '\n');
        return length(lines) >= 3 && match(lines[0], /^#!.*\/(ba)?sh/) && lines[1] == '# luci-netbird maintenance guard v1' && lines[2] == guard;
    }
    function integrate_watchdog() {
        if (external_guarded()) return { ok: true, data: { already: true } };
        let path = '/root/ztn-watchdog.sh';
        let s = stat(path);
        if (!s || s.uid != 0 || (s.mode & 18)) return { ok: false, message: 'Expected an existing root-owned non-writable external watchdog.' };
        let text = readfile(path) || '';
        let n = index(text, '\n');
        if (n < 0 || !match(substr(text, 0, n), /^#!.*\/(ba)?sh/)) return { ok: false, message: 'The external watchdog is not a supported shell script.' };
        if (access(path + '.before-netbird-update', 'f')) return { ok: false, message: 'A watchdog integration backup already exists; inspect it before retrying.' };
        if (run('cp -p ' + q(path) + ' ' + q(path + '.before-netbird-update') + ' && chmod 0600 ' + q(path + '.before-netbird-update') + ' && sync').code != 0)
            return { ok: false, message: 'Could not preserve the original external watchdog.' };
        let value = substr(text, 0, n + 1) + '# luci-netbird maintenance guard v1\n' + guard + '\n' + substr(text, n + 1);
        if (writefile(path + '.new-netbird-update', value) != length(value) ||
            run('chmod 0700 ' + q(path + '.new-netbird-update') + ' && sh -n ' + q(path + '.new-netbird-update') + ' && sync').code != 0 ||
            !rename(path + '.new-netbird-update', path) || run('sync').code != 0)
            return { ok: false, message: 'Could not atomically install the external watchdog guard; inspect the retained backup.' };
        return { ok: true, data: { integrated: true, backup: path + '.before-netbird-update' } };
    }
    function worker_alive() {
        let pid = trim(readfile('/tmp/luci-netbird-agent-update.pid') || '');
        if (!match(pid, /^[1-9][0-9]*$/)) return false;
        let cmd = readfile('/proc/' + pid + '/cmdline') || '';
        return index(cmd, 'agent-update-worker.uc') >= 0;
    }
    function spawn(mode) {
        if (mode != 'run' && mode != 'scheduled') return { ok: false, message: 'Invalid worker mode.' };
        let r = run('NB_AGENT_WORKER=1 NBLIB=' + q(ctx.lib) + ' setsid ucode /usr/share/netbird/agent-update-worker.uc ' + mode +
            ' </dev/null >/tmp/luci-netbird-agent-update.log 2>&1 & echo $!');
        let pid = trim(r.out);
        if (!match(pid, /^[1-9][0-9]*$/) || writefile('/tmp/luci-netbird-agent-update.pid', pid) != length(pid))
            return { ok: false, code: 'install_failed', message: 'Could not start or track the independent update worker.' };
        return { ok: true, data: { started: true, pid: int(pid) } };
    }
    return { sample: sample, profile_matches: profile_matches,
        daemon_pid: function() { let p = process(); return p ? '' + p.pid : ''; },
        profile_dir: function() { let file = profile_file(process()); return file ? real(replace(file, /\/[^/]+$/, '')) : ''; },
        probe: probe, external_guarded: external_guarded,
        arm_deadline: function() {
            let r = run('umask 077; NB_AGENT_WORKER=1 NBLIB=' + q(ctx.lib) + ' setsid ucode /usr/share/netbird/agent-update-worker.uc deadline' +
                ' </dev/null >/tmp/luci-netbird-agent-deadline.log 2>&1 & echo $!');
            return r.code == 0 && !!match(trim(r.out), /^[1-9][0-9]*$/);
        },
        monitor_running: function() {
            try {
                let r = run('ubus call service list \'{"name":"luci-netbird-updater"}\'');
                let service = json(r.out)['luci-netbird-updater'];
                for (let name, item in (service ? service.instances || {} : {}))
                    if (item.running && index(item.command || [], '/usr/share/netbird/agent-update-monitor.sh') >= 0) return true;
            } catch (e) {}
            return false;
        },
        integrate_watchdog: integrate_watchdog, worker_alive: worker_alive, spawn: spawn };
}
return { create: create };
