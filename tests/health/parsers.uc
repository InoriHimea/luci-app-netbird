// SPDX-License-Identifier: Apache-2.0
import { parse_agent, parse_ip, select_peer } from '../../luci-app-netbird/root/usr/share/netbird/health/parsers.uc';
import { readfile } from 'fs';
let fixtures = ARGV[0] || 'tests/health/fixtures';
let n = 0;
function check(ok, label) { if (!ok) die(`FAIL: ${label}\n`); printf('ok %d - %s\n', ++n, label); }
for (let version in ['0.82.0', '0.78.1']) {
    let raw = readfile(`${fixtures}/status-${version}.json`);
    let p = parse_agent(raw);
    check(p.ok && p.data.daemon_version == version && type(p.data.management) == 'bool', `real ${version} status`);
}
let p = parse_agent('{"daemonStatus":"Connected","privateKey":"secret"}');
check(!p.ok && index(sprintf('%J', p), 'secret') < 0, 'incomplete status and secret rejected');
check(!parse_agent('{').ok, 'malformed status is unknown');
p = parse_agent('{"daemonVersion":"1","daemonStatus":"Connected","usesKernelInterface":false,"management":{"connected":true},"signal":{"connected":true},"peers":{"details":[{"netbirdIp":"100.64.0.1","status":"Idle","privateKey":"secret"}]}}');
check(p.ok && p.data.backend == 'userspace' && p.data.peers[0].status == 'Idle' && index(sprintf('%J', p), 'secret') < 0, 'userspace and Idle preserved without secret');
check(select_peer(p, '100.64.0.1').peer.status == 'Idle', 'exact approved peer selection preserves Idle');
check(select_peer(p, '100.64.0.2').reason == 'PEER_NOT_OBSERVED', 'missing approved peer cannot select a replacement');
check(!select_peer(p, '100.64.0.1;touch /tmp/x').ok, 'invalid peer selector rejected');
for (let kind in ['rules', 'routes', 'links']) {
    p = parse_ip(kind, readfile(`${fixtures}/real-${kind}.json`), 'json');
    check(p.ok, `real ${kind} JSON`);
}
p = parse_ip('rules', '77: from all iif br-business lookup 9911\n32766: from all lookup main\n', 'text');
check(p.ok && p.records[0].table == '9911' && p.records[0].priority == 77 && p.records[0].iif == 'br-business', 'equivalent layout not hardcoded');
p = parse_ip('routes', '10.40.0.0/16 dev mesh-alt table 9911 proto static scope link\ndefault via 192.0.2.1 dev wan\n', 'text');
check(p.ok && p.records[0].dev == 'mesh-alt' && p.records[1].gateway == '192.0.2.1', 'old ip route fallback');
check(!parse_ip('rules', '77: from all mysterious-selector yes lookup 9911', 'text').ok, 'unknown selector fails closed');
check(!parse_ip('rules', '[]', 'json').ok, 'empty rule collection is not normal');
check(!parse_ip('links', '[{}]', 'json').ok, 'missing link identity rejected');
check(!parse_ip('routes', '[{"dst":"default","dev":77}]', 'json').ok, 'wrong route field type rejected');
check(!parse_ip('routes', '[', 'json').ok, 'truncated JSON rejected');
check(!parse_ip('routes', '[{"dst":"default","nhid":17}]', 'json').ok, 'unresolved nexthop cannot disappear');
check(!parse_ip('routes', 'default dev eth0 dev eth1', 'text').ok, 'duplicate device rejected');
check(!parse_ip('rules', '77: from all lookup main lookup other', 'text').ok, 'duplicate rule table rejected');
check(!parse_ip('routes', 'not-an-ip-prefix dev eth0', 'text').ok, 'invalid destination rejected');
check(!parse_ip('routes', '192.0.2.0/99 dev eth0', 'text').ok, 'out-of-range prefix rejected');
check(!parse_ip('rules', '[{"priority":77,"table":9911,"fwmark":null}]', 'json').ok, 'explicit null selector rejected');
let status = json(readfile(fixtures + '/status-0.82.0.json'));
status.usesKernelInterface = 'true';
check(!parse_agent(sprintf('%J', status)).ok, 'malformed backend not silently unknown');
status.usesKernelInterface = true; status.daemonVersion = '';
check(!parse_agent(sprintf('%J', status)).ok, 'empty agent identity rejected');
p = parse_ip('rules', '[{"priority":42,"not":true,"src":"192.0.2.0","srclen":24,"fwmark":16,"fwmask":255,"table":9911}]', 'json');
check(p.ok && p.records[0].not === true && p.records[0].fwmark == 16 && p.records[0].fwmask == 255, 'inverted numeric-mark rule preserves selectors');
p = parse_ip('rules', '[{"priority":43,"src":"all","action":"blackhole"}]', 'json');
check(p.ok && p.records[0].action == 'blackhole' && p.records[0].table == null, 'terminal action does not require lookup table');
p = parse_ip('rules', '42: not from 192.0.2.0/24 fwmark 0x10/0xff lookup 9911\n43: from all prohibit', 'text');
check(p.ok && p.records[0].not === true && p.records[0].fwmask == '0xff' && p.records[1].action == 'prohibit', 'text invert mask and terminal action');
check(!parse_ip('rules', '[{"priority":1,"src":"all"}]', 'json').ok, 'missing lookup action cannot default to main');
check(!parse_ip('rules', '[{"priority":1,"table":9911,"not":"true"}]', 'json').ok, 'nonboolean inversion rejected');
check(!parse_ip('rules', '[{"priority":1,"table":9911,"fwmark":4294967296}]', 'json').ok, 'overflow mark rejected');
check(!parse_ip('rules', '42: not not from all lookup 9911', 'text').ok, 'duplicate inversion rejected');
p = parse_ip('rules', '[{"priority":105,"src":"all","table":"main","suppress_prefixlen":0}]', 'json');
check(p.ok && p.records[0].suppress_prefixlength === 0, '24.10 JSON spelling preserves default-route suppression');
check(!parse_ip('rules', '[{"priority":105,"table":"main","suppress_prefixlen":0,"suppress_prefixlength":8}]', 'json').ok,
    'ambiguous suppression spellings cannot silently replace a selector');
p = parse_ip('rules', '[{"priority":110,"not":null,"src":"all","fwmark":"0x1bd00","table":"netbird"}]', 'json');
check(p.ok && p.records[0].not === true && p.records[0].fwmark == '0x1bd00' && p.records[0].table == 'netbird',
    'legacy presence-only JSON inversion preserves the native marked rule');
printf('PASS: %d parser assertions\n', n);
