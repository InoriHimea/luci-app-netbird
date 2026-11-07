// SPDX-License-Identifier: Apache-2.0
import { run_command, run_legacy_command, cleanup_commands } from '../../luci-app-netbird/root/usr/share/netbird/health/runner.uc';
import { access, readfile, unlink, mkdtemp, open, rmdir } from 'fs';
let count = 0;
function check(value, label) {
    if (!value) die(`FAIL: ${label}\n`);
    printf('ok %d - %s\n', ++count, label);
}
let r = run_command(['/bin/busybox', 'printf', '%s', '$(touch /tmp/nbh-injected);literal'], 1000);
check(r.ok && r.stdout == '$(touch /tmp/nbh-injected);literal' && !access('/tmp/nbh-injected'), 'arguments remain literal');
let quoted = "' ; touch /tmp/nbh-quote-injected; printf '";
r = run_command(['/bin/busybox', 'printf', '%s', quoted], 1000);
check(r.ok && r.stdout == quoted && !access('/tmp/nbh-quote-injected'), 'all embedded single quotes remain literal');
r = run_command(['/bin/sh', '-c',
    '. ./luci-app-netbird/root/usr/share/netbird/nb-run-bounded.sh; _NB_HAS_TIMEOUT=0; '
    + 'value="$(nb_run_bounded 2 /bin/sh -c \'sleep 1; printf bounded-substitution\')"; '
    + '[ "$value" = bounded-substitution ] && printf "%s" "$value"'], 3500);
check(r.ok && r.cleanup_confirmed && r.stdout == 'bounded-substitution',
    'native settings-style bounded command substitution reaps children without SIGCHLD deadlock');
r = run_command(['/no-such-health-tool'], 1000);
check(!r.ok && r.reason == 'TOOL_MISSING', 'missing tool is not empty success');
r = run_command(['/bin/sh', '-c', 'printf partial; exit 7'], 1000);
check(!r.ok && r.exit_code == 7, 'nonzero partial output fails closed');
r = run_command(['/bin/sh', '-c', 'while :; do printf 0123456789; done'], 1000);
check(!r.ok && r.reason == 'OUTPUT_LIMIT' && length(r.stdout) <= 65536, 'stdout flood bounded');
r = run_command(['/bin/sh', '-c', 'while :; do printf 0123456789 >&2; done'], 1000);
check(!r.ok && r.reason == 'OUTPUT_LIMIT', 'stderr flood bounded');
r = run_command(['/bin/sh', '-c', '(sleep 1; touch /tmp/nbh-orphan) & wait'], 100);
check(!r.ok && r.reason == 'TIMEOUT' && r.duration_ms < 1000, 'timeout independently enforced');
sleep(1200);
check(!access('/tmp/nbh-orphan'), 'timeout drains descendant process group');
r = run_command(['/bin/sh', '-c', '(sleep 1; touch /tmp/nbh-orphan) & exit 0'], 1000);
sleep(1200);
check(r.ok && !access('/tmp/nbh-orphan'), 'successful parent cannot leave descendants');
let legacy_dir = mkdtemp('/tmp/nbh-legacy.XXXXXX');
r = run_legacy_command('(sleep 1; touch ' + legacy_dir + '/late) & wait', 150);
check(!r.ok && r.reason == 'TIMEOUT' && r.cleanup_confirmed, 'legacy timeout drains its session');
sleep(1200);
check(!access(legacy_dir + '/late'), 'legacy timed-out parent cannot leave a late writer');
r = run_legacy_command('printf out; printf err >&2; exit 9', 1000);
check(!r.ok && r.exit_code == 9 && r.stdout == 'outerr', 'legacy diagnostics and original failure exit survive containment');
r = run_legacy_command('(sleep 1; touch ' + legacy_dir + '/late) & exit 0', 1000);
sleep(1200);
check(r.ok && r.cleanup_confirmed && !access(legacy_dir + '/late'), 'legacy successful parent cannot leave a late writer');
rmdir(legacy_dir);
check(!run_command(['/bin/true'], 0).ok, 'exhausted deadline never disables timeout');
r = run_command(['/bin/sh', '-c', 'printf note >&2'], 1000);
check(r.ok && r.output_bytes == 4 && !('stderr' in r), 'stderr counted without exposing contents');
r = run_command(['/bin/sh', '-c', 'printf "ip: invalid option -- j\\n" >&2; exit 1'], 1000);
check(!r.json_unsupported, 'unrecognized diagnostic does not authorize fallback');
r = run_command(['/bin/sh', '-c', 'printf \'Option "-j" is unknown, try "ip -help".\\n\' >&2; exit 255'], 1000);
check(!r.ok && r.json_unsupported, 'known ip JSON capability diagnostic preserved');
let abandoned = mkdtemp('/tmp/netbird-health-cmd.XXXXXX');
let file = open(abandoned + '/out', 'wx', 0600); file.write('partial'); file.close();
check(cleanup_commands() && !access(abandoned), 'abandoned private files are reclaimed after owner death');
let lease = open('/tmp/netbird-health/commands.lock', 'a', 0600);
lease.lock('s');
let active = mkdtemp('/tmp/netbird-health-cmd.XXXXXX');
check(!cleanup_commands() && access(active), 'janitor cannot race a live owner or armed guard');
lease.close();
check(cleanup_commands() && !access(active), 'released lease permits interrupted allocation cleanup');
let foreign = mkdtemp('/tmp/netbird-health-cmd.XXXXXX');
file = open(foreign + '/unrecognized', 'wx', 0600); file.close();
cleanup_commands();
check(access(foreign + '/unrecognized'), 'janitor refuses unexpected directory contents');
unlink(foreign + '/unrecognized'); rmdir(foreign);
printf('PASS: %d runner assertions\n', count);
