// SPDX-License-Identifier: Apache-2.0
import { readfile } from 'fs';
import { validate_config } from '../../luci-app-netbird/root/usr/share/netbird/health/config.uc';
let schema = json(readfile('luci-app-netbird/root/usr/share/netbird/health/config.schema.json'));
let fixture = readfile('tests/health/fixtures/config-valid.json');
let count = 0;
function check(ok, label) { if (!ok) die(label + '\n'); count++; }
function base() { return json(fixture); }
function valid(c) { return validate_config(c, schema).ok; }
check(valid(base()), 'existing approved baseline remains valid');
let c = base(); c.monitor.interval = 0;
check(!valid(c), 'bounded sampling interval');
c = base(); c.monitor.enabled = 'false';
check(!valid(c), 'typed boolean, not UCI truthiness');
for (let bound in [{ key: 'grace_period', low: 0, high: 600 },
    { key: 'convergence_timeout', low: 5, high: 600 }, { key: 'event_debounce', low: 1, high: 10 }]) {
    for (let value in [bound.low, bound.high]) {
        c = base(); c.monitor[bound.key] = value;
        check(valid(c), 'valid timing boundary: ' + bound.key);
    }
    for (let value in [bound.low - 1, bound.high + 1, '5', 5.5]) {
        c = base(); c.monitor[bound.key] = value;
        check(!valid(c), 'invalid timing cannot renew or busy-loop convergence: ' + bound.key);
    }
}
c = base(); c.paths[0].ingress_interface = 'br-lan;reboot';
check(!valid(c), 'interface injection');
c = base(); c.paths[0].normalized_cidr = '198.51.100.7/24';
check(!valid(c), 'host bits require explicit normalized network');
c = base(); c.paths[0].raw_cidr = '198.51.100.7/24';
check(valid(c), 'raw host bits retained alongside approved normalized prefix');
c = base(); c.paths[0].raw_cidr = '198.51.101.0/24';
check(!valid(c), 'raw and normalized networks cannot diverge');
c = base(); c.paths[0].source_ip = '192.0.2.999';
check(!valid(c), 'strict IPv4 source');
c = base(); c.paths[0].destination = '127.0.0.1';
check(!valid(c), 'loopback is not an approved network query target');
c = base(); c.paths[0].optional_mark = 4294967296;
check(!valid(c), 'mark uint32 boundary');
c = base(); push(c.paths, c.paths[0]);
check(!valid(c), 'duplicate path IDs');
function endpoint() { return { id: 'web', path_id: 'example-path', host: 'service.example',
    allowed_addresses: ['198.51.100.10'], protocol: 'HTTPS', port: 443,
    vantage: 'router_probe', http_path: '/ready', http_status: 204, enabled: true, required: true }; }
c = base(); push(c.endpoints, endpoint());
check(valid(c), 'approved FQDN and pinned address');
c.endpoints[0].allowed_addresses = ['169.254.169.254'];
check(!valid(c), 'metadata/link-local pin forbidden');
c.endpoints[0].allowed_addresses = ['203.0.113.10'];
check(!valid(c), 'resolved pin outside approved path prefix');
c.endpoints[0].allowed_addresses = ['198.51.100.10']; c.endpoints[0].host = '2130706433';
check(!valid(c), 'noncanonical numeric IP cannot masquerade as FQDN');
c.endpoints[0].host = '127.1';
check(!valid(c), 'short IPv4 spelling rejected');
c.endpoints[0].host = 'user:secret@service.example';
check(!valid(c), 'userinfo forbidden');
c.endpoints[0].host = 'service.example'; c.endpoints[0].http_path = '//other.example/private';
check(!valid(c), 'network-path reference forbidden');
c.endpoints[0].http_path = '/%2e%2e/private';
check(!valid(c), 'encoded path traversal forbidden');
c.endpoints[0].http_path = '/ready?token=secret';
check(!valid(c), 'credential-free probes cannot carry query secrets');
c.endpoints[0].http_path = '/ready'; c.endpoints[0].port = 65536;
check(!valid(c), 'port boundary');
c = base(); push(c.endpoints, endpoint()); c.endpoints[0].path_id = 'unknown';
check(!valid(c), 'endpoint must reference configured path');
c = base(); c.node.description = '<img src=x onerror=alert(1)>';
check(!valid(c), 'unknown description cannot bypass strict config schema');
c = base(); c.notification.sink_ref = '../../root/secret';
check(!valid(c), 'sink reference is not a filesystem path');
c = base(); c.paths[0].approval.approved_by = '<script>alert(1)</script>';
check(!valid(c), 'audit identity is bounded plain text');
print('config: ', count, ' assertions passed\n');
