// SPDX-License-Identifier: Apache-2.0
'use strict';
'require view';
'require rpc';
'require dom';
'require poll';
'require ui';
'require view.netbird.health-common as health';

var getConfig = rpc.declare({ object: 'luci.netbird.health', method: 'get_config', expect: {} });
var setConfig = rpc.declare({ object: 'luci.netbird.health', method: 'set_config', params: ['config', 'expected_revision'], expect: {} });
var startCheck = rpc.declare({ object: 'luci.netbird.health', method: 'start_check', params: ['path_id'], expect: {} });
var getJob = rpc.declare({ object: 'luci.netbird.health', method: 'get_job', params: ['id'], expect: {} });
var exportEvidence = rpc.declare({ object: 'luci.netbird.health', method: 'prepare_export', params: ['id', 'offset'], expect: {} });
var notify = rpc.declare({ object: 'luci.netbird.health', method: 'test_notification', expect: {} });
var prepareRecovery = rpc.declare({ object: 'luci.netbird.health', method: 'prepare_recovery', params: ['expected_revision'], expect: {} });
var startRecovery = rpc.declare({ object: 'luci.netbird.health', method: 'start_recovery', params: ['id', 'expected_revision', 'confirmed'], expect: {} });
var getRecoveryJob = rpc.declare({ object: 'luci.netbird.health', method: 'get_recovery_job', params: ['id'], expect: {} });
var access = rpc.declare({ object: 'session', method: 'access', params: ['scope', 'object', 'function'], expect: { access: false } });
var methods = ['start_check', 'set_config', 'prepare_export', 'test_notification', 'start_recovery'];

