// SPDX-License-Identifier: Apache-2.0
// Private child entry; caller owns the independent process-group deadline.
import { probe_endpoint } from './probe.uc';
if (length(ARGV) != 2 || length(ARGV[0]) > 4096) exit(2);
let endpoint;
try { endpoint = json(ARGV[0]); }
catch (err) { exit(2); }
print(sprintf('%J', probe_endpoint(endpoint, int(ARGV[1]))));
