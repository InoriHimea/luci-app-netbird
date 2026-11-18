// SPDX-License-Identifier: Apache-2.0
import { evaluate_path } from 'netbird.health.evaluate';
import { aggregate } from 'netbird.health.model';
let count = 0;
function check(ok, name) { if (!ok) die('FAIL: ' + name); printf('ok %d - %s\n', ++count, name); }
function clone(value) { return json(sprintf('%J', value)); }
let path = { id: 'site', enabled: true, required: true,
    approval: { approved: true, baseline_revision: 1 },
    source_ip: '192.0.2.10', ingress_interface: 'br-business', destination: '198.51.100.5',
    expected_prefix: '198.51.100.0/24', allowed_egress: ['mesh-alt'], optional_mark: null,
    routing: { tables: ['9911'], native_priorities: [77], primary_peer: '100.64.0.1',
        backup_peers: ['100.64.0.2'], mark_reference: null, query_limitations: [] } };
let snapshot = { complete: true, generation: 'stable',
    rules: { ok: true, records: [ { priority: 77, src: 'all', table: '9911' },
        { priority: 32766, src: 'all', table: 'main' } ] },
    routes: { ok: true, records: [ { dst: '198.51.100.0/24', dev: 'mesh-alt', table: '9911' },
        { dst: 'default', dev: 'wan', table: 'main' } ] },
    links: { ok: true, records: [ { ifindex: 8, ifname: 'mesh-alt', flags: ['UP', 'LOWER_UP'], operstate: 'UNKNOWN' } ] } };
let lookup = { ok: true, table: '9911', dev: 'mesh-alt',
    source: path.source_ip, iif: path.ingress_interface, destination: path.destination, mark: null };
lookup.evidence = { kind: 'forward_lookup', path_id: path.id, path_source: path.source_ip, iif: path.ingress_interface,
    destination: path.destination, baseline_revision: 1, generation: 'stable', sampled_at: 90, expires_at: 110 };
function result(p, s, l) { return evaluate_path(p, s, l, 100); }
function category(r, name) { for (let c in r.checks) if (c.category == name) return c; return null; }
let r = result(path, snapshot, lookup);
check(category(r, 'rules').status == 'PASS' && category(r, 'forward').status == 'PASS', 'A04 equivalent approved layout');
let s = clone(snapshot); s.rules.records = [snapshot.rules.records[1]];
let l = clone(lookup); l.table = 'main'; l.dev = 'wan';
r = result(path, s, l);
check(category(r, 'rules').status == 'FAIL' && category(r, 'forward').code == 'FORWARD_LOOKUP_MISMATCH', 'A01 orphan table and actual WAN lookup fail');
s.rules.records = [{ priority: 12100, src: '192.0.2.0/24', dst: '198.51.100.0/24', iif: 'br-business', table: '9911' }, snapshot.rules.records[1]];
r = result(path, s, lookup);
check(category(r, 'rules').code == 'NATIVE_RULE_DRIFT' && category(r, 'rules').severity == 'warning' && category(r, 'forward').status == 'PASS', 'A02 fallback does not erase native drift');
s = clone(snapshot); push(s.routes.records, { dst: '198.51.100.5/32', dev: 'wan', table: '9911' });
r = result(path, s, l);
check(category(r, 'routes').code == 'ROUTE_SHADOWED' && category(r, 'routes').status == 'FAIL', 'A05 more specific route cannot hide behind expected prefix');
s = clone(snapshot); s.routes.records = [snapshot.routes.records[1]];
r = result(path, s, l);
check(category(r, 'routes').code == 'ROUTE_MISSING', 'A05 missing expected prefix');
s = clone(snapshot); s.rules.records = [{ priority: 1, src: 'all', table: 'main' }, snapshot.rules.records[0]];
r = result(path, s, l);
check(category(r, 'rules').code == 'RULE_SHADOWED', 'earlier reachable WAN route shadows approved rule');
function evidence(kind) {
    return { kind, path_id: path.id, path_source: path.source_ip, iif: path.ingress_interface,
        destination: path.destination, baseline_revision: 1, generation: 'stable', sampled_at: 90, expires_at: 110 };
}
s = clone(snapshot); s.selected_peer = { verified: true, address: '100.64.0.2', evidence: evidence('route_selection') };
r = result(path, s, lookup);
check(category(r, 'peer').code == 'BACKUP_TAKEOVER' && category(r, 'peer').severity == 'warning', 'A06 verified backup is redundancy degradation');
s.selected_peer = { verified: false, address: '100.64.0.2' };
r = result(path, s, lookup);
check(category(r, 'peer').status == 'UNKNOWN', 'unverified peer cannot claim takeover');
r = result(path, snapshot, lookup);
check(category(r, 'lan').status == 'UNKNOWN' && category(r, 'lan').code == 'NOT_CONFIGURED', 'A10 LAN obligation retained');
s = clone(snapshot); s.probes = { router: { status: 'PASS', fresh: true, evidence: evidence('router_probe') },
    lan: { status: 'FAIL', fresh: true, evidence: evidence('lan_probe') } };