return view.extend({
 load: function () {
  return Promise.all(methods.map(function (method) {
   return L.resolveDefault(access('ubus', 'luci.netbird.health', method), false);
  }));
 },
 render: function (permissions) {
  var box = E('div', { 'class': 'cbi-map nb-health', 'id': 'nb-health-page' });
  var summaryBox = E('section', { 'aria-live': 'polite' }), issueBox = E('section'), evidenceBox = E('section');
  var eventBox = E('section'), message = E('p', { 'role': 'status', 'aria-live': 'polite' });
  var alertBox = E('section', { 'id': 'nb-health-alert-state', 'aria-live': 'polite' });
  var recoveryBox = E('section', { 'id': 'nb-health-recovery-result', 'aria-live': 'polite' });
  var recoveryId = E('input', { 'type': 'text', 'maxlength': 32, 'aria-label': _('Recovery job ID for result query') });
  var recoveryStorageKey = 'netbird-health-recovery-job';
  try { recoveryId.value = window.localStorage.getItem(recoveryStorageKey) || ''; } catch (e) {}
  var configError = E('p', { 'class': 'alert-message warning' });
  var editor = E('textarea', { 'id': 'nb-health-config', 'rows': 20, 'spellcheck': 'false', 'aria-label': _('Approved health configuration JSON') });
  var path = E('select', { 'id': 'nb-health-path', 'aria-label': _('Approved path for immediate check') });
  var buttons = [], jobs = {}, config = null, current = null, failure = _('Loading cached evidence'), busy = false, reading = false, attached = false;
  var armExpiry = health.expiryGuard(box, draw);
  var armObserverExpiry = health.expiryGuard(box, draw);
  function independentFresh(value) {
   var now = Date.now() / 1000;
   return !!(value && value.fresh === true && Number.isFinite(value.sampled_at) && Number.isFinite(value.max_age) &&
    now >= value.sampled_at && now - value.sampled_at <= value.max_age);
  }
  function say(value) { message.textContent = String(value); }
  function updateControls() {
   buttons.forEach(function (entry) {
    entry.node.disabled = busy || permissions[entry.permission] !== true ||
     (entry.permission === 0 && (!config || !config.monitor.enabled || !path.value || Object.keys(jobs).some(function (id) { return jobs[id] === 'check'; }))) ||
     (entry.permission === 4 && entry.needsConfig && (!config || !config.monitor.enabled || Object.keys(jobs).some(function (id) { return jobs[id] === 'recovery'; }))) ||
     (entry.needsConfig && !config);
   });
   editor.disabled = busy || permissions[1] !== true || !config;
   path.disabled = busy || permissions[0] !== true;
  }
  path.addEventListener('change', updateControls);
  function draw() {
   armExpiry(current && current.summary);
   var expanded = new Set(Array.from(evidenceBox.querySelectorAll('details[open]')).map(function (node) { return node.getAttribute('data-check-id'); }));
   var expandedEvents = new Set(Array.from(eventBox.querySelectorAll('details[open]')).map(function (node) { return node.getAttribute('data-event-id'); }));
   var summary = current && current.summary, valid = !failure && health.fresh(summary);
   dom.content(summaryBox, health.summaryNode(summary, failure));
   var observer = summary && summary.observer, notification = summary && summary.notification;
   armObserverExpiry(observer && { run: { flags: {} }, fresh: observer.fresh, scope: 'full_approved_baseline',
    sampled_at: observer.sampled_at, max_age: observer.max_age });
   dom.content(alertBox, [ E('h3', {}, _('Observer and notification state (independent of health)')),
    E('p', {}, _('Notification acceptance is not a verified user receipt. Central/local/none has one owner; automatic takeover is disabled. Retries may have at-least-once risk.')),
    E('pre', {}, health.literal({ observer: independentFresh(observer) ? observer : { state: 'unknown', failure: null },
     notification: notification ? Object.assign({}, notification, independentFresh(notification) ? {} : { state: 'unknown', fresh: false }) :
      { state: 'unknown', receipt_verified: false } })) ]);
   var items = current ? current.checks : [];
   var issues = items.filter(function (item) { return !valid || !item.fresh || item.status !== 'PASS'; });
   dom.content(issueBox, [ E('h3', {}, _('Issues / unverified obligations')), E('p', {},
    !current ? _('Evidence unavailable; this is not an all-PASS result.') : !issues.length ?
     _('No failing or unverified checks in this complete fresh snapshot.') : _('Expand the checks below for evidence; disabled and not-applicable items remain in the denominator.'))
   ].concat(issues.map(function (item) { return E('p', {}, [ health.pill(valid && item.fresh ? item.status : 'UNKNOWN'), ' ', health.literal(item.id), ' — ', health.literal(item.code) ]); })));
   dom.content(evidenceBox, [ E('h3', {}, _('Rules, routes, paths and protocol-layer evidence')) ].concat(items.map(function (item) { return health.evidenceNode(item, valid); })));
   evidenceBox.querySelectorAll('details').forEach(function (node) { node.open = expanded.has(node.getAttribute('data-check-id')); });
   var timeline = current && current.events;
   dom.content(eventBox, [ E('h3', {}, _('Event timeline and evidence gaps')),
    E('p', { 'class': 'alert-message warning' }, _('Bounded retained snapshot differences only. Events may be missing between samples; actor is unknown and cause is undetermined. This is not a lossless RTNL log.'))
   ].concat(timeline ? timeline.items.map(function (event) {
    return E('details', { 'data-event-id': event.run_id }, [ E('summary', {}, health.literal(health.stamp(event.sampled_at) + ' — ' + health.text(event.type))),
     E('pre', {}, health.literal(event)) ]);
   }) : [ E('p', {}, _('Timeline unavailable; no absence-of-events claim.')) ]));
   eventBox.querySelectorAll('details').forEach(function (node) { node.open = expandedEvents.has(node.getAttribute('data-event-id')); });
  }
  function readConfig(fill) {
   return getConfig().then(health.checked).then(function (data) {
    if (!data.config || data.config.revision !== data.revision) throw new Error(_('Invalid configuration revision'));
    config = data.config;
    dom.content(configError, _('Only netbird_health is saved. NetBird, network and firewall are not restarted. Approval identity is an administrator-supplied label, not authenticated actor proof.'));
    configError.appendChild(document.createTextNode(' ' + _('Monitor timing: grace_period 0–600s (boot-relative), convergence_timeout 5–600s (default 60), event_debounce 1–10s (default 2). Event floods and service reloads never renew an open deadline.')));
    if (fill) editor.value = JSON.stringify(config, null, 2);
    var selected = path.value;
    dom.content(path, [ E('option', { 'value': '' }, _('Select an approved enabled path')) ].concat(config.paths.filter(function (item) { return item.enabled && item.approval.approved; })
     .map(function (item) { return E('option', { 'value': item.id }, health.literal(item.id + ' — from ' + item.source_ip + ' iif ' + item.ingress_interface + ' mark ' + health.text(item.optional_mark))); })));
    path.value = selected;
    updateControls();
   }).catch(function (error) { config = null; configError.textContent = error.message; updateControls(); });
  }
  function refresh() {
   if (reading) return Promise.resolve();
   reading = true;
   return health.snapshot().then(function (data) { current = data; failure = null; })
    .catch(function (error) { failure = error.message; })
    .finally(function () { reading = false; draw(); });
  }
  function action(permission, fn) {
   return function () {
    if (busy || permissions[permission] !== true) return Promise.resolve();
    busy = true; updateControls();
    return Promise.resolve().then(fn).catch(function (error) { say(error.message || error); })
     .finally(function () { busy = false; updateControls(); });
   };
  }
  function button(label, permission, fn, needsConfig) {
   var node = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-action', 'click': action(permission, fn) }, label);
   buttons.push({ node: node, permission: permission, needsConfig: needsConfig === true || permission === 1 && needsConfig !== false }); return node;
  }
  function track(data, kind) {
   if (!data.job || !data.job.id) throw new Error(_('Missing job identifier; submission outcome unknown, do not automatically retry.'));
   jobs[data.job.id] = kind;
   say((data.coalesced ? _('Merged with existing job: ') : _('Backend job: ')) + data.job.id + ' — ' + data.job.state +
    (kind === 'check' ? ' (' + _('full approved baseline; browser closure does not cancel it') + ')' : ' (' + _('test submission is not verified delivery') + ')'));
  }
  function readJobs() {
   return Promise.all(Object.keys(jobs).map(function (id) {
    return (jobs[id] === 'recovery' ? getRecoveryJob(id) : getJob(id)).then(health.checked).then(function (data) {
     var job = data.job;
     if (!job || !job.state) throw new Error(_('Invalid job response'));
     if (jobs[id] === 'recovery') dom.content(recoveryBox, [ E('h3', {}, _('Managed restart result — not command-exit proof')),
      E('p', {}, _('Required fresh rules, routes, actual forwarding and business vantages determine recovery. Missing LAN evidence never becomes green. No automatic resubmission.')),
      E('pre', {}, health.literal(job)) ]);
     if (job.state !== 'queued' && job.state !== 'running') {
      say(_('Backend job finished: ') + id + ' — ' + job.state + ' / ' + health.text(job.outcome || job.result || job.reason || job.delivery_state) +
       (jobs[id] === 'notification' ? ' (' + _('receipt not verified') + ')' : ''));
      delete jobs[id];
     }
    }).catch(function (error) { say(id + ': ' + error.message + ' (' + _('outcome unknown; retain the ID and query it, no automatic resubmission') + ')'); delete jobs[id]; });
   })).then(updateControls);
  }
  function save(next) {
   if (!config || next.revision !== config.revision) throw new Error(_('Configuration revision changed; reload the editor before saving.'));
   return setConfig(next, config.revision).then(health.checked).then(function (data) {
    say(_('Independent health configuration saved; reload state: ') + health.text(data.reload_state));
    return readConfig(true).then(refresh);
   });
  }
  function confirmPause() {
   if (!config) return;
   var next = JSON.parse(JSON.stringify(config)); next.monitor.enabled = !next.monitor.enabled;
   return new Promise(function (resolve) {
    ui.showModal(next.monitor.enabled ? _('Resume health inspection?') : _('Pause health inspection?'), [
     E('p', {}, _('Changes only independent health scheduling, not NetBird connectivity. Unsaved editor changes are not applied.')),
     E('button', { 'class': 'btn', 'click': function () { ui.hideModal(); resolve(); } }, _('Cancel')),
     E('button', { 'class': 'btn cbi-button-positive', 'click': function () { ui.hideModal(); resolve(Promise.resolve().then(function () { return save(next); })); } }, _('Confirm'))
    ]);
   });
  }
  function queryRecovery() {
   var id = recoveryId.value.trim();
   if (!/^[0-9a-f]{32}$/.test(id)) throw new Error(_('Enter the 32-character recovery job ID.'));
   jobs[id] = 'recovery'; return readJobs();
  }
  function confirmRecovery() {
   if (!config) throw new Error(_('Health configuration unavailable.'));
   return prepareRecovery(config.revision).then(health.checked).then(function (prepared) {
    if (!/^[0-9a-f]{32}$/.test(prepared.id) || prepared.operation !== 'managed_agent_restart' || !Number.isInteger(prepared.revision))
     throw new Error(_('Invalid recovery confirmation.'));
    return new Promise(function (resolve) {
     var agreed = E('input', { 'type': 'checkbox' }), accepted = false;
     var confirm = E('button', { 'class': 'btn cbi-button-negative', 'disabled': true, 'click': function () {
      if (accepted || !agreed.checked) return;
      accepted = true; confirm.disabled = true; ui.hideModal();
      // Retain the non-secret ID before submission; a lost reply must only be
      // queried, never automatically confirmed or restarted a second time.
      recoveryId.value = prepared.id; jobs[prepared.id] = 'recovery';
      try { window.localStorage.setItem(recoveryStorageKey, prepared.id); } catch (e) {}
      say(_('Recovery job ID (retain for reconnect): ') + prepared.id);
      resolve(startRecovery(prepared.id, prepared.revision, true).then(health.checked).then(function (data) {
       if (!data.job || data.job.id !== prepared.id) throw new Error(_('Recovery acknowledgement missing; query the saved ID, do not resubmit.'));
       return readJobs();
      }));
     } }, _('Confirm one managed agent restart'));
     agreed.addEventListener('change', function () { confirm.disabled = !agreed.checked || accepted; });
     ui.showModal(_('Restart managed NetBird agent?'), [
      E('p', { 'class': 'alert-message warning' }, health.literal(prepared.impact)),
      E('p', {}, _('Authenticated operator: ') + health.text(prepared.actor) + ' — ' + _('Operation: managed service restart once; no down/up, login or route repair.')),
      E('details', {}, [ E('summary', {}, _('Evidence before confirmation (sampled, not current proof)')), E('pre', {}, health.literal(prepared.evidence)) ]),
      E('label', {}, [ agreed, ' ', _('I understand that the Mesh connection and this page may disconnect. I explicitly approve this one restart.') ]),
      E('div', { 'class': 'right' }, [ E('button', { 'class': 'btn', 'click': function () { if (!accepted) { accepted = true; ui.hideModal(); resolve(); } } }, _('Cancel')), confirm ]) ]);
    });
   });
  }
  function download() {
   var metadata, chunks = [], offset = 0;
   return exportEvidence().then(health.checked).then(function (data) {
    if (!/^[0-9a-f]{32}$/.test(data.id) || !/^[0-9a-f]{64}$/.test(data.sha256) || !Number.isInteger(data.size) || data.size < 1 || data.size > 196608)
     throw new Error(_('Invalid export metadata'));
    metadata = data;
    function chunk() {
     return exportEvidence(metadata.id, offset).then(health.checked).then(function (part) {
      if (part.id !== metadata.id || part.sha256 !== metadata.sha256 || part.size !== metadata.size || part.offset !== offset || part.encoding !== 'base64')
       throw new Error(_('Export changed during download'));
      var raw = atob(part.content_base64), bytes = Uint8Array.from(raw, function (c) { return c.charCodeAt(0); });
      if (!bytes.length || bytes.length > 16384 || part.next_offset !== offset + bytes.length || part.next_offset > metadata.size)
       throw new Error(_('Invalid export chunk'));
      chunks.push(bytes); offset = part.next_offset;
      if (part.has_more) return chunk();
      if (offset !== metadata.size) throw new Error(_('Incomplete export'));
      var blob = new Blob(chunks, { type: 'application/json' });
      var link = E('a', { 'href': URL.createObjectURL(blob), 'download': 'netbird-health-' + metadata.id + '.json' });
      document.body.appendChild(link); link.click(); link.remove();
      window.setTimeout(function () { URL.revokeObjectURL(link.href); }, 1000);
      say(_('Redacted sampled evidence downloaded, not current proof. Server SHA-256: ') + metadata.sha256);
     });
    }
    return chunk();
   });
  }
  box.appendChild(E('h2', {}, _('NetBird — Health inspection')));
  box.appendChild(E('p', {}, _('Browser polling reads cached results only. Backend scheduling survives closing this page. No automatic route repair is provided.')));
  box.appendChild(E('p', {}, _('Actions require separate run / configuration / export / notification / recovery permissions. Disabled controls do not grant authority.')));
  box.appendChild(summaryBox); box.appendChild(message);
  box.appendChild(alertBox);
  box.appendChild(E('div', { 'class': 'nb-health-actions' }, [ path,
   button(_('Check now (full approved baseline)'), 0, function () { return startCheck(path.value).then(health.checked).then(function (data) { track(data, 'check'); }); }),
   button(_('Export redacted evidence'), 2, download), button(_('Pause / resume inspection'), 1, confirmPause),
   button(_('Send independent test notification'), 3, function () {
    return new Promise(function (resolve) {
     ui.showModal(_('Send a test notification?'), [ E('p', {}, _('Uses only the protected locally owned sink. HTTP acceptance does not prove receipt. This is not a connectivity repair.')),
      E('button', { 'class': 'btn', 'click': function () { ui.hideModal(); resolve(); } }, _('Cancel')),
      E('button', { 'class': 'btn cbi-button-positive', 'click': function () { ui.hideModal(); resolve(notify().then(health.checked).then(function (data) { track(data, 'notification'); })); } }, _('Send test')) ]);
    });
   }) ]));
  box.appendChild(E('div', { 'class': 'nb-health-actions' }, [
   button(_('Recover: restart managed agent…'), 4, confirmRecovery, true), recoveryId,
   button(_('Query recovery job only (no restart)'), 4, queryRecovery, false) ]));
  box.appendChild(recoveryBox);
  box.appendChild(issueBox); box.appendChild(evidenceBox); box.appendChild(eventBox);
  var configuration = E('details', { 'id': 'nb-health-configuration' }, [ E('summary', {}, _('Approved monitoring configuration (JSON)')), configError,
   E('label', { 'for': 'nb-health-config' }, _('Complete configuration: monitor interval, paths, endpoints, approval and notification ownership. No secrets.')),
   editor, E('div', { 'class': 'nb-health-actions' }, [
    button(_('Save health configuration only'), 1, function () { return save(JSON.parse(editor.value)); }),
    button(_('Reload configuration / discard edits'), 1, function () { return readConfig(true); }, false) ]) ]);
  box.appendChild(configuration);
  draw(); updateControls(); readConfig(true); refresh();
  if (permissions[4] === true && /^[0-9a-f]{32}$/.test(recoveryId.value)) { jobs[recoveryId.value] = 'recovery'; readJobs(); }
  poll.add(function tick() {
   if (!box.isConnected) { if (attached) poll.remove(tick); return Promise.resolve(); }
   attached = true; draw(); return Promise.all([refresh(), readJobs()]);
  }, 5);
  return box;
 },
 handleSaveApply: null,
 handleSave: null,
 handleReset: null
});
