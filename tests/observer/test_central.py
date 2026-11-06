# SPDX-License-Identifier: Apache-2.0
import unittest
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch
from observer.central import visibility
from observer.central import empty_state, validate_config, view
from observer.model import observe_node
from test_model import frame
from test_lan_probe import binding


class VisibilityTests(unittest.TestCase):
    def vote(self, state, failure, wall):
        return visibility(state, failure, key='node-a', node_id='node-a', wall=wall, minimum_interval=10)

    def test_threshold_episode_recovery_and_second_failure(self):
        state = {}; events = []
        for wall in (10, 20, 30, 40):
            state, new = self.vote(state, 'NODE_UNREACHABLE', wall); events += new
        self.assertEqual([e['kind'] for e in events], ['failure'])
        first = events[0]
        self.assertEqual(first['node_id'], 'node-a')
        self.assertEqual(first['categories'], ['NODE_UNREACHABLE'])
        state, new = self.vote(state, None, 50)
        self.assertEqual(new, [])
        state, new = self.vote(state, None, 60)
        self.assertEqual([e['kind'] for e in new], ['recovery'])
        self.assertEqual(new[0]['episode_id'], first['episode_id'])
        self.assertIsNone(state['failure'])
        for wall in (70, 80, 90):
            state, new = self.vote(state, 'RESULT_STALE', wall)
        self.assertEqual(len(new), 1)
        self.assertNotEqual(new[0]['id'], first['id'])
        self.assertNotEqual(new[0]['episode_id'], first['episode_id'])

    def test_fast_polls_and_wall_rollback_do_not_advance_threshold(self):
        state = {}
        for wall in (10, 11, 12, 5, 19):
            state, events = self.vote(state, 'COLLECTION_FAILED', wall)
            self.assertEqual(events, [])
        self.assertEqual(state['bad'], 1)
        state, _ = self.vote(state, 'COLLECTION_FAILED', 20)
        state, events = self.vote(state, 'COLLECTION_FAILED', 30)
        self.assertEqual(len(events), 1)

    def test_disabling_monitoring_breaks_recovery_streak_without_closing_incident(self):
        paused = {}
        for wall in (10, 20, 30):
            paused, events = self.vote(paused, 'MONITOR_DISABLED', wall)
            self.assertEqual(events, [])
            self.assertFalse(paused.get('active', False))
        state = {}
        for wall in (10, 20, 30):
            state, _ = self.vote(state, 'NODE_UNREACHABLE', wall)
        episode = state['episode_id']
        state, _ = self.vote(state, None, 40)
        for wall in (50, 60, 70):
            state, events = self.vote(state, 'MONITOR_DISABLED', wall)
            self.assertEqual(events, [])
            self.assertTrue(state['active'])
        state, events = self.vote(state, None, 80)
        self.assertEqual(events, [])
        state, events = self.vote(state, None, 90)
        self.assertEqual([event['kind'] for event in events], ['recovery'])
        self.assertEqual(events[0]['episode_id'], episode)


class CachedReadTests(unittest.TestCase):
    def config(self):
        return validate_config(dict(schema_version=1, enabled=True, collector_id='central-a',
            interval_seconds=10, poll_budget_ms=500, max_age=90,
            nodes={'node-a': dict(host='127.0.0.1', port=22, user='root', identity_file='/tmp/key', known_hosts_file='/tmp/hosts')},
            lan={}, notifications=dict(owner='none', sink_file=None)))

    def test_cached_read_expires_by_monotonic_time_despite_wall_slew(self):
        c = self.config(); state = empty_state()
        state['nodes']['node-a'] = observe_node(None, frame(), node_id='node-a', wall=1001,
            monotonic=10, collector_boot='boot', max_age=90)
        result = view(c, state, wall=1002, monotonic=71, boot='boot')
        self.assertFalse(result['site']['nodes'][0]['fresh'])

    def test_read_respects_the_nodes_shorter_source_ttl(self):
        c = self.config(); state = empty_state()
        state['nodes']['node-a'] = observe_node(None, frame(max_age=5), node_id='node-a', wall=1001,
            monotonic=10, collector_boot='central-boot-a', max_age=90)
        result = view(c, state, wall=1006, monotonic=15, boot='central-boot-a')
        self.assertFalse(result['site']['nodes'][0]['fresh'])
        self.assertEqual(result['site']['coverage']['router_probe'], 'unknown')

    def test_read_does_not_reuse_lan_pass_after_approved_target_changes(self):
        c = self.config(); expected = binding(); expected.pop('boot_id')
        c['lan']['west-rdp'] = dict(expected=dict(expected, address='198.51.100.3'), node_id='node-a', ssh=c['nodes']['node-a'])
        state = empty_state(); state.update(collector_boot='boot', last_poll_at=100, last_poll_monotonic=10)
        state['lan']['west-rdp'] = dict(expected, status='PASS', fresh=True, sampled_at=100, boot_id='node-boot', run_id='r1')
        result = view(c, state, wall=101, monotonic=11, boot='boot')
        self.assertEqual(result['site']['lan']['west-rdp']['status'], 'UNKNOWN')

    def test_negative_probe_cause_remains_visible_only_while_poll_is_current(self):
        c = self.config(); expected = binding(); expected.pop('boot_id')
        c['lan']['west-rdp'] = dict(expected=expected, node_id='node-a', ssh=c['nodes']['node-a'])
        state = empty_state(); state.update(collector_boot='boot', last_poll_at=100, last_poll_monotonic=10)
        state['lan']['west-rdp'] = dict(status='UNKNOWN', fresh=False, reason='PATH_NOT_ATTESTED')
        current = view(c, state, wall=101, monotonic=11, boot='boot')['site']['lan']['west-rdp']
        self.assertEqual(current['reason'], 'PATH_NOT_ATTESTED')
        self.assertEqual(current['status'], 'UNKNOWN')
        expired = view(c, state, wall=191, monotonic=101, boot='boot')['site']['lan']['west-rdp']
        self.assertEqual(expired['reason'], 'PROBE_STALE')




