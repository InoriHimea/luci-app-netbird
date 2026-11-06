# SPDX-License-Identifier: Apache-2.0
"""Independent Linux central collector. No listener, agent control, or owner failover."""
import argparse
import copy
import hashlib
import http.client
import json
import os
from pathlib import Path
import signal
import ssl
import stat
import sys
import time
from urllib.parse import urlsplit
import uuid
from .lan_probe import validate_config as validate_probe_config, validate_result
from .model import admit_events, aggregate_site, anchor_sample, observe_node, sample_current, VANTAGES
from .transport import (ObserverError, atomic_json, bounded, decode_json, identifier,
                        private_directory, read_private_json, ssh_json, validate_ssh)


def visibility(previous, failure, *, key, node_id, wall, minimum_interval):
    state = dict(previous or {})
    if failure == 'MONITOR_DISABLED':
        state.update(bad=0, good=0)
        return state, []
    if wall - state.get('last_vote', -minimum_interval) < minimum_interval:
        return state, []
    state['last_vote'] = wall
    state['bad'] = state.get('bad', 0) + 1 if failure else 0
    state['good'] = 0 if failure else state.get('good', 0) + 1
    events = []
    kind = None
    if failure and state['bad'] >= 3 and not state.get('active'):
        state.update(active=True, episode_id=str(uuid.uuid4()), failure=failure)
        kind = 'failure'
    elif not failure and state['good'] >= 2 and state.get('active'):
        state['active'] = False
        kind = 'recovery'
    if kind:
        category = state['failure']
        event_id = hashlib.sha256(json.dumps([node_id, key, category, state['episode_id'], kind],
                                             separators=(',', ':')).encode()).hexdigest()
        events.append(dict(id=event_id, episode_id=state['episode_id'], node_id=node_id, kind=kind,
                           created_at=wall, owner='central', categories=[category],
                           details=[dict(category=category, id=key, code=category, severity='warning')]))
    if not failure and not state.get('active'):
        state['failure'] = None
    return state, events


def _pending_visibility(previous, failure, **arguments):
    if previous and previous.get('pending_event'):
        return dict(previous), [previous['pending_event']]
    state, events = visibility(previous, failure, **arguments)
    if events:
        state['pending_event'] = events[0]
    return state, events


def validate_config(c):
    fields = {'schema_version', 'enabled', 'collector_id', 'interval_seconds', 'poll_budget_ms',
              'max_age', 'nodes', 'lan', 'notifications'}
    if (type(c) is not dict or set(c) != fields or type(c['schema_version']) is not int or c['schema_version'] != 1
            or type(c['enabled']) is not bool):
        raise ObserverError('CONFIG_INVALID')
    identifier(c['collector_id'])
    for key, low, high in [('interval_seconds', 10, 3600), ('poll_budget_ms', 500, 60000), ('max_age', 10, 86400)]:
        if type(c[key]) is not int or not low <= c[key] <= high:
            raise ObserverError('CONFIG_INVALID')
    if c['max_age'] < 2*c['interval_seconds'] or c['poll_budget_ms'] >= 1000*c['interval_seconds']:
        raise ObserverError('CONFIG_BUDGET_INVALID')
    if any(type(c[k]) is not dict or len(c[k]) > 32 for k in ('nodes', 'lan')):
        raise ObserverError('CONFIG_INVALID')
    for node_id, spec in c['nodes'].items():
        identifier(node_id); validate_ssh(spec)
    for key, spec in c['lan'].items():
        identifier(key)
        if type(spec) is not dict or set(spec) != {'ssh', 'expected', 'node_id'} or spec['node_id'] not in c['nodes']:
            raise ObserverError('LAN_CONFIG_INVALID')
        validate_ssh(spec['ssh'])
        e = spec['expected']
        if type(e) is not dict or set(e) != {'probe_id', 'target_id', 'source', 'interface', 'gateway', 'baseline_revision',
                                           'address', 'port', 'protocol', 'timeout_ms'}:
            raise ObserverError('LAN_CONFIG_INVALID')
        validate_probe_config(dict(schema_version=1, enabled=True,
                                   **{k: e[k] for k in ('probe_id', 'source', 'interface', 'gateway', 'baseline_revision')},
                                   targets={e['target_id']: {k: e[k] for k in ('address', 'port', 'protocol', 'timeout_ms')}}))
    n = c['notifications']
    if (type(n) is not dict or set(n) != {'owner', 'sink_file'} or n['owner'] not in ('none', 'central')
            or n['sink_file'] is not None and (not isinstance(n['sink_file'], str) or
                not n['sink_file'].startswith('/') or len(n['sink_file']) > 1024)):
        raise ObserverError('NOTIFICATION_CONFIG_INVALID')
    return c


