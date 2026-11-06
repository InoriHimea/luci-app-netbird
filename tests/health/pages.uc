// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, lsdir, unlink, rmdir } from 'fs';
import { create_pages } from '../../luci-app-netbird/root/usr/share/netbird/health/pages.uc';
let count = 0, now = 1000;
function check(ok, label) { if (!ok) die(label + '\n'); count++; }
let root = mkdtemp('/tmp/nbh-pages-test.XXXXXX');
let pages = create_pages(root, () => now);
let rows = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];
let first = pages.first('checks', rows, { run_id: 'run-one', config_revision: 7 }, 2);
check(first.ok && first.total == 3 && length(first.items) == 2 && first.has_more && first.next_cursor,
    'first page reports actual frozen total');
rows[2].id = 'changed';
let second = pages.next('checks', first.next_cursor);
check(second.ok && second.items[0].id == 'c' && second.total == 3 && second.offset == 2 &&
    !second.has_more && second.next_cursor == null && second.metadata.run_id == 'run-one',
    'continuation retains original rows and generation despite later publications');
check(!pages.next('events', first.next_cursor).ok, 'cursor cannot cross dataset kinds');
check(pages.next('checks', '../latest.json').reason == 'CURSOR_INVALID', 'cursor is never a path');
check(pages.next('checks', '00000000000000000000000000000000').reason == 'CURSOR_UNKNOWN', 'unknown cursor explicit');
now += 600001;
check(pages.next('checks', first.next_cursor).reason == 'CURSOR_EXPIRED', 'expired snapshot explicit');
let empty = pages.first('events', [], { attribution: 'cause_undetermined' }, 2);
check(empty.ok && empty.total == 0 && !empty.has_more && length(empty.items) == 0, 'empty dataset has no phantom continuation');
check(!pages.first('checks', rows, {}, 0).ok && !pages.first('checks', rows, {}, 101).ok, 'page size bounds enforced');
for (let i = 0; i < 8; i++) check(pages.first('checks', rows, { generation: i }, 1).ok, 'bounded snapshot churn remains usable');
let snapshots = filter(lsdir(root), name => match(name, /^page-[0-9a-f]{32}\.json$/));
check(length(snapshots) <= 4, 'snapshot churn cannot grow retained storage without bound');
for (let name in lsdir(root)) unlink(root + '/' + name);
rmdir(root);
print('pages: ', count, ' assertions passed\n');
