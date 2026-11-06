// SPDX-License-Identifier: Apache-2.0
import { run_command } from '../../luci-app-netbird/root/usr/share/netbird/health/runner.uc';
import { access, readfile, unlink } from 'fs';
let count = 0;
function check(value, label) {
    if (!value) die(`FAIL: ${label}\n`);
    printf('ok %d - %s\n', ++count, label);
}
let r = run_command(['/bin/busybox', 'printf', '%s', '$(touch /tmp/nbh-injected);literal'], 1000);
check(r.ok && r.stdout == '$(touch /tmp/nbh-injected);literal' && !access('/tmp/nbh-injected'), 'arguments remain literal');
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
check(!run_command(['/bin/true'], 0).ok, 'exhausted deadline never disables timeout');
r = run_command(['/bin/sh', '-c', 'printf note >&2'], 1000);
check(r.ok && r.output_bytes == 4 && !('stderr' in r), 'stderr counted without exposing contents');
r = run_command(['/bin/sh', '-c', 'printf "ip: invalid option -- j\\n" >&2; exit 1'], 1000);
check(!r.json_unsupported, 'unrecognized diagnostic does not authorize fallback');
r = run_command(['/bin/sh', '-c', 'printf \'Option "-j" is unknown, try "ip -help".\\n\' >&2; exit 255'], 1000);
check(!r.ok && r.json_unsupported, 'known ip JSON capability diagnostic preserved');
printf('PASS: %d runner assertions\n', count);