r = result(path, s, lookup);
check(category(r, 'router').status == 'PASS' && category(r, 'lan').status == 'FAIL' && aggregate(r.checks).overall == 'unhealthy', 'A09 local success cannot override LAN failure');
let p = clone(path); p.approval.approved = false;
r = result(p, snapshot, lookup);
check(category(r, 'forward').status == 'UNKNOWN', 'A23 unapproved path cannot gain forwarding proof');
p = clone(path); p.routing.query_limitations = ['DNAT'];
r = result(p, snapshot, lookup);
check(category(r, 'forward').status == 'UNKNOWN' && category(r, 'forward').code == 'QUERY_LIMITED', 'DNAT query is not full-path proof');
l = clone(lookup); l.source = '192.0.2.11';
r = result(path, snapshot, l);
check(category(r, 'forward').status == 'UNKNOWN', 'lookup must belong to actual approved source');
s = clone(snapshot); s.complete = false;
r = result(path, s, lookup);
check(category(r, 'rules').status == 'UNKNOWN', 'inconsistent generation cannot pass');
r = result(path, snapshot, lookup);
check(r.attribution == 'UNKNOWN' && r.actions == null, 'A24 correlation never attributes actor or proposes mutation');
s = clone(snapshot); push(s.rules.records, { priority: 77, src: 'all', table: 'main' });
r = result(path, s, lookup);
check(category(r, 'rules').status == 'UNKNOWN' && category(r, 'rules').code == 'AMBIGUOUS_RULE', 'equal priorities cannot acquire order through sorting');
p = clone(path); p.expected_prefix = '198.51.100.7/24';
r = result(p, snapshot, lookup);
check(category(r, 'rules').code == 'INTENT_UNVERIFIED', 'approved prefix with host bits is not silently normalized');
s = clone(snapshot); s.selected_peer = { verified: true, address: '100.64.0.2', evidence: evidence('peer_presence') };
r = result(path, s, lookup);
check(category(r, 'peer').status == 'UNKNOWN', 'peer presence cannot prove route selection');
s.probes = { lan: { status: 'PASS', fresh: true, evidence: evidence('lan_probe') } };
s.probes.lan.evidence.path_id = 'another-path';
r = result(path, s, lookup);
check(category(r, 'lan').status == 'UNKNOWN', 'another path cannot satisfy LAN obligation');
s.probes.lan.evidence = evidence('lan_probe'); s.probes.lan.evidence.generation = 'old';
r = result(path, s, lookup);
check(category(r, 'lan').status == 'UNKNOWN', 'old generation probe cannot prove current forwarding');
s.probes.lan.evidence = evidence('lan_probe'); s.probes.lan.evidence.expires_at = 100;
r = result(path, s, lookup);
check(category(r, 'lan').status == 'UNKNOWN', 'expiry boundary overrides producer fresh flag');
s.probes.lan.evidence = evidence('router_probe');
r = result(path, s, lookup);
check(category(r, 'lan').status == 'UNKNOWN', 'router probe cannot be relabeled as LAN evidence');
s = clone(snapshot); push(s.routes.records, { dst: '198.51.100.5/32', dev: 'wan', table: '9911' });
push(s.links.records, { ifname: 'wan', flags: ['UP'] });
l = clone(lookup); l.dev = 'wan';
let exceptions = [{ id: 'approved-wan', object_id: path.id, authorization: 'change-7', reason: 'approved direct destination', expires_at: 110,
    route: { baseline_revision: 1, prefix: '198.51.100.5/32', table: '9911', egress: 'wan' } }];
