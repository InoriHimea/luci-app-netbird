// SPDX-License-Identifier: Apache-2.0
// Invoke with NB_AGENT_WORKER=1 ucode <this-file> <command>.
import { readfile } from 'fs';
if (getenv('NB_AGENT_WORKER') != '1') {
    warn('Run with NB_AGENT_WORKER=1.\n');
    exit(2);
}
let command = ARGV[0] || 'status';
if (index(['run', 'scheduled', 'recover', 'recover-retry', 'boot', 'deadline'], command) >= 0) {
    let m = match(readfile('/proc/self/stat') || '', /^([0-9]+) \(.*\) (.+)$/);
    let fields = m ? split(m[2], ' ') : [];
    if (!m || fields[2] != m[1] || fields[3] != m[1])
        exit(system('setsid ucode /usr/share/netbird/agent-update-worker.uc ' + command));
}
try {
    let api = loadfile('/usr/share/rpcd/ucode/netbird.uc')();
    let result = api.run(command);
    if (command == 'guard') exit(result.ok && result.data && result.data.allowed ? 0 : 1);
    print(sprintf('%J\n', result));
    exit(result.ok ? 0 : 1);
} catch (e) {
    // Guard failures must pause watchdogs, not accidentally permit mutations.
    warn(sprintf('Agent updater: %s\n', e));
    exit(1);
}
