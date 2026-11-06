// SPDX-License-Identifier: Apache-2.0
import { run_recovery_worker } from './runner.uc';
if (length(ARGV) != 2 || !match(ARGV[0], /^[0-9a-f]{32}$/) || !match(ARGV[1], /^[0-9]{1,16}$/)) exit(2);
// The independently armed runner guard kills a stopped/orphaned worker too.
// Nested fixed commands inherit the same absolute deadline, never a new window.
let result = run_recovery_worker(ARGV[0], int(ARGV[1]));
exit(result.ok ? 0 : 1);
