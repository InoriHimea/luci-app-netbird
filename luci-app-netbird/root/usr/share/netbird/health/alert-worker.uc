// SPDX-License-Identifier: Apache-2.0
import { production_alerts } from './alert-runtime.uc';
let alerts = production_alerts();
if (!alerts) exit(2);
let result = alerts.run_pending();
exit(result.ok ? 0 : 1);
