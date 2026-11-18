// SPDX-License-Identifier: Apache-2.0
import { run_command } from './runner.uc';
import { permitted_address } from './config.uc';

// Called only inside the independently bounded cycle worker. This is not a
// LAN forward-path test: the socket belongs to this router's network stack.
function valid_endpoint(e) {
    return type(e) == 'object' && e.enabled === true &&
        type(e.host) == 'string' && length(e.host) <= 253 &&
        match(e.host, /^[A-Za-z0-9][A-Za-z0-9.:-]*$/) &&
        type(e.port) == 'int' && e.port > 0 && e.port <= 65535 &&
        index(['TCP', 'ICMP', 'HTTP', 'HTTPS', 'RDP'], e.protocol) >= 0 &&
        type(e.http_path) == 'string' && length(e.http_path) <= 512 &&
        match(e.http_path, /^\/[^\r\n]*$/) && index(e.http_path, '\x00') < 0 &&
        type(e.http_status) == 'int' && e.http_status >= 100 && e.http_status <= 599;
}
function rdp_confirm(data) {
    // TPKT + X.224 connection confirm only; never send credentials or logon.
    if (type(data) != 'string' || length(data) < 11 || ord(data, 0) != 3 ||
        ord(data, 1) != 0 || ord(data, 5) != 0xd0) return false;
    let size = ord(data, 2) * 256 + ord(data, 3);
    return size == length(data) && ord(data, 4) >= 6 && ord(data, 4) + 5 == size;
}
function approved_resolution(endpoint, addresses) {
    if (type(endpoint.allowed_addresses) != 'array' || !length(endpoint.allowed_addresses) ||
        length(endpoint.allowed_addresses) > 8 || type(addresses) != 'array' ||
        !length(addresses) || length(addresses) > 32) return null;
    for (let row in addresses) {
        let address = row?.addr?.address;
        if (!permitted_address(address) || index(endpoint.allowed_addresses, address) < 0) return null;
    }
    return addresses[0].addr.address;
}
function probe_endpoint(e, timeout_ms) {
    let result = { endpoint_id: e?.id, path_id: e?.path_id,
        vantage: 'router_probe', state: 'UNKNOWN', reason: 'ENDPOINT_INVALID',
        protocol: e?.protocol, source_ip: null, destination_ip: null,
        http_status: null, attribution: 'cause_undetermined' };
    if (!valid_endpoint(e) || type(timeout_ms) != 'int' || timeout_ms < 1 || timeout_ms > 20000)
        return result;
    if (e.vantage != 'router_probe') {
        result.reason = 'EXTERNAL_VANTAGE_REQUIRED';
        return result;
    }
    let socket;
    try { socket = require('socket'); }
    catch (err) { result.reason = 'SOCKET_UNAVAILABLE'; return result; }
    let destination = e.host;
    // Direct protocol helpers remain privileged local primitives. The approved
    // configuration schema requires pins for every production cycle endpoint.
    if ('allowed_addresses' in e) {
        let addresses = socket.addrinfo(e.host, null, { family: socket.AF_UNSPEC, socktype: socket.SOCK_STREAM });
        destination = approved_resolution(e, addresses);
        if (!destination) { result.reason = 'ADDRESS_SCOPE_INVALID'; return result; }
    }
    if (e.protocol == 'HTTP' || e.protocol == 'HTTPS') {
        let scheme = lc(e.protocol), host = index(e.host, ':') >= 0 ? '[' + e.host + ']' : e.host;
        let argv = ['/usr/bin/curl', '-q', '--noproxy', '*', '--globoff',
            '--proto', '=' + scheme, '--max-time', sprintf('%.3f', timeout_ms / 1000.0),
            '--connect-timeout', sprintf('%.3f', timeout_ms / 1000.0),
            '--silent', '--output', '/dev/null', '--write-out', '%{local_ip}\n%{remote_ip}\n%{http_code}\n',
            '--url', scheme + '://' + host + ':' + e.port + e.http_path];
        if ('allowed_addresses' in e) { push(argv, '--resolve'); push(argv, e.host + ':' + e.port + ':' + destination); }
        let r = run_command(argv, timeout_ms);
        let lines = split(trim(r.stdout), '\n');
        if (length(lines) == 3 && iptoarr(lines[0]) && iptoarr(lines[1])) {
            result.source_ip = lines[0]; result.destination_ip = lines[1];
            result.http_status = int(lines[2]);
        }
        if ('allowed_addresses' in e && result.destination_ip != null && result.destination_ip != destination) {
            result.reason = 'ADDRESS_SCOPE_INVALID'; return result;
        }
        if (!r.ok) { result.reason = r.reason; return result; }
        if (!result.source_ip) { result.reason = 'SOURCE_UNOBSERVED'; return result; }
        result.state = result.http_status == e.http_status ? 'PASS' : 'FAIL';
        result.reason = result.state == 'PASS' ? null : 'HTTP_STATUS_MISMATCH';
        return result;
    }
    if (e.protocol == 'ICMP') {
        // Linux ping datagram sockets: observe the actual ICMP socket source,
        // not a different protocol's route selection. No raw capability needed.
        let addresses = socket.addrinfo(destination, null, { family: socket.AF_INET, socktype: socket.SOCK_DGRAM });
        let target = addresses?.[0]?.addr?.address;
        if (!target) { result.reason = 'ICMP_RESOLUTION_UNAVAILABLE'; return result; }
        let connection = socket.create(socket.AF_INET, socket.SOCK_DGRAM | socket.SOCK_CLOEXEC, 1);
        if (!connection) { result.reason = 'ICMP_SOCKET_UNAVAILABLE'; return result; }
        if (!connection.connect({ address: target, port: 0 })) {
            connection.close(); result.reason = 'ICMP_CONNECT_FAILED'; return result;
        }
        let local = connection.sockname(), packet = '\x08\x00\x00\x00\x00\x00\x00\x01nbh';
        if (connection.send(packet) != length(packet)) {
            connection.close(); result.reason = 'ICMP_SEND_FAILED'; return result;
        }
        let response = connection.recvmsg(256), data = response?.data;
        result.source_ip = local?.address;
        result.destination_ip = response?.address?.address;
        connection.close();
        if (!result.source_ip || !result.destination_ip) { result.reason = 'SOURCE_UNOBSERVED'; return result; }
        let valid = type(data) == 'string' && length(data) == length(packet) &&
            ord(data, 0) == 0 && ord(data, 1) == 0 &&
            ord(data, 4) * 256 + ord(data, 5) == local.port &&
            substr(data, 6) == substr(packet, 6) && result.destination_ip == target;
        result.state = valid ? 'PASS' : 'FAIL';
        result.reason = valid ? null : 'ICMP_REPLY_INVALID';
        return result;
    }
    let connection = socket.connect(destination, e.port, { socktype: socket.SOCK_STREAM }, timeout_ms);
    if (!connection) { result.reason = 'CONNECT_UNDETERMINED'; return result; }
    result.source_ip = connection.sockname()?.address;
    result.destination_ip = connection.peername()?.address;
    if ('allowed_addresses' in e && result.destination_ip != destination) {
        connection.close(); result.reason = 'ADDRESS_SCOPE_INVALID'; return result;
    }
    if (!result.source_ip || !result.destination_ip) {
        connection.close(); result.reason = 'SOURCE_UNOBSERVED'; return result;
    }
    if (e.protocol == 'TCP') {
        connection.close(); result.state = 'PASS'; result.reason = null; return result;
    }
    // The surrounding worker deadline also bounds send/recv and name lookup.
    let request = '\x03\x00\x00\x13\x0e' + chr(224) + '\x00\x00\x00\x00\x00\x01\x00\x08\x00\x03\x00\x00\x00';
    if (connection.send(request) != length(request)) {
        connection.close(); result.reason = 'RDP_SEND_FAILED'; return result;
    }
    let data = '';
    while (length(data) < 256) {
        let part = connection.recv(256 - length(data));
        if (!part) break;
        data += part;
        if (length(data) >= 4 && length(data) >= ord(data, 2) * 256 + ord(data, 3)) break;
    }
    connection.close();
    result.state = rdp_confirm(data) ? 'PASS' : 'FAIL';
    result.reason = result.state == 'PASS' ? null : 'RDP_CONFIRM_INVALID';
    return result;
}
// Public cycle entry: DNS and protocol reads are bounded even if libc blocks.
function run_probe(e, timeout_ms) {
    if (!valid_endpoint(e) || e.vantage != 'router_probe')
        return probe_endpoint(e, timeout_ms);
    let r = run_command(['/usr/bin/ucode', '/usr/share/netbird/health/probe-worker.uc',
        sprintf('%J', e), '' + timeout_ms], timeout_ms);
    if (r.ok) {
        try {
            let result = json(r.stdout);
            if (type(result) == 'object' && result.endpoint_id == e.id && result.path_id == e.path_id) {
                result.duration_ms = r.duration_ms;
                result.exit_code = r.exit_code;
                return result;
            }
        }
        catch (err) {}
    }
    return { endpoint_id: e.id, path_id: e.path_id, vantage: 'router_probe',
        protocol: e.protocol, state: 'UNKNOWN', reason: r.reason || 'PROBE_RESULT_INVALID',
        duration_ms: r.duration_ms, exit_code: r.exit_code,
        source_ip: null, destination_ip: null, http_status: null, attribution: 'cause_undetermined' };
}
export { valid_endpoint, rdp_confirm, probe_endpoint, run_probe, approved_resolution };