def empty_state():
    return dict(schema_version=1, nodes={}, lan={}, visibility={}, seen={}, outbox=[],
                last_poll_at=0, last_poll_monotonic=0, collector_boot=None, last_delivery_at=0, delivery_reason=None)


def load_state(path):
    try:
        state = read_private_json(path)
    except FileNotFoundError:
        return empty_state()
    if (type(state) is not dict or set(state) != set(empty_state()) or type(state['schema_version']) is not int
            or state['schema_version'] != 1 or any(type(state[k]) is not dict for k in ('nodes', 'lan', 'visibility', 'seen'))
            or len(state['nodes']) > 32 or len(state['lan']) > 32 or len(state['visibility']) > 64
            or len(state['seen']) > 1024 or type(state['outbox']) is not list or len(state['outbox']) > 32
            or any(type(state[k]) is not int or state[k] < 0 for k in ('last_poll_at', 'last_delivery_at'))
            or type(state['last_poll_monotonic']) not in (int, float)):
        raise ObserverError('STATE_INVALID')
    for node in state['nodes'].values():
        if (type(node) is not dict or not {'last_source', 'collector_boot', 'observed_at', 'observed_monotonic',
                'coverage', 'overall', 'fresh', 'sampled_at'} <= set(node)
                or type(node['observed_at']) is not int or type(node['observed_monotonic']) not in (int, float)):
            raise ObserverError('STATE_INVALID')
    for record in state['outbox']:
        if (type(record) is not dict or not {'key', 'event', 'status', 'attempts', 'next_attempt'} <= set(record)
                or record['status'] not in ('queued', 'submitted', 'unknown', 'failed', 'accepted')
                or type(record['attempts']) is not int or not 0 <= record['attempts'] <= 3
                or type(record['next_attempt']) is not int):
            raise ObserverError('STATE_INVALID')
    return state


def _boot():
    return Path('/proc/sys/kernel/random/boot_id').read_text().strip()


def view(c, state, *, wall, monotonic, boot):
    nodes = []
    for node_id in c['nodes']:
        node = copy.deepcopy(state['nodes'].get(node_id))
        if not node:
            node = observe_node(None, None, node_id=node_id, wall=wall, monotonic=monotonic,
                                collector_boot=boot, max_age=c['max_age'], failure='NOT_COLLECTED')
        elif (node['collector_boot'] != boot or wall < node['observed_at'] or
                not 0 <= monotonic-node['observed_monotonic'] <= c['max_age'] or wall - node['observed_at'] > c['max_age'] or
                node.get('fresh') and (type(node.get('sampled_at')) is not int or
                    wall - node['sampled_at'] > min(c['max_age'], node.get('max_age', c['max_age'])) or
                    not sample_current(node.get('last_source'), monotonic=monotonic, collector_boot=boot))):
            node = observe_node(node, None, node_id=node_id, wall=wall, monotonic=monotonic,
                                collector_boot=boot, max_age=c['max_age'], failure='RESULT_STALE')
        node.pop('events', None)
        nodes.append(node)
    lan = {}
    for key in c['lan']:
        item = state['lan'].get(key)
        poll_current = (state['collector_boot'] == boot and 0 <= wall-state['last_poll_at'] <= c['max_age']
                        and 0 <= monotonic-state['last_poll_monotonic'] <= c['max_age'])
        if type(item) is dict and item.get('status') == 'UNKNOWN' and poll_current:
            lan[key] = item
        elif (type(item) is not dict or item.get('fresh') is not True or type(item.get('sampled_at')) is not int
                or not 0 <= wall-item['sampled_at'] <= c['max_age'] or not poll_current
                or not sample_current(item.get('last_source'), monotonic=monotonic, collector_boot=boot)
                or not all(type(item.get(k)) is type(v) and item[k] == v for k, v in c['lan'][key]['expected'].items())
                or wall < state['last_poll_at'] or monotonic < state['last_poll_monotonic']):
            lan[key] = dict(status='UNKNOWN', fresh=False, reason='PROBE_STALE' if item else 'PROBE_UNAVAILABLE')
        else:
            lan[key] = item
    site = aggregate_site(nodes, c['lan'], lan)
    if not c['enabled']:
        site['overall'] = 'disabled'
        site['coverage'] = dict.fromkeys(VANTAGES, 'unknown')
    return dict(schema_version=1, collector_id=c['collector_id'], sampled_at=state['last_poll_at'], served_at=wall,
                enabled=c['enabled'], site=site,
                delivery=dict(owner=c['notifications']['owner'], reason=state['delivery_reason'],
                              queued=sum(r['status'] == 'queued' or r['status'] == 'failed' and r['attempts'] < 3
                                         for r in state['outbox']),
                              failed=sum(r['status'] == 'failed' and r['attempts'] >= 3 for r in state['outbox']),
                              unknown=sum(r['status'] in ('submitted', 'unknown') for r in state['outbox']),
                              provider_accepted=sum(r['status'] == 'accepted' for r in state['outbox']),
                              receipt_verified=False))


