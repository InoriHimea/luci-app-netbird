# SPDX-License-Identifier: Apache-2.0
import copy
import unittest

from observer.model import observe_node, aggregate_site, admit_events


def frame(**updates):
    result = dict(schema_version=1, ok=True, node_id='node-a', boot_id='boot-a',
                  run_id='run-1', sampled_at=1000, served_at=1000,
                  config_revision=1, baseline_revision=1, fresh=True,
                  max_age=60, monitor_enabled=True, overall='unknown',
                  coverage=dict(local_structure='healthy', forward_lookup='healthy',
                                router_probe='healthy', lan_probe='unknown',
                                external_observer='unknown'), events=[])
    result.update(updates)
    return result


def poll(previous=None, payload=None, **updates):
    args = dict(node_id='node-a', wall=1001, monotonic=10,
                collector_boot='central-boot-a', max_age=60)
    args.update(updates)
    return observe_node(previous, frame() if payload is None else payload, **args)


class Freshness(unittest.TestCase):
    def test_new_run_at_same_source_timestamp_cannot_reset_sample_deadline(self):
        first = poll()
        newer_run = poll(first, frame(run_id='same-second-new-run'), wall=1002, monotonic=40)
        self.assertTrue(newer_run['fresh'])
        replay = poll(newer_run, wall=1003, monotonic=71)
        self.assertFalse(replay['fresh'])

    def test_retired_boot_capacity_fails_closed_without_forgetting_old_boots(self):
        state = poll()
        for i in range(1, 33):
            state = poll(state, frame(boot_id='boot-'+str(i), run_id='new-run-'+str(i),
                sampled_at=1000+i, served_at=1000+i), wall=1001+i, monotonic=10+i)
            self.assertTrue(state['fresh'])
        overflow = poll(state, frame(boot_id='overflow', run_id='overflow', sampled_at=1033, served_at=1033),
                        wall=1034, monotonic=43)
        self.assertFalse(overflow['fresh'])
        replay = poll(overflow, wall=1035, monotonic=44)
        self.assertFalse(replay['fresh'])

    def test_retired_source_boot_cannot_return_as_an_unseen_sample(self):
        first = poll()
        changed = poll(first, frame(boot_id='boot-b', run_id='run-b', sampled_at=1001, served_at=1001),
                       wall=1002, monotonic=20)
        self.assertTrue(changed['fresh'])
        replay = poll(changed, wall=1003, monotonic=71)
        self.assertFalse(replay['fresh'])

    def test_repeated_cache_and_failed_polls_cannot_extend_sample_lifetime(self):
        for interrupted in (False, True):
            with self.subTest(interrupted=interrupted):
                first = poll()
                repeated = poll(first, wall=1002, monotonic=40)
                self.assertTrue(repeated['fresh'])
                if interrupted:
                    repeated = poll(repeated, wall=1003, monotonic=45, failure='NODE_UNREACHABLE')
                expired = poll(repeated, wall=1004, monotonic=71)
                self.assertFalse(expired['fresh'])
                self.assertEqual(expired['reason'], 'RESULT_STALE')

    def test_collector_reboot_requires_a_new_source_sample(self):
        first = poll()
        same = poll(first, wall=1002, monotonic=1, collector_boot='central-boot-b')
        self.assertFalse(same['fresh'])
        new = poll(same, frame(run_id='new-run', sampled_at=1002, served_at=1002),
                   wall=1003, monotonic=2, collector_boot='central-boot-b')
        self.assertTrue(new['fresh'])

    def test_failed_poll_never_reuses_prior_router_green(self):
        first = poll()
        failed = observe_node(first, None, node_id='node-a', wall=1002,
                              monotonic=11, collector_boot='central-boot-a',
                              max_age=60, failure='NODE_UNREACHABLE')
        self.assertEqual(failed['reason'], 'NODE_UNREACHABLE')
        self.assertEqual(failed['coverage']['router_probe'], 'unknown')
        self.assertEqual(failed['overall'], 'unknown')

    def test_same_run_timestamp_relabel_is_rejected(self):
        first = poll()
        second = poll(first, frame(sampled_at=1030, served_at=1030), wall=1031, monotonic=40)
        self.assertEqual(second['reason'], 'RUN_ID_REUSED')
        self.assertFalse(second['fresh'])

    def test_node_boot_change_cannot_reuse_prior_run(self):
        first = poll()
        second = poll(first, frame(boot_id='boot-b'), wall=1002, monotonic=11)
        self.assertEqual(second['reason'], 'BOOT_RUN_REUSED')
        self.assertEqual(second['overall'], 'unknown')

    def test_stopped_run_expires_despite_successful_polls(self):
        first = poll()
        stale = poll(first, frame(served_at=1062), wall=1062, monotonic=71)
        self.assertEqual(stale['reason'], 'RESULT_STALE')
        self.assertFalse(stale['fresh'])

    def test_clock_reversal_and_future_sample_fail_closed(self):
        first = poll()
        backwards = poll(first, wall=1000, monotonic=11)
        self.assertEqual(backwards['reason'], 'CLOCK_REVERSED')
        future = poll(payload=frame(sampled_at=1010), wall=1001)
        self.assertEqual(future['reason'], 'CLOCK_SKEW')

    def test_new_run_recovers_current_observer_without_old_failure(self):
        bad = observe_node(None, None, node_id='node-a', wall=1001,
                           monotonic=10, collector_boot='central-boot-a',
                           max_age=60, failure='COLLECTION_FAILED')
        good = poll(bad, frame(run_id='run-2', sampled_at=1002, served_at=1002),
                    wall=1003, monotonic=12)
        self.assertTrue(good['fresh'])
        self.assertIsNone(good['reason'])
        self.assertEqual(good['observer']['state'], 'normal')
        self.assertIsNone(good['observer']['failure'])

    def test_wrong_node_and_incomplete_schema_are_not_green(self):
        self.assertEqual(poll(payload=frame(node_id='node-b'))['reason'], 'NODE_ID_MISMATCH')
        malformed = frame()
        del malformed['coverage']['lan_probe']
        self.assertEqual(poll(payload=malformed)['reason'], 'SCHEMA_INVALID')

    def test_node_declared_stale_and_disabled_remain_distinct(self):
        self.assertEqual(poll(payload=frame(fresh=False))['reason'], 'NODE_RESULT_INVALID')
        paused = poll(payload=frame(monitor_enabled=False))
        self.assertEqual(paused['overall'], 'disabled')
        self.assertFalse(paused['fresh'])


    def test_unhashable_remote_enums_fail_closed(self):
        self.assertEqual(poll(payload=frame(overall={}))['reason'], 'SCHEMA_INVALID')
        bad = frame()
        bad['coverage']['router_probe'] = []
        self.assertEqual(poll(payload=bad)['reason'], 'SCHEMA_INVALID')

    def test_new_run_cannot_relabel_older_same_boot_observation(self):
        first = poll(payload=frame(sampled_at=1001, served_at=1001))
        old = poll(first, frame(run_id='run-2'), wall=1002, monotonic=11)
        self.assertEqual(old['reason'], 'SAMPLE_REVERSED')

