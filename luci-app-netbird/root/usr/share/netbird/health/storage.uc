// SPDX-License-Identifier: Apache-2.0
import { lstat, mkdir, open, rename, unlink, lsdir } from 'fs';
const MAX_STATE = 524288;
export function private_dir(path) {
    let st = lstat(path);
    if (!st) { if (!mkdir(path, 0700)) return false; st = lstat(path); }
    return st?.type == 'directory' && st.uid == 0 && st.mode == 0700;
};
export function read_json(path, limit) {
    if (type(limit) != 'int' || limit < 1 || limit > MAX_STATE) return null;
    let st = lstat(path);
    if (st?.type != 'file' || st.size > limit) return null;
    let f = open(path, 'r');
    if (!f) return null;
    let text = f.read(limit + 1); f.close();
    if (type(text) != 'string' || length(text) > limit) return null;
    try { return json(text); } catch (e) { return null; }
};
export function atomic_json(dir, name, data, limit) {
    limit ??= MAX_STATE;
    if (type(name) != 'string' || !match(name, /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,95}$/) ||
        type(limit) != 'int' || limit < 1 || limit > MAX_STATE || !private_dir(dir)) return false;
    let text = sprintf('%J\n', data);
    if (length(text) > limit) return false;
    // Single serialized writer only. Recover its interrupted private temporary file;
    // never adopt a symlink or a file with unexpected ownership/permissions.
    // History sequences share one recoverable stage; killed writes cannot
    // accumulate a new temporary file with every published sequence.
    let temporary = dir + '/' + (match(name, /^history-[0-9]{10}\.json$/) ? '.history' : name) + '.new';
    let stale = lstat(temporary);
    if (stale && (stale.type != 'file' || stale.uid != 0 || stale.mode != 0600 || !unlink(temporary)))
        return false;
    let f = open(temporary, 'wx', 0600);
    if (!f) return false;
    let written = f.write(text); f.close();
    if (written != length(text) || !rename(temporary, dir + '/' + name)) {
        unlink(temporary); return false;
    }
    return true;
};
export function keep_history(dir, limit, byte_limit) {
    byte_limit ??= 4194304;
    if (!private_dir(dir) || type(limit) != 'int' || limit < 0 || limit > 1000 ||
        type(byte_limit) != 'int' || byte_limit < 0 || byte_limit > 4194304) return false;
    let names = [];
    for (let name in lsdir(dir) || [])
        if (match(name, /^history-[0-9]{10}\.json$/)) push(names, name);
    sort(names);
    let bytes = 0, kept = 0;
    for (let i = length(names) - 1; i >= 0; i--) {
        let path = dir + '/' + names[i], st = lstat(path);
        if (st?.type != 'file') continue;
        if (kept >= limit || bytes + st.size > byte_limit) unlink(path);
        else { bytes += st.size; kept++; }
    }
    return true;
};