def _enqueue(state, incoming, wall):
    # Terminal outcomes may leave the bounded display, never the live dedup ledger.
    for event in incoming:
        admitted = admit_events(state['seen'], [event], now=wall)
        if not admitted['accepted']:
            state['seen'] = admitted['state']
            if admitted['reason']:
                state['delivery_reason'] = admitted['reason']
            continue
        if len(state['outbox']) >= 32:
            terminal = next((i for i, r in enumerate(state['outbox']) if r['status'] in ('accepted', 'unknown')
                             or r['status'] == 'failed' and r['attempts'] >= 3), None)
            if terminal is None:
                state['delivery_reason'] = 'QUEUE_CAPACITY'; break
            del state['outbox'][terminal]
        state['seen'] = admitted['state']
        if admitted['reason']:
            state['delivery_reason'] = admitted['reason']
        for public in admitted['accepted']:
            key = hashlib.sha256(json.dumps([public['node_id'], public['id']], separators=(',', ':')).encode()).hexdigest()
            state['outbox'].append(dict(key=key, event=public, status='queued', attempts=0,
                                        next_attempt=wall, receipt_verified=False))


def deliver(path, key, sink_file):
    # An independent hard deadline also applies if the coordinator dies during DNS/TLS.
    signal.signal(signal.SIGALRM, signal.SIG_DFL)
    signal.setitimer(signal.ITIMER_REAL, 4)
    state = load_state(path)
    record = next((r for r in state['outbox'] if r['key'] == key and r['status'] == 'submitted'), None)
    if record is None:
        raise ObserverError('DELIVERY_NOT_SUBMITTED')
    backend = read_private_json(sink_file)
    if (type(backend) is not dict or set(backend) != {'endpoint', 'token', 'ca_file'}
            or not isinstance(backend['endpoint'], str) or not isinstance(backend['token'], str)
            or not 1 <= len(backend['token']) <= 8192 or any(ord(c) < 33 or ord(c) > 126 for c in backend['token'])):
        raise ObserverError('SINK_INVALID')
    url = urlsplit(backend['endpoint'])
    if (url.scheme != 'https' or not url.hostname or url.username is not None or url.password is not None
            or url.query or url.fragment or url.path != '/message'
            or backend['ca_file'] is not None and not isinstance(backend['ca_file'], str)):
        raise ObserverError('SINK_INVALID')
    connection = http.client.HTTPSConnection(url.hostname, url.port or 443, timeout=2,
                    context=ssl.create_default_context(cafile=backend['ca_file']))
    event = record['event']
    message = dict(title='NetBird ' + event['kind'], priority=5,
                   message=json.dumps(event, ensure_ascii=True, separators=(',', ':')))
    try:
        connection.request('POST', '/message', body=json.dumps(message).encode(),
                           headers={'Content-Type': 'application/json', 'X-Gotify-Key': backend['token']})
        response = connection.getresponse()
        return dict(status='accepted' if 200 <= response.status < 300 else 'failed', receipt_verified=False)
    finally:
        connection.close()


