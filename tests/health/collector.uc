// SPDX-License-Identifier: Apache-2.0
import { collect } from '../../luci-app-netbird/root/usr/share/netbird/health/collect.uc';
import { readfile, mkdtemp, mkdir, open, unlink, rmdir } from 'fs';
let fixtures = ARGV[0] || 'tests/health/fixtures';
let n = 0;
function check(ok, label) { if (!ok) die(`FAIL: ${label}\n`); printf('ok %d - %s\n', ++n, label); }
let mode = 'stable', links = 0;
// Fake procfs: 4242 is the long-lived daemon, 4343 a short `netbird status`
// client (watchdog/LuCI/collector), 4444 a replacement daemon incarnation.
let procfs = mkdtemp('/tmp/nbh-procfs.XXXXXX');
function proc_entry(pid, argv, start) {
    mkdir(procfs + '/' + pid, 0700);
    let f = open(procfs + '/' + pid + '/cmdline', 'w', 0600); f.write(join(chr(0), argv) + chr(0)); f.close();
    f = open(procfs + '/' + pid + '/stat', 'w', 0600);
    f.write(pid + ' (netbird) S 1 ' + pid + ' ' + pid + ' 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 10 0 ' + start + ' 0\n'); f.close();
}
proc_entry(4242, ['/usr/bin/netbird', 'service', 'run', '--log-level', 'info'], 63787988);
proc_entry(4343, ['/usr/bin/netbird', 'status', '--json'], 98350425);
proc_entry(4444, ['/usr/bin/netbird', 'service', 'run', '--log-level', 'info'], 98350500);
let self_pid = '4242', nft_calls = 0, text_calls = 0, pid_calls = 0;
let rule_calls = 0;
function runner(argv, timeout) {
    let command = join(' ', argv), out = '';
    if (index(command, 'status') >= 0) out = readfile(fixtures + '/status-0.82.0.json');
    else if (index(command, 'pidof') >= 0) {
        let second = pid_calls++ > 0;
        out = (mode == 'missing-process' ? '99999999' : mode == 'only-client' ? '4343' :
            mode == 'transient-client' && second ? '4242 4343' :
            mode == 'vanished-client' && second ? '4242 4545' :
            mode == 'daemon-restart' && second ? '4444' : self_pid) + '\n';
    }
    else if (index(command, 'rule') >= 0) out = readfile(fixtures + '/real-rules.json');
    else if (index(command, 'route get') >= 0) out = '[{"dst":"10.40.1.2","from":"192.0.2.10","dev":"mesh-alt","table":9911}]';
    else if (index(command, 'route') >= 0) out = readfile(fixtures + '/real-routes.json');
    else if (index(command, 'link') >= 0) {
        out = readfile(fixtures + '/real-links.json');
        if (mode == 'churn' && links++) out = replace(out, '1280', '1400');
    }
    else if (index(command, 'nft') >= 0) {
        out = sprintf('{"nftables":[{"table":{"family":"inet","name":"fw4","handle":%d}}]}', mode == 'firewall-churn' ? ++nft_calls : 1);
        if (mode == 'mixed-firewall') out = '{"nftables":[{"metainfo":true,"table":null}]}';
        if (mode == 'ipv6-table') out = '{"nftables":[{"table":{"family":"ip6","name":"filter","handle":8}}]}';
        if (mode == 'unknown-family') out = '{"nftables":[{"table":{"family":"unknown","name":"filter","handle":8}}]}';
    }
    if (mode == 'command-error' && index(command, 'rule') >= 0) {
        if (index(argv, '-j') >= 0) return { ok: false, reason: 'COMMAND_FAILED', stdout: '', exit_code: 2 };
        text_calls++; out = '0: from all lookup local\n';
    }
    if (mode == 'old-json' && index(command, 'rule') >= 0) {
        if (index(argv, '-j') >= 0) return { ok: false, reason: 'COMMAND_FAILED', json_unsupported: true, stdout: '', exit_code: 1 };
        out = '0: from all lookup local\n32766: from all lookup main\n';
    }
    if (mode == 'A01' || mode == 'A04') {
        if (index(command, 'rule') >= 0)
            out = mode == 'A01' ? '[{"priority":32766,"src":"all","table":"main"}]'
                : '[{"priority":77,"src":"all","iif":"br-business","table":9911},{"priority":32766,"src":"all","table":"main"}]';
        if (index(command, 'route') >= 0) out = '[{"dst":"10.40.0.0/16","dev":"mesh-alt","table":9911},{"dst":"default","gateway":"192.0.2.1","dev":"wan"}]';
        if (index(command, 'link') >= 0) out = '[{"ifindex":9,"ifname":"mesh-alt","flags":["UP"],"mtu":1280,"operstate":"UNKNOWN"}]';
    }
    if (mode == 'budget') return { ok: true, stdout: out, output_bytes: 65535, exit_code: 0 };
    if (mode == 'rule-churn' && index(command, 'rule') >= 0 && rule_calls++) out = '[{"priority":32766,"src":"all","table":"main"}]';
    if (mode == 'timeout' && index(command, 'status') >= 0) return { ok: false, reason: 'TIMEOUT', stdout: '', exit_code: null, duration_ms: 2000 };
    return { ok: true, stdout: out, exit_code: 0, duration_ms: 1 };
}
function collect_mode(m, paths) { mode = m; pid_calls = 0; return collect(runner, paths, procfs); }
let r = collect_mode('stable');
check(r.complete && r.agent.data.daemon_version == '0.82.0', 'stable generation yields complete collection');
r = collect_mode('transient-client');
check(r.complete && length(r.boundaries.after.processes) == 1 && r.boundaries.after.processes[0].pid == 4242,
    'short-lived netbird CLI client is not daemon generation identity');