class Vantages(unittest.TestCase):
    def test_lan_failure_survives_router_success(self):
        report = aggregate_site([poll()], ['rdp-a', 'rdp-b'], {
            'rdp-a': {'status': 'PASS', 'fresh': True},
            'rdp-b': {'status': 'FAIL', 'fresh': True}})
        self.assertEqual(report['coverage']['router_probe'], 'healthy')
        self.assertEqual(report['coverage']['lan_probe'], 'unhealthy')
        self.assertEqual(report['overall'], 'unhealthy')
        self.assertEqual(report['lan_expected_count'], 2)

    def test_absent_or_stale_lan_keeps_full_denominator(self):
        report = aggregate_site([poll()], ['rdp-a', 'rdp-b'], {
            'rdp-a': {'status': 'PASS', 'fresh': False}})
        self.assertEqual(report['lan_expected_count'], 2)
        self.assertEqual(report['lan_unknown_count'], 2)
        self.assertEqual(report['coverage']['lan_probe'], 'unknown')
        self.assertEqual(report['overall'], 'unknown')
        self.assertEqual(set(report['lan']), {'rdp-a', 'rdp-b'})

    def test_no_lan_configuration_is_unknown_not_empty_success(self):
        report = aggregate_site([poll()], [], {})
        self.assertEqual(report['lan_reason'], 'NOT_CONFIGURED')
        self.assertEqual(report['overall'], 'unknown')


class Deduplication(unittest.TestCase):
    def event(self, **updates):
        result = dict(id='episode-a:failure:0', episode_id='episode-a',
                      node_id='node-a', kind='failure', created_at=1000,
                      owner='central', categories=['FORWARD_PATH'], details=[])
        result.update(updates)
        return result

    def test_duplicate_poll_and_restored_ledger_do_not_repeat_event(self):
        first = admit_events({}, [self.event()], now=1001, capacity=4, retention=60)
        self.assertEqual(len(first['accepted']), 1)
        restored = copy.deepcopy(first['state'])
        again = admit_events(restored, [self.event()], now=1002, capacity=4, retention=60)
        self.assertEqual(again['accepted'], [])
        other = admit_events(restored, [self.event(node_id='node-b')],
                             now=1002, capacity=4, retention=60)
        self.assertEqual(len(other['accepted']), 1)

    def test_recovery_and_new_episode_have_distinct_correlated_ids(self):
        first = admit_events({}, [self.event()], now=1001, capacity=4, retention=60)
        second = admit_events(first['state'], [self.event(id='episode-a:recovery:0', kind='recovery'),
            self.event(id='episode-b:failure:0', episode_id='episode-b')],
            now=1002, capacity=4, retention=60)
        self.assertEqual([e['episode_id'] for e in second['accepted']], ['episode-a', 'episode-b'])

    def test_capacity_does_not_evict_unexpired_events_and_allow_replay(self):
        first = admit_events({}, [self.event()], now=1001, capacity=1, retention=60)
        full = admit_events(first['state'], [self.event(id='episode-b:failure:0', episode_id='episode-b')],
                            now=1002, capacity=1, retention=60)
        self.assertEqual(full['accepted'], [])
        self.assertEqual(full['reason'], 'DEDUP_CAPACITY')
        old = admit_events(full['state'], [self.event()], now=1062, capacity=1, retention=60)
        self.assertEqual(old['accepted'], [])

    def test_local_owner_and_future_events_are_not_central_delivery(self):
        result = admit_events({}, [self.event(owner='local'), self.event(created_at=1100)],
                              now=1001, capacity=4, retention=60)
        self.assertEqual(result['accepted'], [])
    def test_wall_clock_reversal_does_not_forget_live_dedup_ids(self):
        first = admit_events({}, [self.event()], now=1001, capacity=4, retention=60)
        backwards = admit_events(first['state'], [], now=990, capacity=4, retention=60)
        again = admit_events(backwards['state'], [self.event()], now=1002, capacity=4, retention=60)
        self.assertEqual(again['accepted'], [])


if __name__ == '__main__':
    unittest.main()