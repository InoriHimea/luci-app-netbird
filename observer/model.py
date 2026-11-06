# SPDX-License-Identifier: Apache-2.0
"""Pure P1 observation model. Transport success is not business/LAN success."""
import copy
import hashlib
import json
import re

VANTAGES = ('local_structure', 'forward_lookup', 'router_probe', 'lan_probe', 'external_observer')
HEALTH = {'healthy', 'unhealthy', 'degraded', 'unknown', 'disabled', 'maintenance', 'checking'}


def _integer(value, low=0, high=2**53 - 1):
    return type(value) is int and low <= value <= high


def _text(value, maximum=128):
    return isinstance(value, str) and 0 < len(value) <= maximum and not any(ord(c) < 32 for c in value)


def _valid_frame(value):
    return (type(value) is dict and type(value.get('schema_version')) is int and value['schema_version'] == 1 and value.get('ok') is True
            and all(_text(value.get(k)) for k in ('node_id', 'boot_id', 'run_id'))
            and all(_integer(value.get(k)) for k in ('sampled_at', 'served_at', 'config_revision', 'baseline_revision'))
            and _integer(value.get('max_age'), 1, 86400)
            and type(value.get('fresh')) is bool and type(value.get('monitor_enabled')) is bool
            and isinstance(value.get('overall'), str) and value['overall'] in HEALTH and type(value.get('coverage')) is dict
            and set(value['coverage']) == set(VANTAGES)
            and all(isinstance(v, str) and v in HEALTH for v in value['coverage'].values())
            and type(value.get('events')) is list and len(value['events']) <= 32)


def sample_current(source, *, monotonic, collector_boot):
    return (type(source) is dict and source.get('collector_boot') == collector_boot
            and type(source.get('anchor_monotonic')) in (int, float)
            and type(source.get('expires_monotonic')) in (int, float)
            and source['anchor_monotonic'] <= monotonic <= source['expires_monotonic'])


def anchor_sample(source, payload, *, wall, monotonic, collector_boot, max_age):
    identity = {k: payload[k] for k in ('boot_id', 'run_id', 'sampled_at')}
    retired = list(source.get('retired_boots', [])) if source else []
    if identity['boot_id'] in retired:
        return None
    if source and source['boot_id'] != identity['boot_id']:
        if len(retired) >= 32:
            return None  # Never evict replay protection to make a new boot look safe.
        retired.append(source['boot_id'])
    deadline = monotonic + max_age - (wall - payload['sampled_at'])
    if source and all(source.get(k) == identity[k] for k in ('boot_id', 'sampled_at')):
        if not sample_current(source, monotonic=monotonic, collector_boot=collector_boot):
            return None
        deadline = min(deadline, source['expires_monotonic'])
        anchor = source['anchor_monotonic']
    else:
        anchor = monotonic
    if deadline < monotonic:
        return None
    return dict(identity, collector_boot=collector_boot, anchor_monotonic=anchor,
                expires_monotonic=deadline, retired_boots=retired)


def observe_node(previous, payload, *, node_id, wall, monotonic, collector_boot, max_age,
                 failure=None):
    """Every failed/stale poll replaces effective green; retain identity for replay checks."""
    previous = previous or {}
    source = previous.get('last_source')
    reason = failure
    if not reason and type(payload) is dict and payload.get('node_id') != node_id:
        reason = 'NODE_ID_MISMATCH'
    if not reason and not _valid_frame(payload):
        reason = 'SCHEMA_INVALID'
    if not reason and previous and (wall < previous['observed_at'] or
            previous['collector_boot'] == collector_boot and monotonic < previous['observed_monotonic']):
        reason = 'CLOCK_REVERSED'
    if not reason and (payload['sampled_at'] > wall or payload['served_at'] > wall + 5):
        reason = 'CLOCK_SKEW'
    if not reason and source and source['run_id'] == payload['run_id']:
        if source['boot_id'] != payload['boot_id']:
            reason = 'BOOT_RUN_REUSED'
        elif source['sampled_at'] != payload['sampled_at']:
            reason = 'RUN_ID_REUSED'
    if not reason and source and source['boot_id'] == payload['boot_id'] and payload['sampled_at'] < source['sampled_at']:
        reason = 'SAMPLE_REVERSED'
    if not reason and wall - payload['sampled_at'] > min(max_age, payload['max_age']):
        reason = 'RESULT_STALE'
    if not reason and not payload['fresh']:
        reason = 'NODE_RESULT_INVALID'
    disabled = not reason and not payload['monitor_enabled']
    if not reason and not disabled:
        candidate = anchor_sample(source, payload, wall=wall, monotonic=monotonic,
                                  collector_boot=collector_boot, max_age=min(max_age, payload['max_age']))
        if candidate is None:
            reason = 'RESULT_STALE'
        else:
            source = dict(candidate, **{k: payload[k] for k in ('config_revision', 'baseline_revision')})
    fresh = not reason and not disabled
    return dict(node_id=node_id, fresh=fresh, reason=reason or ('MONITOR_DISABLED' if disabled else None),
                overall=payload['overall'] if fresh else 'disabled' if disabled else 'unknown',
                coverage=copy.deepcopy(payload['coverage']) if fresh else dict.fromkeys(VANTAGES, 'unknown'),
                boot_id=payload.get('boot_id') if type(payload) is dict else None,
                run_id=payload.get('run_id') if type(payload) is dict else None,
                sampled_at=payload.get('sampled_at') if type(payload) is dict else None,
                observed_at=wall, observed_monotonic=monotonic, collector_boot=collector_boot,
                max_age=min(max_age, payload['max_age']) if fresh else max_age,
                last_source=source, events=copy.deepcopy(payload['events']) if fresh else [],
                observer=dict(state='normal' if fresh else 'unknown' if disabled else 'abnormal',
                              failure=None if fresh or disabled else reason))


