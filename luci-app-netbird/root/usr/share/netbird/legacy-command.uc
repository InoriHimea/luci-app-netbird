// SPDX-License-Identifier: Apache-2.0
// Private root shell adapter used by lib/shell.uc, not an RPC endpoint.
import { run_legacy_command } from './health/runner.uc';
if (length(ARGV) != 3 || !match(ARGV[0], /^[1-9][0-9]{0,2}$/) || int(ARGV[0]) > 600 ||
    ARGV[2] != '-' && !match(ARGV[2], /^[0-9a-f]{32}$/)) exit(125);
let actions = null, owner = ARGV[2] == '-' ? null : ARGV[2];
if (owner) {
    actions = loadfile('/usr/share/rpcd/ucode/lib/action_lock.uc')().create();
    if (!actions.prepare_command(owner)) exit(125);
}
let result = run_legacy_command(ARGV[1], int(ARGV[0]) * 1000, owner);
print(result.stdout);
if (!result.cleanup_confirmed || owner && !actions.finish_command(owner)) exit(125);
if (result.reason == 'TIMEOUT') exit(124);
exit(result.ok ? 0 : type(result.exit_code) == 'int' && result.exit_code > 0 && result.exit_code < 256 ? result.exit_code : 125);
