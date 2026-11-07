// SPDX-License-Identifier: Apache-2.0
// Called only by the independently guarded command session, before exec.
if (length(ARGV) != 2) exit(125);
let actions = loadfile('/usr/share/rpcd/ucode/lib/action_lock.uc')().create();
exit(actions.publish_command(ARGV[0], ARGV[1]) ? 0 : 125);
