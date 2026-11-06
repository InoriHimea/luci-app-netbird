// SPDX-License-Identifier: Apache-2.0
import { run_pending } from './notification.uc';
let result = run_pending();
exit(result.ok || result.reason == 'NO_PENDING_NOTIFICATION' ? 0 : 1);