def _health(states):
    if 'unhealthy' in states:
        return 'unhealthy'
    if 'degraded' in states:
        return 'degraded'
    return 'healthy' if states and all(s == 'healthy' for s in states) else 'unknown'


def aggregate_site(nodes, expected_lan, lan_results):
    """The approved LAN denominator is authoritative, never the returned result keys."""
    coverage = {v: _health([n['coverage'][v] for n in nodes]) for v in VANTAGES}
    lan = {}
    for target in expected_lan:
        item = lan_results.get(target)
        if (type(item) is not dict or item.get('fresh') is not True or
                not isinstance(item.get('status'), str) or item['status'] not in {'PASS', 'FAIL'}):
            lan[target] = dict(status='UNKNOWN', fresh=False,
                               reason=item.get('reason', 'PROBE_UNAVAILABLE') if type(item) is dict else 'PROBE_UNAVAILABLE')
        else:
            lan[target] = copy.deepcopy(item)
    coverage['lan_probe'] = _health([{'PASS': 'healthy', 'FAIL': 'unhealthy', 'UNKNOWN': 'unknown'}[v['status']]
                                    for v in lan.values()])
    coverage['external_observer'] = 'healthy' if nodes and all(n['fresh'] for n in nodes) else 'unknown'
    overall = _health(list(coverage.values()) +
                      [n['overall'] for n in nodes if n['overall'] in {'unhealthy', 'degraded'}])
    return dict(overall=overall, coverage=coverage, nodes=nodes, lan=lan,
                lan_expected_count=len(expected_lan),
                lan_unknown_count=sum(v['status'] == 'UNKNOWN' for v in lan.values()),
                lan_reason=None if expected_lan else 'NOT_CONFIGURED')


def _public_event(event):
    if (type(event) is not dict or not all(_text(event.get(k), 192) for k in ('id', 'episode_id', 'node_id'))
            or not isinstance(event.get('kind'), str) or event['kind'] not in {'failure', 'recovery', 'reminder'}
            or not _integer(event.get('created_at')) or event.get('owner') != 'central'
            or type(event.get('categories')) is not list or len(event['categories']) > 16
            or not all(isinstance(c, str) and re.fullmatch(r'[A-Z_]{1,64}', c) for c in event['categories'])
            or type(event.get('details')) is not list or len(event['details']) > 32):
        return None
    result = {k: event[k] for k in ('id', 'episode_id', 'node_id', 'kind', 'created_at', 'owner', 'categories')}
    details = []
    for detail in event['details']:
        if type(detail) is not dict or not all(_text(detail.get(k), 192) for k in ('category', 'id', 'code', 'severity')):
            return None
        details.append({k: detail[k] for k in ('category', 'id', 'code', 'severity')})
    result['details'] = details
    result['receipt_verified'] = False
    return result


def admit_events(state, incoming, *, now, capacity=1024, retention=86400):
    """Fail closed at capacity; evicting live IDs would enable duplicate delivery."""
    saved = {k: v for k, v in state.items() if type(v) is dict and
             _integer(v.get('created_at')) and now - v['created_at'] <= retention}
    accepted, reason = [], None
    for raw in incoming:
        event = _public_event(raw)
        if event is None or not 0 <= now - event['created_at'] <= retention:
            continue
        key = hashlib.sha256(json.dumps([event['node_id'], event['id']], separators=(',', ':')).encode()).hexdigest()
        if key in saved:
            continue
        if len(saved) >= capacity:
            reason = 'DEDUP_CAPACITY'
            continue
        saved[key] = dict(created_at=event['created_at'])
        accepted.append(event)
    return dict(state=saved, accepted=accepted, reason=reason)
