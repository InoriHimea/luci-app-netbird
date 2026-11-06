// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, lsdir, unlink, rmdir } from 'fs';
import { create_exports } from '../../luci-app-netbird/root/usr/share/netbird/health/export.uc';
let root = mkdtemp('/tmp/nbh-export-test.XXXXXX'), now = 1000, n = 0;
function check(ok, label) { if (!ok) die(label + '\n'); n++; }
let exports = create_exports(root, () => now);
let result = { sampled_at: 123, sequence: 4, run: { run_id: 'boot:one', config_revision: 3,
    overall: 'unknown', expected_count: 2, unknown_count: 2,
    checks: [{ id: 'agent', code: 'COMMAND_TIMEOUT', status: 'UNKNOWN', observed: 'command exceeded deadline',
        token: 'MUST_NOT_ESCAPE', private_key: 'PRIVATE_MUST_NOT_ESCAPE' },
        { id: 'bad', code: 'COMMAND_FAILED', status: 'UNKNOWN', observed: 'Authorization: Bearer MUST_NOT_ESCAPE' }] },
    snapshot: { reason: 'GENERATION_CHANGED', token: 'MUST_NOT_ESCAPE' }, session: 'MUST_NOT_ESCAPE' };
let created = exports.create(result);
check(created.ok && match(created.id, /^[0-9a-f]{32}$/) && match(created.sha256, /^[0-9a-f]{64}$/), 'native hashed export issued');
let part = exports.get(created.id, 0), text = b64dec(part.content_base64), evidence = json(text);
check(part.ok && !part.has_more && length(text) == created.size && part.sha256 == created.sha256,
    'chunk metadata describes exact hashed payload');
check(index(text, 'MUST_NOT_ESCAPE') < 0 && index(text, 'PRIVATE_MUST_NOT_ESCAPE') < 0 &&
    evidence.sampled_run.checks[0].code == 'COMMAND_TIMEOUT' &&
    evidence.sampled_run.checks[0].observed == 'command exceeded deadline' && evidence.collection.reason == 'GENERATION_CHANGED',
    'secrets removed while original bounded diagnostic reasons retained');
check(exports.get('../latest.json', 0).reason == 'EXPORT_INVALID', 'export ID cannot select paths');
check(exports.get('00000000000000000000000000000000', 0).reason == 'EXPORT_UNKNOWN', 'unknown ID explicit');
check(exports.get(created.id, -1).reason == 'OFFSET_INVALID' && exports.get(created.id, created.size + 1).reason == 'OFFSET_INVALID', 'out-of-range offsets rejected');
now += 600001;
check(exports.get(created.id, 0).reason == 'EXPORT_EXPIRED', 'expired export explicit');
for (let i = 0; i < 6; i++) check(exports.create(result).ok, 'bounded export rotation remains usable');
check(length(filter(lsdir(root), name => match(name, /^export-[0-9a-f]{32}\.json$/))) <= 4, 'retained exports bounded');
result.run.boot_id = 'c4d75208-325f-4b97-ba75-be160cbe3365';
result.run.run_id = result.run.boot_id + ':12345';
result.run.checks = [];
let description = '';
for (let i = 0; i < 50; i++) description += 'route unavailable; ';
for (let i = 0; i < 40; i++) push(result.run.checks, { id: 'check-' + i, observed: description });
let large = exports.create(result), offset = 0, assembled = '';
while (offset < large.size) {
    let chunk = exports.get(large.id, offset);
    check(chunk.ok && chunk.offset == offset && chunk.next_offset > offset &&
        length(b64dec(chunk.content_base64)) <= 16384, 'chunk offsets advance within transport bound');
    assembled += b64dec(chunk.content_base64); offset = chunk.next_offset;
}
let restored = json(assembled);
check(large.size > 16384 && length(assembled) == large.size && length(restored.sampled_run.checks) == 40,
    'multi-chunk evidence reconstructs complete bounded JSON');
check(restored.sampled_run.boot_id == result.run.boot_id && restored.sampled_run.run_id == result.run.run_id,
    'public boot and run identities are not confused with credentials');
for (let name in lsdir(root)) unlink(root + '/' + name);
rmdir(root);
print('export: ', n, ' assertions passed\n');
