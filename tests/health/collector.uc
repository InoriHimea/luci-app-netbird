// SPDX-License-Identifier: Apache-2.0
import { collect } from '../../luci-app-netbird/root/usr/share/netbird/health/collect.uc';
import { readfile } from 'fs';
let fixtures = ARGV[0] || 'tests/health/fixtures';
let n = 0;
function check(ok, label) { if (!ok) die(`FAIL: ${label}\n`); printf('ok %d - %s\n', ++n, label); }
let mode = 'stable', links = 0;
let self_pid = split(readfile('/proc/self/stat'), ' ')[0], nft_calls = 0, text_calls = 0;
let rule_calls = 0;
function runner(argv, timeout) {
    let command = join(' ', argv), out = '';
    if (index(command, 'status') >= 0) out = readfile(fixtures + '/status-0.82.0.json');
    else if (index(command, 'pidof') >= 0) out = (mode == 'missing-process' ? '99999999' : self_pid) + '\n';
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
let r = collect(runner);
check(r.complete && r.agent.data.daemon_version == '0.82.0', 'stable generation yields complete collection');
check(r.rules.records[0].priority == 0 && r.routes.records[0].dst == 'default' && r.routes.records[0].gateway == '10.10.10.1', 'rule order and default gateway retained');
mode = 'churn'; links = 0; r = collect(runner);
check(!r.complete && r.reason == 'GENERATION_CHANGED', 'interface generation changes invalidate snapshot');
mode = 'timeout'; r = collect(runner);
check(!r.complete && r.agent.reason == 'COMMAND_TIMEOUT', 'agent timeout explicitly unknown');
mode = 'command-error'; r = collect(runner);
check(!r.complete && text_calls == 0, 'arbitrary failure cannot downgrade to text');
mode = 'missing-process'; r = collect(runner);
check(!r.complete && r.reason == 'GENERATION_UNAVAILABLE', 'absent process incarnation is not observed change');
mode = 'firewall-churn'; r = collect(runner);
check(!r.complete && r.reason == 'GENERATION_CHANGED', 'firewall recreation invalidates snapshot');
mode = 'mixed-firewall'; r = collect(runner);
check(!r.complete && !r.firewall.ok, 'mixed metadata cannot skip malformed firewall data');
mode = 'ipv6-table'; r = collect(runner);
check(r.complete && r.firewall.tables[0].family == 'ip6' && r.firewall.tables[0].handle == 8,
    'IPv6 table identity does not invalidate an IPv4 collection generation');
mode = 'unknown-family'; r = collect(runner);
check(!r.complete && !r.firewall.ok, 'unrecognized firewall family remains a parse failure');
mode = 'budget'; r = collect(runner);
check(!r.complete, 'aggregate budget includes stderr bytes');
mode = 'old-json'; r = collect(runner);
check(r.complete && r.rules.records[1].table == 'main', 'known JSON capability gap uses tested text parser');
mode = 'A01'; r = collect(runner);
check(r.complete && r.agent.data.daemon_status == 'Connected' && r.routes.records[0].table == '9911'
    && length(r.rules.records) == 1 && r.rules.records[0].table == 'main', 'A01 preserves connected plus orphaned target-table evidence, without inventing lookup');
mode = 'A04'; r = collect(runner);
check(r.complete && r.rules.records[0].priority == 77 && r.rules.records[0].table == r.routes.records[0].table
    && r.routes.records[0].dev == r.links.records[0].ifname && r.rules.records[0].iif == 'br-business', 'A04 preserves equivalent non-default interface/table/priority semantics');
let path = { id: 'business', approval: { approved: true }, source_ip: '192.0.2.10', destination: '10.40.1.2', ingress_interface: 'br-lan' };
mode = 'stable'; r = collect(runner, [path]);
check(r.complete && r.lookups.business.ok && r.lookups.business.table == '9911', 'lookup captured within stable generation window');
mode = 'churn'; links = 0; r = collect(runner, [path]);
check(!r.complete && !r.lookups.business.ok && r.lookups.business.reason == 'GENERATION_CHANGED', 'later generation change invalidates successful kernel lookup');
mode = 'stable'; r = collect(runner, [path, path]);
check(!r.complete && !r.lookups.business.ok, 'duplicate path identity cannot replace bound evidence');
mode = 'rule-churn'; rule_calls = 0; r = collect(runner);
check(!r.complete && r.boundaries.before.processes[0].pid == r.boundaries.after.processes[0].pid && r.boundaries.before.rules.records[0].priority == 0 && r.boundaries.after.rules.records[0].priority == 32766, 'same daemon PID cannot hide rule reconstruction');
check(r.engine.state == 'unknown' && r.attribution == 'cause_undetermined', 'unobserved engine identity and actor remain unknown');
printf('PASS: %d collector assertions\n', n);
