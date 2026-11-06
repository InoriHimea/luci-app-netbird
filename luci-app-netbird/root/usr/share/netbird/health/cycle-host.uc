// SPDX-License-Identifier: Apache-2.0
import { run_command } from './runner.uc';
import { atomic_json } from './storage.uc';
import { unlink } from 'fs';
let budget = int(ARGV[0]);
if (budget < 1 || budget > 20000) exit(2);
let result = run_command(['/usr/bin/ucode', '/usr/share/netbird/health/cycle.uc'], budget);
if (!result.ok) {
    atomic_json('/tmp/netbird-health', 'cycle-error.json',
        { state: 'UNKNOWN', reason: result.reason, sampled_at: time() });
    exit(1);
}
unlink('/tmp/netbird-health/cycle-error.json');