def _send_one(c, state, state_path, deadline):
    notifications = c['notifications']
    if notifications['owner'] != 'central' or notifications['sink_file'] is None:
        state['delivery_reason'] = 'OWNER_NONE' if notifications['owner'] == 'none' else 'SINK_NOT_CONFIGURED'
        return
    wall = int(time.time())
    if wall-state['last_delivery_at'] < 60 or deadline-time.monotonic() < 1:
        return
    record = next((r for r in state['outbox'] if r['status'] in ('queued', 'failed')
                   and r['attempts'] < 3 and r['next_attempt'] <= wall), None)
    if record is None:
        return
    record.update(status='submitted', attempts=record['attempts']+1, receipt_verified=False)
    state['last_delivery_at'] = wall
    atomic_json(state_path, state)  # The at-most-once boundary precedes any network action.
    try:
        result = bounded([sys.executable, '-m', 'observer.central', 'deliver', '--state', str(state_path),
                          '--sink', notifications['sink_file'], '--event', record['key']],
                         min(3, deadline-time.monotonic()), 8192)
        response = decode_json(result['stdout']) if result['exit'] == 0 else None
        status = response.get('status') if type(response) is dict else None
        record['status'] = status if status in ('accepted', 'failed') else 'unknown'
    except ObserverError:
        record['status'] = 'unknown'
    record['next_attempt'] = wall + 60 * 2**record['attempts']
    state['delivery_reason'] = {'accepted': None, 'failed': 'PROVIDER_REJECTED', 'unknown': 'DELIVERY_UNKNOWN'}[record['status']]