r = collect_mode('vanished-client');
check(r.complete, 'client exiting between pidof and /proc read is not a generation change');
r = collect_mode('daemon-restart');
check(!r.complete && r.reason == 'GENERATION_CHANGED', 'daemon reincarnation still invalidates snapshot');
r = collect_mode('only-client');
check(!r.complete && r.reason == 'GENERATION_UNAVAILABLE', 'CLI client alone is not a running daemon');
check(r.rules.records[0].priority == 0 && r.routes.records[0].dst == 'default' && r.routes.records[0].gateway == '10.10.10.1', 'rule order and default gateway retained');
links = 0; r = collect_mode('churn');
check(!r.complete && r.reason == 'GENERATION_CHANGED', 'interface generation changes invalidate snapshot');
r = collect_mode('timeout');
check(!r.complete && r.agent.reason == 'COMMAND_TIMEOUT', 'agent timeout explicitly unknown');
r = collect_mode('command-error');
check(!r.complete && text_calls == 0, 'arbitrary failure cannot downgrade to text');
r = collect_mode('missing-process');
check(!r.complete && r.reason == 'GENERATION_UNAVAILABLE', 'absent process incarnation is not observed change');
r = collect_mode('firewall-churn');
check(!r.complete && r.reason == 'GENERATION_CHANGED', 'firewall recreation invalidates snapshot');
r = collect_mode('mixed-firewall');
check(!r.complete && !r.firewall.ok, 'mixed metadata cannot skip malformed firewall data');
r = collect_mode('ipv6-table');
check(r.complete && r.firewall.tables[0].family == 'ip6' && r.firewall.tables[0].handle == 8,
    'IPv6 table identity does not invalidate an IPv4 collection generation');
r = collect_mode('unknown-family');
check(!r.complete && !r.firewall.ok, 'unrecognized firewall family remains a parse failure');
r = collect_mode('budget');
check(!r.complete, 'aggregate budget includes stderr bytes');
r = collect_mode('old-json');
check(r.complete && r.rules.records[1].table == 'main', 'known JSON capability gap uses tested text parser');
r = collect_mode('A01');
check(r.complete && r.agent.data.daemon_status == 'Connected' && r.routes.records[0].table == '9911'
    && length(r.rules.records) == 1 && r.rules.records[0].table == 'main', 'A01 preserves connected plus orphaned target-table evidence, without inventing lookup');
r = collect_mode('A04');
check(r.complete && r.rules.records[0].priority == 77 && r.rules.records[0].table == r.routes.records[0].table
    && r.routes.records[0].dev == r.links.records[0].ifname && r.rules.records[0].iif == 'br-business', 'A04 preserves equivalent non-default interface/table/priority semantics');
let path = { id: 'business', approval: { approved: true }, source_ip: '192.0.2.10', destination: '10.40.1.2', ingress_interface: 'br-lan' };
r = collect_mode('stable', [path]);
check(r.complete && r.lookups.business.ok && r.lookups.business.table == '9911', 'lookup captured within stable generation window');
links = 0; r = collect_mode('churn', [path]);
check(!r.complete && !r.lookups.business.ok && r.lookups.business.reason == 'GENERATION_CHANGED', 'later generation change invalidates successful kernel lookup');
r = collect_mode('stable', [path, path]);
check(!r.complete && !r.lookups.business.ok, 'duplicate path identity cannot replace bound evidence');
rule_calls = 0; r = collect_mode('rule-churn');
check(!r.complete && r.boundaries.before.processes[0].pid == r.boundaries.after.processes[0].pid && r.boundaries.before.rules.records[0].priority == 0 && r.boundaries.after.rules.records[0].priority == 32766, 'same daemon PID cannot hide rule reconstruction');
check(r.engine.state == 'unknown' && r.attribution == 'cause_undetermined', 'unobserved engine identity and actor remain unknown');
printf('PASS: %d collector assertions\n', n);