class QueueTests(unittest.TestCase):
    def poll(self, c, state, path, wall, payload=None, monotonic=None, boot='boot'):
        from observer.central import cycle
        from observer.transport import ObserverError
        with patch('observer.central.time.time', return_value=wall), \
             patch('observer.central.time.monotonic', return_value=wall-1000 if monotonic is None else monotonic), \
             patch('observer.central._boot', return_value=boot), \
             patch('observer.central.ssh_json', return_value=payload,
                   side_effect=ObserverError('NODE_UNREACHABLE') if payload is None else None):
            cycle(c, state, path)

    @unittest.skipUnless(sys.platform == 'linux', 'Linux private-state contract')
    def test_lan_same_sample_cannot_outlive_monotonic_ttl_or_collector_boot(self):
        from observer.central import load_state
        for mode in ('expiry', 'reboot', 'retired-boot', 'wall-reversed', 'monotonic-reversed'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                c = CachedReadTests().config(); expected = binding(); expected.pop('boot_id')
                c['lan']['west-rdp'] = dict(expected=expected, node_id='node-a', ssh=c['nodes']['node-a'])
                raw = dict(expected, schema_version=1, boot_id='probe-boot', run_id='probe-run', sampled_at=1000,
                    status='PASS', path_verified=True,
                    route=dict(dev=expected['interface'], gateway=expected['gateway'], prefsrc=expected['source']))
                state = empty_state(); path = str(Path(directory)/'state.json')
                self.poll(c, state, path, 1001, raw, monotonic=10)
                self.assertEqual(state['lan']['west-rdp']['status'], 'PASS')
                state = load_state(path)
                if mode == 'reboot':
                    self.poll(c, state, path, 1002, raw, monotonic=1, boot='new-boot')
                elif mode == 'retired-boot':
                    self.poll(c, state, path, 1002, dict(raw, boot_id='new-probe-boot', run_id='new-run', sampled_at=1001), monotonic=20)
                    self.poll(c, state, path, 1003, raw, monotonic=101)
                elif mode in ('wall-reversed', 'monotonic-reversed'):
                    self.poll(c, state, path, 1000 if mode == 'wall-reversed' else 1002,
                              dict(raw, run_id='new-run'), monotonic=20 if mode == 'wall-reversed' else 9)
                else:
                    self.poll(c, state, path, 1002, raw, monotonic=50)
                    cached = view(c, state, wall=1003, monotonic=101, boot='boot')
                    self.assertEqual(cached['site']['lan']['west-rdp']['status'], 'UNKNOWN')
                    self.poll(c, state, path, 1003, raw, monotonic=101)
                self.assertEqual(state['lan']['west-rdp']['status'], 'UNKNOWN')

    @unittest.skipUnless(sys.platform == 'linux', 'Linux private-state contract')
    def test_node_identifier_cannot_collide_with_lan_visibility_namespace(self):
        with tempfile.TemporaryDirectory() as directory:
            c = CachedReadTests().config(); spec = c['nodes'].pop('node-a'); c['nodes']['lan:west-rdp'] = spec
            expected = binding(); expected.pop('boot_id')
            c['lan']['west-rdp'] = dict(expected=expected, node_id='lan:west-rdp', ssh=spec)
            raw = dict(expected, schema_version=1, boot_id='probe-boot', run_id='probe-run', sampled_at=1000,
                status='PASS', path_verified=True,
                route=dict(dev=expected['interface'], gateway=expected['gateway'], prefsrc=expected['source']))
            state = empty_state(); path = str(Path(directory)/'state.json')
            for wall in (1001, 1011, 1021):
                self.poll(c, state, path, wall, raw)
            events = [r['event'] for r in state['outbox'] if r['event']['categories'] == ['COLLECTION_FAILED']]
            self.assertEqual([event['kind'] for event in events], ['failure'])
            self.assertEqual(events[0]['node_id'], 'lan:west-rdp')


    @unittest.skipUnless(sys.platform == 'linux', 'Linux private-state contract')
    def test_queue_backpressure_retries_failure_and_recovery_transitions(self):
        from observer.central import _enqueue, load_state
        for recovery, reversed_health in ((False, False), (True, False), (False, True), (True, True)):
            with self.subTest(recovery=recovery, reversed_health=reversed_health), tempfile.TemporaryDirectory() as directory:
                c = CachedReadTests().config(); state = empty_state()
                _enqueue(state, [dict(id='e'+str(i), episode_id='ep'+str(i), node_id='node-a', kind='failure',
                    created_at=1000, owner='central', categories=['ROUTER_PROBE'], details=[]) for i in range(32)], 1000)
                state['visibility']['node:node-a'] = dict(last_vote=1010, bad=2, good=1 if recovery else 0,
                    active=recovery, episode_id='original-episode', failure='NODE_UNREACHABLE')
                path = str(Path(directory)/'state.json')
                self.poll(c, state, path, 1020, frame() if recovery else None)
                state = load_state(path)
                state['outbox'][0]['status'] = 'accepted'
                subsequent = frame() if recovery != reversed_health else None
                self.poll(c, state, path, 1030, subsequent)
                state = load_state(path)
                transitions = [r['event'] for r in state['outbox'] if r['event']['categories'] == ['NODE_UNREACHABLE']]
                self.assertEqual([e['kind'] for e in transitions], ['recovery' if recovery else 'failure'])
                if recovery:
                    self.assertEqual(transitions[0]['episode_id'], 'original-episode')
                self.poll(c, state, path, 1040, subsequent)
                self.assertEqual(sum(r['event']['categories'] == ['NODE_UNREACHABLE'] for r in state['outbox']), 1)

    def test_duplicate_at_capacity_is_not_overflow_and_new_event_is_not_lost(self):
        from observer.central import _enqueue
        state = empty_state()
        events = [dict(id='e'+str(i), episode_id='episode'+str(i), node_id='node-a', kind='failure',
                       created_at=100, owner='central', categories=['ROUTER_PROBE'], details=[]) for i in range(33)]
        _enqueue(state, events[:32], 100)
        _enqueue(state, [events[0]], 100)
        self.assertIsNone(state['delivery_reason'])
        self.assertEqual(len(state['outbox']), 32)
        _enqueue(state, [events[32]], 100)
        self.assertEqual(state['delivery_reason'], 'QUEUE_CAPACITY')
        self.assertEqual(len(state['seen']), 32)
        state['outbox'][0]['status'] = 'accepted'
        _enqueue(state, [events[32]], 100)
        self.assertEqual(len(state['seen']), 33)
        self.assertEqual(state['outbox'][-1]['event']['id'], 'e32')

    def test_exhausted_rejections_do_not_permanently_block_new_incidents(self):
        from observer.central import _enqueue
        state = empty_state()
        events = [dict(id='e'+str(i), episode_id='episode'+str(i), node_id='node-a', kind='failure',
                       created_at=100, owner='central', categories=['ROUTER_PROBE'], details=[]) for i in range(33)]
        _enqueue(state, events[:32], 100)
        for record in state['outbox']:
            record.update(status='failed', attempts=3)
        delivery = view(CachedReadTests().config(), state, wall=100, monotonic=10, boot='boot')['delivery']
        self.assertEqual(delivery['queued'], 0)
        self.assertEqual(delivery['failed'], 32)
        _enqueue(state, [events[32]], 101)
        self.assertEqual(state['outbox'][-1]['event']['id'], 'e32')
        self.assertEqual(len(state['seen']), 33)


if __name__ == '__main__':
    unittest.main()
