// SPDX-License-Identifier: Apache-2.0
// Command completion is not recovery. Only a new, same-generation native cycle
// may supply path/business postconditions; the owner's maintenance flag is not
// itself a failing path check and must not be mistaken for a health proof.
function recovery_verdict(command, result, config, boot, post_started_ms) {
    if (command?.ok !== true || command.exit_code !== 0 || command.invoked !== true || command.cleanup_confirmed !== true)
        return { outcome: command?.cleanup_confirmed === true ? 'FAILED' : 'UNKNOWN', reason: 'RESTART_COMMAND_FAILED' };
    let run = result?.run;
    if (type(boot) != 'string' || !match(boot, /^[0-9a-f-]{36}$/) || type(post_started_ms) != 'int' ||
        run?.boot_id != boot || run?.config_revision != config?.revision || type(run?.run_id) != 'string' ||
        type(run?.checks) != 'array' || length(run.checks) > 512)
        return { outcome: 'UNKNOWN', reason: 'POST_CHECK_UNVERIFIED' };
    let parts = split(run.run_id, ':');
    if (length(parts) != 2 || parts[0] != boot || !match(parts[1], /^[0-9]{1,16}$/) ||
        int(parts[1]) < post_started_ms || type(run.monotonic_duration_ms) != 'int' ||
        run.monotonic_duration_ms < 0 || run.monotonic_duration_ms > 20000)
        return { outcome: 'UNKNOWN', reason: 'POST_CHECK_STALE' };
    let found = {}, passed = 0, unknown = false, failure = false, paths = 0;
    for (let check in run.checks) {
        if (type(check?.id) != 'string' || found[check.id])
            return { outcome: 'UNKNOWN', reason: 'POST_CHECK_INVALID' };
        found[check.id] = check;
        if (check.required === false) continue;
        if (check.fresh !== true || check.executed !== true ||
            index(['PASS', 'FAIL', 'UNKNOWN', 'NOT_APPLICABLE', 'DISABLED'], check.status) < 0) unknown = true;
        else if (check.status == 'FAIL') failure = true;
        else if (check.status == 'PASS') passed++;
        else if (check.status == 'UNKNOWN') unknown = true;
    }
    // Require every configured active path's actual rules, routes, forwarding
    // lookup and both business vantages, even if a producer omits a denominator.
    for (let path in config.paths || []) if (path.enabled === true) {
        paths++;
        for (let category in ['rules', 'routes', 'peer', 'forward', 'router', 'lan']) {
            let check = found[path.id + ':' + category];
            if (!check || check.status != 'PASS' || check.fresh !== true || check.executed !== true) unknown = true;
        }
    }
    let collection = found['node:collection'];
    if (!collection || collection.status != 'PASS' || collection.fresh !== true || collection.executed !== true ||
        result.snapshot?.complete !== true || type(run.generation) != 'string' || !length(run.generation) ||
        result.snapshot.generation != run.generation) unknown = true;
    if (failure) return { outcome: 'FAILED', reason: 'POST_CHECK_FAILED' };
    if (!paths) return { outcome: 'UNKNOWN', reason: 'NO_APPROVED_PATH' };
    if (unknown || run.convergence?.phase != 'ready')
        return { outcome: passed ? 'PARTIAL' : 'UNKNOWN', reason: 'POST_CHECK_INCOMPLETE' };
    return { outcome: 'RESTORED', reason: 'POST_CHECK_PASSED' };
}
export { recovery_verdict };
