// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, lsdir, unlink, rmdir, open } from 'fs';
import { create_jobs } from '../../luci-app-netbird/root/usr/share/netbird/health/jobs.uc';
let root = mkdtemp('/tmp/nbh-jobs-test.XXXXXX'), now = 1000;
let jobs = create_jobs(root, () => now), count = 0;
function check(ok, label) { if (!ok) die(label + '\n'); count++; }
let queued = jobs.enqueue(7);
check(queued.ok && match(queued.job.id, /^[0-9a-f]{32}$/) && queued.job.state == 'queued', 'backend issues an opaque queued job');
let writer = open(root + '/jobs.lock', 'a', 0600);
check(writer.lock('xn'), 'fixture holds concurrent metadata writer lease');
let contended = jobs.enqueue(7);
check(contended.ok && contended.coalesced && contended.job.id == queued.job.id,
    'published in-flight job remains coalescible while metadata writer is busy');
writer.close();
let again = jobs.enqueue(7);
check(again.ok && again.job.id == queued.job.id && again.coalesced, 'concurrent manual requests share the queued job');
let running = jobs.begin(7);
check(running.ok && running.job.id == queued.job.id && running.job.state == 'running', 'scheduled work adopts a pending manual job');
check(jobs.enqueue(7).job.id == running.job.id, 'active periodic/manual work is single flight');
check(jobs.finish(running.job.id, { run_id: 'fixture-run', config_revision: 7 }, null).ok, 'completed run publication');
let done = jobs.get(running.job.id);
check(done.ok && done.job.state == 'done' && done.run.run_id == 'fixture-run', 'result belongs to issued completed job');
check(jobs.enqueue(7).job.id == done.job.id, 'rapid repeat uses the recent completed result');
now += 2001;
let next = jobs.enqueue(7);
check(next.ok && next.job.id != done.job.id, 'later request starts a new job');
check(!jobs.finish(done.job.id, { run_id: 'late-write' }, null).ok && jobs.get(done.job.id).run.run_id == 'fixture-run',
    'late completion cannot rewrite a terminal result');
check(jobs.get('../latest.json').reason == 'JOB_INVALID', 'job ID is not a filesystem path');
check(jobs.get('00000000000000000000000000000000').reason == 'JOB_UNKNOWN', 'unknown syntactically valid ID is explicit');
now += 600001;
check(jobs.get(next.job.id).reason == 'JOB_EXPIRED', 'expired issued job is explicit');
let fresh = jobs.begin(8);
check(fresh.ok && fresh.job.id != next.job.id && fresh.job.config_revision == 8, 'expired work cannot block a newer generation');
jobs.finish(fresh.job.id, { run_id: 'revision-eight', config_revision: 8 }, null);
now += 2001;
let obsolete = jobs.enqueue(8), replacement = jobs.begin(9);
check(replacement.ok && replacement.job.config_revision == 9 && replacement.job.id != obsolete.job.id &&
    jobs.get(obsolete.job.id).job.error == 'CONFIG_CHANGED', 'queued obsolete revision cannot block changed configuration');
jobs.finish(replacement.job.id, { run_id: 'revision-nine', config_revision: 9 }, null);
let orphan = jobs.begin(9);
now += 29999;
check(jobs.enqueue(10).reason == 'CONFIG_CHANGED', 'new revision must not displace a potentially live bounded worker');
now += 2;
check(jobs.get(orphan.job.id).job.state == 'failed' && jobs.get(orphan.job.id).job.error == 'EXECUTION_LEASE_EXPIRED',
    'orphaned worker becomes visibly terminal at the execution lease rather than retention expiry');
let recovered = jobs.enqueue(10);
check(recovered.ok && recovered.job.id != orphan.job.id && recovered.job.config_revision == 10 &&
    jobs.get(orphan.job.id).job.error == 'EXECUTION_LEASE_EXPIRED', 'expired execution lease admits new approved generation');
check(!jobs.finish(orphan.job.id, { run_id: 'late-orphan', config_revision: 9 }, null).ok,
    'late orphan completion cannot overwrite replacement generation');
let adopted = jobs.begin(10);
now += 30001;
check(jobs.enqueue(10).job.id != adopted.job.id, 'same-generation orphan is recovered rather than forever coalesced');
for (let name in lsdir(root)) unlink(root + '/' + name);
rmdir(root);
print('jobs: ', count, ' assertions passed\n');