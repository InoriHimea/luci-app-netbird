// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Tailscale Inc & AUTHORS  (attribution retained; see NOTICE)
// Modified from luci-app-tailscale-community@eabe1288afe024566b930b26681a722ccf07b19b
// 函数体整段复制自上游 commit 301f02e
//
// Canonical runtime path:    /usr/share/rpcd/ucode/lib/shell.uc
// Repo canonical source:     root/usr/share/rpcd/ucode/lib/shell.uc
//
// shell_quote(s) — POSIX sh safe single-quote wrapping
// 不变量：printf '%s\n' shell_quote(x) 的输出等于 x
// 内部 ' 通过 '\'' 序列转义（关闭当前单引号段 → 字面 ' → 开启新单引号段）
//
// module-compat：本文件作为 ucode 模块经 loadfile()() 加载，返回 { shell_quote, with_timeout }。
// ucode 2025.07.18 不支持 export 关键字，只接受顶层 return 模式；
// 同时去掉 shebang 与 'use strict'（loadfile 模式不需要）。

function shell_quote(s) {
    if (s == null || s == '') return "''";
    return "'" + replace(s, "'", "'\\''") + "'";
}
let action_owner = null;
function set_owner(id) { action_owner = id; }

// Every bounded legacy command gets the same independent deadline and group
// drain as health actions. Killing only a CLI/init parent leaves orphan writers
// that can outlive the shared lifecycle owner. No timeout-applet fallback is safe.
function with_timeout(cmd, secs) {
    secs = (type(secs) == 'int' && secs > 0) ? min(secs, 600) : 5;
    return '/usr/bin/ucode /usr/share/netbird/legacy-command.uc ' + secs + ' ' + shell_quote(cmd) +
        ' ' + shell_quote(action_owner || '-');
}

return { shell_quote, with_timeout, set_owner };