def cycle(c, state, state_path):
    wall, monotonic, boot = int(time.time()), time.monotonic(), _boot()
    if not c['enabled']:
        return view(c, state, wall=wall, monotonic=monotonic, boot=boot)
    if (state['collector_boot'] == boot and wall >= state['last_poll_at']
            and 0 <= monotonic-state['last_poll_monotonic'] < c['interval_seconds']):
        return view(c, state, wall=wall, monotonic=monotonic, boot=boot)
    for record in state['outbox']:
        if record['status'] == 'submitted':
            record['status'] = 'unknown'  # A lost result is never automatically replayed.
    deadline = monotonic + c['poll_budget_ms']/1000
    incoming, nodes, lan, incidents, transitions = [], {}, {}, {}, []
    for node_id, spec in c['nodes'].items():
        payload, failure = None, None
        try:
            remaining = deadline-time.monotonic()
            if remaining <= 0:
                raise ObserverError('POLL_BUDGET_EXCEEDED')
            payload = ssh_json(spec, min(3, remaining))
            if type(payload) is dict and payload.get('schema_version') == 1 and payload.get('ok') is False:
                failure = 'COLLECTION_UNAVAILABLE'
        except ObserverError as error:
            failure = error.code
        node = observe_node(state['nodes'].get(node_id), payload, node_id=node_id,
                            wall=int(time.time()), monotonic=time.monotonic(), collector_boot=boot,
                            max_age=c['max_age'], failure=failure)
        incoming.extend(node.pop('events'))
        nodes[node_id] = node
        category = (node['reason'] if node['reason'] in ('NODE_UNREACHABLE', 'RESULT_STALE') else 'COLLECTION_FAILED') if not node['fresh'] else None
        if node['reason'] == 'MONITOR_DISABLED':
            category = 'MONITOR_DISABLED'
        incident_key = 'node:' + node_id
        incidents[incident_key], events = _pending_visibility(state['visibility'].get(incident_key), category,
                     key=node_id, node_id=node_id, wall=wall, minimum_interval=c['interval_seconds'])
        incoming.extend(events)
        transitions.extend((incident_key, event) for event in events)
    for key, spec in c['lan'].items():
        try:
            remaining = deadline-time.monotonic()
            if remaining <= 0:
                raise ObserverError('POLL_BUDGET_EXCEEDED')
            raw = ssh_json(spec['ssh'], min(spec['expected']['timeout_ms']/1000+1, remaining), spec['expected']['target_id'])
            lan[key] = validate_result(raw, spec['expected'], now=int(time.time()), max_age=c['max_age'],
                                       previous=state['lan'].get(key))
        except ObserverError as error:
            lan[key] = validate_result(None, spec['expected'], now=int(time.time()), max_age=c['max_age'],
                                       previous=state['lan'].get(key))
            lan[key]['reason'] = error.code
        if (int(time.time()) < state['last_poll_at'] or state['collector_boot'] == boot
                and time.monotonic() < state['last_poll_monotonic']):
            lan[key] = dict(status='UNKNOWN', fresh=False, reason='CLOCK_REVERSED',
                            last_source=state['lan'].get(key, {}).get('last_source'))
        if lan[key]['fresh']:
            previous_source = state['lan'].get(key, {}).get('last_source')
            candidate = anchor_sample(previous_source, lan[key], wall=int(time.time()), monotonic=time.monotonic(),
                                      collector_boot=boot, max_age=c['max_age'])
            if candidate is None:
                lan[key].update(status='UNKNOWN', fresh=False, reason='PROBE_STALE', last_source=previous_source)
            else:
                lan[key]['last_source'] = candidate
        category = None if lan[key]['status'] == 'PASS' else 'LAN_PATH_FAILED' if lan[key]['status'] == 'FAIL' else 'LAN_PROBE_UNAVAILABLE'
        incident_key = 'lan:' + key
        incidents[incident_key], events = _pending_visibility(state['visibility'].get(incident_key), category,
                 key=key, node_id=spec['node_id'], wall=wall, minimum_interval=c['interval_seconds'])
        incoming.extend(events)
        transitions.extend((incident_key, event) for event in events)
    state.update(nodes=nodes, lan=lan, visibility=incidents, last_poll_at=wall,
                 last_poll_monotonic=monotonic, collector_boot=boot, delivery_reason=None)
    _enqueue(state, incoming, wall)
    for key, event in transitions:
        event_key = hashlib.sha256(json.dumps([event['node_id'], event['id']], separators=(',', ':')).encode()).hexdigest()
        if event_key in state['seen']:
            incidents[key].pop('pending_event', None)
    atomic_json(state_path, state)
    _send_one(c, state, state_path, deadline)
    atomic_json(state_path, state)
    return view(c, state, wall=int(time.time()), monotonic=time.monotonic(), boot=boot)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['once', 'read', 'deliver'])
    parser.add_argument('--config')
    parser.add_argument('--state', required=True)
    parser.add_argument('--sink')
    parser.add_argument('--event')
    args = parser.parse_args()
    try:
        if sys.platform != 'linux':
            raise ObserverError('CAPABILITY_MISSING')
        forced = os.environ.get('SSH_ORIGINAL_COMMAND')
        if forced is not None and (forced != 'netbird-health central-v1' or args.command != 'read'):
            raise ObserverError('COMMAND_DENIED')
        if args.command == 'deliver':
            if (args.config is not None or args.sink is None or args.event is None or len(args.event) != 64 or
                    any(ch not in '0123456789abcdef' for ch in args.event)):
                raise ObserverError('COMMAND_DENIED')
            result = deliver(args.state, args.event, args.sink)
        else:
            if args.config is None or args.sink is not None or args.event is not None:
                raise ObserverError('COMMAND_DENIED')
            c = validate_config(read_private_json(args.config))
            if args.command == 'read':
                result = view(c, load_state(args.state), wall=int(time.time()), monotonic=time.monotonic(), boot=_boot())
            else:
                import fcntl
                directory = private_directory(Path(args.state).parent, create=True)
                fd = os.open(directory / 'cycle.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
                try:
                    info = os.fstat(fd)
                    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
                        raise ObserverError('PRIVATE_FILE_REQUIRED')
                    try:
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        raise ObserverError('COLLECTOR_BUSY') from None
                    result = cycle(c, load_state(args.state), Path(args.state))
                finally:
                    os.close(fd)
        print(json.dumps(result, allow_nan=False))
        return 0
    except (ObserverError, OSError, ValueError, TypeError, KeyError) as error:
        print(json.dumps(dict(schema_version=1, ok=False, reason=error.code if isinstance(error, ObserverError) else 'COLLECTOR_UNAVAILABLE')))
        return 2


if __name__ == '__main__':
    sys.exit(main())