r = evaluate_path(path, s, l, 100, exceptions);
check(category(r, 'routes').status == 'PASS' && category(r, 'forward').status == 'PASS', 'scoped approved WAN exception permits exact route');
exceptions[0].expires_at = 100;
r = evaluate_path(path, s, l, 100, exceptions);
check(category(r, 'routes').status == 'FAIL' && category(r, 'forward').status == 'FAIL', 'expired exception cannot permit forwarding');
exceptions[0].expires_at = 110; exceptions[0].object_id = 'other';
r = evaluate_path(path, s, l, 100, exceptions);
check(category(r, 'forward').status == 'FAIL', 'another path exception cannot widen approval');
exceptions[0].object_id = path.id; exceptions[0].route.prefix = '198.51.100.0/24';
r = evaluate_path(path, s, l, 100, exceptions);
check(category(r, 'forward').status == 'FAIL', 'exception requires exact installed route not broad destination match');
s = clone(snapshot); unshift(s.rules.records, { priority: 10, src: 'all', table: '100', suppress_prefixlength: 0 });
push(s.routes.records, { dst: 'default', type: 'blackhole', table: '100' });
r = result(path, s, lookup);
check(category(r, 'rules').status == 'FAIL', 'suppression cannot bypass a terminal route error');
p = clone(path); p.destination = '203.0.113.5';
s = clone(snapshot); push(s.routes.records, { dst: 'default', dev: 'mesh-alt', table: '9911' });
l = clone(lookup); l.destination = p.destination;
r = result(p, s, l);
check(category(r, 'rules').code == 'INTENT_UNVERIFIED', 'destination must belong to approved expected prefix');
l = clone(lookup); l.evidence = evidence('forward_lookup'); l.evidence.generation = 'old';
r = result(path, snapshot, l);
check(category(r, 'forward').status == 'UNKNOWN', 'old collection lookup cannot prove current forwarding');
p = clone(path); p.routing.tables = ['main', '9911']; p.routing.native_priorities = [105, 110];
s = clone(snapshot); s.rules.records = [
    { priority: 105, src: 'all', table: 'main', suppress_prefixlength: 0 },
    { priority: 110, src: 'all', fwmark: '0x1bd00', not: true, table: '9911' },
    { priority: 32766, src: 'all', table: 'main' }
];
r = result(p, s, lookup);
check(category(r, 'rules').status == 'PASS' && category(r, 'routes').status == 'PASS',
    'suppressed main default cannot shadow the selected mesh route');
delete s.rules.records[0].suppress_prefixlength;
r = result(p, s, lookup);
check(category(r, 'rules').code == 'RULE_SHADOWED' && category(r, 'routes').code == 'ROUTE_SHADOWED',
    'unsuppressed earlier main default still fails the effective path');
s.rules.records[0].suppress_prefixlength = 0;
push(s.routes.records, { dst: '198.51.100.5/32', dev: 'wan', table: 'main' });
r = result(p, s, lookup);
check(category(r, 'rules').code == 'RULE_SHADOWED' && category(r, 'routes').code == 'ROUTE_SHADOWED',
    'main specific route is not hidden by default-route suppression');
printf('PASS: %d evaluator assertions\n', count);
