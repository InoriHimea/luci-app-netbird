// SPDX-License-Identifier: Apache-2.0
import { mkdtemp, readfile, writefile, chmod, unlink, symlink } from 'fs';
import { create_automatic_store } from '../../luci-app-netbird/root/usr/share/netbird/health/automatic-store.uc';
let root = mkdtemp('/tmp/nbh-automatic.XXXXXX'), now = 10000, n = 0;
const boot = '11111111-1111-4111-8111-111111111111';
function check(ok, label) { if (!ok) die(`FAIL: ${label}\n`); printf('ok %d - %s\n', ++n, label); }
function id(value) { return sprintf('%032x', value); }
let store = create_automatic_store(root, () => now, boot);
check(store.reserve(id(1), 7).reason == 'AUTOMATIC_DISABLED', 'missing state is default off');
check(store.set_enabled(true, 'root', 7, false).reason == 'LAYOUT_UNVERIFIED', 'explicit enable without verified layout is rejected');
check(store.set_enabled(true, 'root', 7, true).ok, 'explicit actor and verified configuration arm the independent switch');
let initial = readfile(root + '/state.json');
for (let i = 0; i < 10; i++) store.get();
check(readfile(root + '/state.json') == initial, 'status polling does not rewrite persistent budget');
check(store.reserve(id(1), 8).reason == 'LAYOUT_RECONFIRMATION_REQUIRED', 'configuration change cannot inherit prior layout approval');
check(store.reserve(id(1), 7).ok, 'first event reserves durably before any dispatch');
let pending = create_automatic_store(root, () => now, boot);
check(pending.reserve(id(2), 7).reason == 'AUTOMATIC_INCIDENT_ALREADY_ATTEMPTED', 'process restart cannot repeat an unacknowledged dispatch');
check(pending.finish(id(1), 'FAILED', 'POST_CHECK_FAILED').ok, 'unsuccessful recovery has a terminal incident');
now += 3600000;
check(pending.reserve(id(2), 7).reason == 'AUTOMATIC_INCIDENT_ALREADY_ATTEMPTED', 'elapsed cooldown cannot retry a still-failed incident');
check(pending.set_enabled(false, 'root', 7, false).ok && pending.set_enabled(true, 'root', 7, true).ok,
    'explicit switch changes are permitted without erasing recovery state');
check(pending.reserve(id(2), 7).reason == 'AUTOMATIC_INCIDENT_ALREADY_ATTEMPTED', 'off/on does not mint another attempt');
let consent = pending.get().state;
check(consent.authorization_id != consent.episode.authorization_id && consent.episode.actor == 'root',
    'off/on invalidates late worker consent while preserving the charged original actor');
check(pending.clear(id(1), false).reason == 'AUTOMATIC_RECOVERY_UNVERIFIED', 'unknown LAN or business cannot reset incident');
check(pending.clear(id(1), true).ok, 'verified sustained recovery can end the incident');
check(pending.reserve(id(2), 7).ok, 'a new incident after cooldown can charge exactly once');
check(pending.finish(id(2), 'UNKNOWN', 'POST_CHECK_UNAVAILABLE').ok && pending.clear(id(2), true).ok,
    'later independent evidence can close a previously unknown result');
now += 1799999;
check(pending.reserve(id(3), 7).reason == 'AUTOMATIC_COOLDOWN', 'new incident cannot bypass thirty-minute cooldown');
now++;
check(pending.reserve(id(3), 7).ok, 'exact cooldown boundary permits new independent incident');
pending.finish(id(3), 'RESTORED', 'POST_CHECK_PASSED'); pending.clear(id(3), true);
let charge = json(readfile(root + '/state.json')).last_attempt.started_ms;
now = charge - 1;
check(pending.reserve(id(4), 7).reason == 'AUTOMATIC_CLOCK_REVERSED', 'monotonic reversal cannot free budget');
let reboot = create_automatic_store(root, () => now, '22222222-2222-4222-8222-222222222222');
now = 1799999;
let before = readfile(root + '/state.json');
check(reboot.reserve(id(4), 7).reason == 'AUTOMATIC_COOLDOWN', 'reboot must prove its own full thirty minutes elapsed');
check(readfile(root + '/state.json') == before, 'reboot cooldown checks need no persistent reanchor writes');
now++;
check(reboot.reserve(id(4), 7).ok, 'new boot can charge only after full own-uptime cooldown');
check(reboot.reserve(id(5), 7).reason == 'AUTOMATIC_INCIDENT_ALREADY_ATTEMPTED', 'new-boot dispatch remains single attempt');
let stored = readfile(root + '/state.json');
chmod(root + '/state.json', 0644);
check(reboot.get().reason == 'AUTOMATIC_STATE_INVALID', 'world-readable state is not adopted');
chmod(root + '/state.json', 0600);
let broken = json(stored); delete broken.last_attempt;
writefile(root + '/state.json', sprintf('%J', broken));
check(reboot.get().reason == 'AUTOMATIC_STATE_INVALID', 'truncated budget object cannot reset prior charges');
writefile(root + '/state.json', stored); unlink(root + '/state.json');
symlink('/etc/passwd', root + '/state.json');
check(reboot.get().reason == 'AUTOMATIC_STATE_INVALID', 'symlink state is rejected without adopting its target');
printf('PASS: %d automatic durable budget assertions\n', n);
