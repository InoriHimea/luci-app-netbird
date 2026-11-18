// SPDX-License-Identifier: Apache-2.0
import * as socket from 'socket';
import { probe_endpoint, rdp_confirm, run_probe, approved_resolution } from '../../luci-app-netbird/root/usr/share/netbird/health/probe.uc';
let count = 0;
function check(ok, label) { if (!ok) die(label + '\n'); count++; }
let endpoint = { id: 'loopback', path_id: 'test', enabled: true, host: '127.0.0.1',
    protocol: 'TCP', port: 19421, vantage: 'router_probe', http_path: '/', http_status: 200 };
let server = socket.create(socket.AF_INET, socket.SOCK_STREAM | socket.SOCK_CLOEXEC);
if (server && (!server.bind({ address: '127.0.0.1', port: endpoint.port }) || !server.listen(16))) {
    server.close(); server = null;
}
check(server != null, 'isolated TCP listener');
let result = probe_endpoint(endpoint, 1000);
check(result.state == 'PASS' && result.source_ip == '127.0.0.1' &&
    result.destination_ip == '127.0.0.1' && result.vantage == 'router_probe', 'actual socket source');
check(run_probe(endpoint, 1000).state == 'PASS', 'bounded TCP worker actual connection');
for (let i = 0; i < 2; i++) {
    let peer = server.accept(null, socket.SOCK_CLOEXEC);
    check(peer != null, 'completed TCP probe reached the listener');
    peer.close();
}
endpoint.protocol = 'RDP';
let start = clock(true), stalled = run_probe(endpoint, 300), end = clock(true);
let elapsed = (end[0] - start[0]) * 1000 + (end[1] - start[1]) / 1000000;
check(stalled.state == 'UNKNOWN' && stalled.reason == 'TIMEOUT' && elapsed < 700,
    'silent RDP listener cannot block worker');
let rdp_peer = server.accept(null, socket.SOCK_CLOEXEC);
check(rdp_peer != null, 'bounded RDP probe reached the listener');
let request = rdp_peer.recv(256) || '';
rdp_peer.close();
check(length(request) == 19 && ord(request, 0) == 3 &&
    ord(request, 2) * 256 + ord(request, 3) == length(request) && ord(request, 5) == 224 &&
    ord(request, 11) == 1 && ord(request, 15) == 3,
    'actual RDP request has a binary X224 opcode and matching TPKT length');
endpoint.protocol = 'TCP';
server.close();
let unavailable = probe_endpoint(endpoint, 1000);
check(unavailable.state == 'UNKNOWN' && unavailable.reason == 'CONNECT_UNDETERMINED',
    'unclassified local or remote connect failure never establishes endpoint fault');
endpoint.vantage = 'lan_probe';
check(probe_endpoint(endpoint, 1000).reason == 'EXTERNAL_VANTAGE_REQUIRED', 'router cannot prove LAN');
endpoint.vantage = 'external_observer';
check(probe_endpoint(endpoint, 1000).reason == 'EXTERNAL_VANTAGE_REQUIRED', 'router cannot impersonate observer');
endpoint.vantage = 'router_probe'; endpoint.allowed_addresses = ['198.51.100.10'];
check(probe_endpoint(endpoint, 1000).reason == 'ADDRESS_SCOPE_INVALID', 'resolved loopback cannot bypass approved pins');
check(approved_resolution(endpoint, [{ addr: { address: '198.51.100.10' } }]) == '198.51.100.10', 'approved DNS answer selected');
check(approved_resolution(endpoint, [{ addr: { address: '198.51.100.10' } }, { addr: { address: '127.0.0.1' } }]) == null,
    'mixed safe and forbidden DNS answers fail closed');
check(approved_resolution(endpoint, [{ addr: { address: '::ffff:127.0.0.1' } }]) == null, 'mapped IPv6 cannot evade IPv4 policy');
delete endpoint.allowed_addresses;
endpoint.vantage = 'router_probe'; endpoint.host = 'user:secret@127.0.0.1';
check(probe_endpoint(endpoint, 1000).reason == 'ENDPOINT_INVALID', 'userinfo rejected');
endpoint.host = '127.0.0.1'; endpoint.http_path = '/\r\nAuthorization: secret';
check(probe_endpoint(endpoint, 1000).reason == 'ENDPOINT_INVALID', 'header injection rejected');
endpoint.http_path = '/'; endpoint.enabled = false;
check(probe_endpoint(endpoint, 1000).reason == 'ENDPOINT_INVALID', 'disabled endpoint never connected');
check(rdp_confirm('\x03\x00\x00\x0b\x06' + chr(208) + '\x00\x00\x00\x00\x00'), 'X224 confirm');
check(!rdp_confirm('\x03\x00\x00\x0b\x06' + chr(224) + '\x00\x00\x00\x00\x00'), 'request echo is not confirmation');
check(!rdp_confirm('\x03\x00\x00\x13\x06' + chr(208) + '\x00\x00\x00\x00\x00'), 'truncated TPKT rejected');
print('probe: ', count, ' assertions passed\n');
