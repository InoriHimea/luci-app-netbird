// SPDX-License-Identifier: Apache-2.0
import { private_dir, atomic_json, read_json, keep_history } from '../../luci-app-netbird/root/usr/share/netbird/health/storage.uc';
import { mkdtemp, lstat, symlink, unlink, rmdir, lsdir, chmod, open } from 'fs';
let n = 0;
function check(ok, label) { if (!ok) die(`FAIL: ${label}\n`); printf('ok %d - %s\n', ++n, label); }
let root = mkdtemp('/tmp/nbh-storage-test.XXXXXX');
check(private_dir(root), 'root-owned private directory accepted');
check(atomic_json(root, 'current.json', { generation: 'a', value: 1 }), 'initial snapshot published');
check(atomic_json(root, 'current.json', { generation: 'b', value: 2 }) && read_json(root + '/current.json', 1024).generation == 'b', 'replacement presents complete new generation');
check(lstat(root + '/current.json').mode == 0600, 'snapshot never world-readable');
check(!atomic_json(root, '../escaped.json', {}) && !atomic_json(root, 'large.json', { data: '12345678' }, 8), 'path escape and oversized state rejected');
symlink('/tmp', root + '/link');
check(!private_dir(root + '/link'), 'symlink state directory rejected');
chmod(root, 0755);
check(!private_dir(root), 'insecure existing directory rejected rather than adopted');
chmod(root, 0700);
for (let i = 1; i <= 4; i++) atomic_json(root, sprintf('history-%010d.json', i), { i });
keep_history(root, 2);
check(!lstat(root + '/history-0000000001.json') && !lstat(root + '/history-0000000002.json') && read_json(root + '/history-0000000003.json', 100).i == 3 && read_json(root + '/history-0000000004.json', 100).i == 4, 'rotation preserves only newest approved count');
check(read_json(root + '/current.json', 4) == null, 'truncated JSON never returned as current evidence');
let interrupted = open(root + '/current.json.new', 'wx', 0600);
interrupted.write('{'); interrupted.close();
check(atomic_json(root, 'current.json', { generation: 'c' }) && read_json(root + '/current.json', 1024).generation == 'c', 'serialized writer recovers interrupted publication');
symlink(root + '/current.json', root + '/current.json.new');
check(!atomic_json(root, 'current.json', { generation: 'unsafe' }) && read_json(root + '/current.json', 1024).generation == 'c', 'temporary symlink cannot replace published evidence');
interrupted = open(root + '/.history.new', 'wx', 0600);
interrupted.write('{'); interrupted.close();
check(atomic_json(root, 'history-0000000005.json', { i: 5 }) && !lstat(root + '/.history.new'),
    'a new sequence reclaims the previous interrupted history stage');
let payload = sprintf('%0524200d', 0);
for (let i = 20; i <= 28; i++) atomic_json(root, sprintf('history-%010d.json', i), { payload });
keep_history(root, 1000);
let bytes = 0;
for (let name in lsdir(root)) if (match(name, /^history-[0-9]{10}\.json$/)) bytes += lstat(root + '/' + name).size;
check(bytes <= 4194304 && !lstat(root + '/history-0000000020.json') && lstat(root + '/history-0000000028.json'),
    'aggregate byte cap evicts oldest snapshots even below count limit');
for (let i = 40; i <= 44; i++) {
    keep_history(root, 1, 4194304 - 524288);
    atomic_json(root, sprintf('history-%010d.json', i), { i });
    // Simulate termination here, before any post-publication pruning.
}
let retained = [];
for (let name in lsdir(root)) if (match(name, /^history-[0-9]{10}\.json$/)) push(retained, name);
check(length(retained) == 2 && read_json(root + '/history-0000000044.json', 100).i == 44,
    'pre-publication reservation bounds repeated crashes after history rename');
for (let name in lsdir(root)) unlink(root + '/' + name);
rmdir(root);
printf('PASS: %d storage assertions\n', n);
