// SPDX-License-Identifier: Apache-2.0
import * as health from '/usr/share/netbird/health/api.uc';
import { prepare_export } from '/usr/share/netbird/health/export.uc';
import { test_notification } from '/usr/share/netbird/health/notification.uc';
import { authenticated_actor } from '/usr/share/netbird/health/actor.uc';
import * as recovery from '/usr/share/netbird/health/recovery.uc';
const envelope = loadfile('/usr/share/rpcd/ucode/lib/envelope.uc')();
const CODE = envelope.CODE;
function handler(method) {
    return function(request) {
        try {
            // rpcd/uhttpd enforces the exact method ACL before invocation.
            // Never log or return request.args.ubus_rpc_session or raw exceptions.
            let result = method(request.args || {});
            if (result.ok) { delete result.ok; return envelope.ok(result); }
            let reason = type(result.reason) == 'string' && match(result.reason, /^[A-Z][A-Z0-9_]{0,63}$/) ?
                result.reason : 'HEALTH_OPERATION_FAILED';
            let code = match(reason, /_EXPIRED$/) ? CODE.EXPIRED :
                match(reason, /_UNKNOWN$/) ? CODE.NOT_FOUND :
                match(reason, /_CONFLICT$|^CONFIG_CHANGED$/) ? CODE.CONFLICT :
                match(reason, /_NOT_CONFIGURED$|^MONITOR_DISABLED$/) ? CODE.NOT_CONFIGURED :
                match(reason, /_BUSY$/) ? CODE.RESOURCE_BUSY :
                match(reason, /_INVALID$/) ? CODE.INVALID_INPUT : CODE.HEALTH_ERROR;
            return envelope.err(code, reason);
        }
        catch (e) { return envelope.err(CODE.INTERNAL_ERROR, 'HEALTH_OPERATION_FAILED'); }
    };
}
function authenticated(method) {
    return authenticated_actor(function(request, actor) {
        return handler(() => method(request.args || {}, actor))({ args: {} });
    }, function() { return envelope.err(CODE.PERMISSION_DENIED, 'RECOVERY_DENIED'); }, false);
}
return {
    'luci.netbird.health': {
        get_summary: { args: {}, call: handler(health.get_summary) },
        get_checks: { args: { cursor: '', limit: 0 }, call: handler(health.get_checks) },
        get_events: { args: { cursor: '', limit: 0 }, call: handler(health.get_events) },
        get_config: { args: {}, call: handler(health.get_config) },
        start_check: { args: { path_id: '' }, call: handler(health.start_check) },
        get_job: { args: { id: '' }, call: handler(health.get_job) },
        prepare_export: { args: { id: '', offset: 0 }, call: handler(prepare_export) },
        test_notification: { args: {}, call: handler(test_notification) },
        prepare_recovery: { args: { expected_revision: 0 }, call: authenticated(recovery.prepare_recovery) },
        start_recovery: { args: { id: '', expected_revision: 0, confirmed: false }, call: authenticated(recovery.start_recovery) },
        get_recovery_job: { args: { id: '' }, call: authenticated(recovery.get_recovery_job) },
        set_config: { args: { config: {}, expected_revision: 0 }, call: handler(health.set_config) }
    }
};
