// SPDX-License-Identifier: Apache-2.0
import { open, lsdir, unlink } from 'fs';
import { private_dir, read_json, atomic_json } from './storage.uc';
import { opaque_id } from './jobs.uc';
import { monotonic_ms } from './runner.uc';
function create_pages(root, clock) {
    clock ??= monotonic_ms;
    function names() { return filter(lsdir(root) || [], name => match(name, /^page-[0-9a-f]{32}\.json$/)); }
    function response(snapshot, index) {
        let offset = index * snapshot.limit, end = min(offset + snapshot.limit, length(snapshot.rows));
        return { ok: true, items: slice(snapshot.rows, offset, end), total: length(snapshot.rows),
            offset, has_more: end < length(snapshot.rows), next_cursor: snapshot.cursors[index + 1] || null,
            metadata: snapshot.metadata };
    }
    function first(kind, rows, metadata, limit) {
        if (index(['checks', 'events'], kind) < 0 || type(rows) != 'array' || length(rows) > 4096 ||
            type(metadata) != 'object' || type(limit) != 'int' || limit < 1 || limit > 100)
            return { ok: false, reason: 'PAGE_INVALID' };
        if (length(rows) <= limit) return response({ rows, metadata, limit, cursors: [] }, 0);
        if (!private_dir(root)) return { ok: false, reason: 'STORAGE_UNAVAILABLE' };
        let lock = open(root + '/pages.lock', 'a', 0600);
        if (!lock || !lock.lock('xn')) { if (lock) lock.close(); return { ok: false, reason: 'PAGES_BUSY' }; }
        let result;
        try {
            let id = opaque_id(), now = clock(), cursors = [];
            if (!id) result = { ok: false, reason: 'ID_UNAVAILABLE' };
            else {
                for (let offset = 0; offset < max(1, length(rows)); offset += limit) {
                    let token = opaque_id();
                    if (!token || index(cursors, token) >= 0) { result = { ok: false, reason: 'ID_UNAVAILABLE' }; break; }
                    push(cursors, token);
                }
                if (!result) {
                    let retained = [];
                    for (let name in names()) {
                        let old = read_json(root + '/' + name, 524288);
                        push(retained, { name, created_ms: old?.created_ms || 0 });
                    }
                    sort(retained, (a, b) => a.created_ms - b.created_ms);
                    // Reserve room before publication, including interrupted publishers.
                    while (length(retained) >= 4) {
                        if (!unlink(root + '/' + shift(retained).name)) { result = { ok: false, reason: 'STORAGE_UNAVAILABLE' }; break; }
                    }
                    if (!result) {
                        let snapshot = { kind, rows, metadata, limit, cursors, created_ms: now, expires_ms: now + 600000 };
                        result = atomic_json(root, 'page-' + id + '.json', snapshot) ? response(snapshot, 0) :
                            { ok: false, reason: 'PAGE_TOO_LARGE' };
                    }
                }
            }
        }
        catch (e) { result = { ok: false, reason: 'PAGE_STATE_INVALID' }; }
        lock.close();
        return result;
    }
    function next(kind, cursor) {
        if (index(['checks', 'events'], kind) < 0 || type(cursor) != 'string' || !match(cursor, /^[0-9a-f]{32}$/))
            return { ok: false, reason: 'CURSOR_INVALID' };
        for (let name in names()) {
            let snapshot = read_json(root + '/' + name, 524288);
            if (type(snapshot?.cursors) != 'array' || snapshot.kind != kind) continue;
            let position = index(snapshot.cursors, cursor);
            if (position < 0) continue;
            let now = clock();
            if (now < snapshot.created_ms || now > snapshot.expires_ms) return { ok: false, reason: 'CURSOR_EXPIRED' };
            if (type(snapshot.rows) != 'array' || type(snapshot.limit) != 'int' || snapshot.limit < 1 || snapshot.limit > 100)
                return { ok: false, reason: 'PAGE_STATE_INVALID' };
            return response(snapshot, position);
        }
        return { ok: false, reason: 'CURSOR_UNKNOWN' };
    }
    return { first, next };
}
export { create_pages };
