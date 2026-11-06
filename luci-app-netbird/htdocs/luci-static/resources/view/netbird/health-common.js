// SPDX-License-Identifier: Apache-2.0
'use strict';
'require rpc';
'require dom';
'require poll';
'require view.netbird.dom-helpers as nb';

var summary = rpc.declare({ object: 'luci.netbird.health', method: 'get_summary', expect: {} });
var checks = rpc.declare({ object: 'luci.netbird.health', method: 'get_checks', params: ['cursor', 'limit'], expect: {} });
var events = rpc.declare({ object: 'luci.netbird.health', method: 'get_events', params: ['cursor', 'limit'], expect: {} });
var labels = {
 healthy: _('Healthy'), degraded: _('Degraded'), unhealthy: _('Unhealthy'), unknown: _('Unknown / not verified'),
 disabled: _('Disabled'), PASS: _('PASS'), FAIL: _('FAIL'), UNKNOWN: _('UNKNOWN / not verified'),
 NOT_APPLICABLE: _('Not applicable'), DISABLED: _('Disabled')
};
function checked(response) {
 if (!response || response.ok !== true || !response.data) throw new Error(response && response.message || _('Health request failed'));
 return response.data;
}
function text(value) { return value == null ? '—' : typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value); }
function literal(value) { return document.createTextNode(text(value)); }
function pair(label, value) {
 var node = nb.pair(label, ''); node.lastChild.textContent = text(value); return node;
}
function stamp(value) { return Number.isFinite(value) && value > 0 ? new Date(value * 1000).toLocaleString() : _('Never / unavailable'); }
function pill(status) {
 var state = Object.prototype.hasOwnProperty.call(labels, status) ? status : 'unknown';
 return E('strong', { 'class': 'nb-health-state nb-health-' + state, 'data-health-state': state }, labels[state]);
}
var expiryAnchors = new WeakMap();
function deadlines(data) {
 var anchor = expiryAnchors.get(data);
 if (!anchor) {
  var mono = performance.now(), wall = Date.now() / 1000;
  var remaining = data.convergence_remaining_ms;
  anchor = { at: mono, evidence: mono + Math.max(0, data.sampled_at + data.max_age - wall) * 1000,
   convergence: Number.isInteger(remaining) && remaining >= 0 && remaining <= 600000 ? mono + remaining : null };
  expiryAnchors.set(data, anchor);
 }
 return anchor;
}
function waitExpired(data) {
 if (!data) return true;
 var anchor = deadlines(data), now = performance.now();
 return anchor.convergence === null || now < anchor.at || now >= anchor.convergence;
}
function fresh(data) {
 var now = Date.now() / 1000;
 if (!(data && data.run && data.run.flags && data.fresh === true && !data.run.flags.stale &&
  data.scope === 'full_approved_baseline' && Number.isFinite(data.sampled_at) &&
  Number.isFinite(data.max_age) && now >= data.sampled_at && now - data.sampled_at <= data.max_age)) return false;
 var anchor = deadlines(data), mono = performance.now();
 return mono >= anchor.at && mono < anchor.evidence;
}
function expiryGuard(node, repaint) {
 var timer;
 return function (data) {
  window.clearTimeout(timer);
  if (!fresh(data)) return;
  var anchor = deadlines(data), expires = anchor.evidence;
  if (data.run.convergence && data.run.convergence.checking && !waitExpired(data))
   expires = Math.min(expires, anchor.convergence);
  var delay = Math.min(2147483647, Math.max(1, expires - performance.now() + 1));
  timer = window.setTimeout(function () { if (node.isConnected) repaint(); }, delay);
 };
}
function summaryNode(data, failure) {
 var valid = !failure && fresh(data), run = data && data.run || {}, coverage = run.coverage || {};
 var waitingExpired = run.convergence && run.convergence.checking && waitExpired(data);
 var box = E('div', { 'class': 'nb-health-summary', 'aria-live': 'polite' });
 box.appendChild(E('p', {}, [ _('Overall (not the agent Connected state): '), pill(valid ? run.overall : 'unknown') ]));
 if (!valid) box.appendChild(E('p', { 'class': 'alert-message warning' },
  literal(_('Current health is not verified. Previous success is not current proof. ') + text(failure || data && data.reason || 'NO_RESULT'))));
 if (run.flags && run.flags.maintenance) box.appendChild(E('p', {}, _('Maintenance active; results do not authorize recovery.')));
 if (run.flags && run.flags.checking && !waitingExpired) box.appendChild(E('p', {}, run.convergence && run.convergence.checking ?
  _('Waiting for complete network convergence; failed evidence remains visible.') : _('Backend check is running independently of this browser.')));
 if (run.convergence) {
  var phases = { startup_grace: _('Startup grace (bounded)'), converging: _('Network convergence wait (bounded)'),
   ready: _('Complete required structure and business evidence ready'), failed: _('Network convergence failed'), unknown: _('Network convergence unknown') };
  box.appendChild(pair(_('Network rebuild phase (independent of Connected)'), valid && !waitingExpired ?
   text(phases[run.convergence.phase] || phases.unknown) + ' — ' + text(run.convergence.reason) : _('Unknown; wait expired or fresh evidence unavailable')));
 }
 var rows = [
  [_('Local structure'), 'local_structure'], [_('Forwarding path lookup (not LAN proof)'), 'forward_lookup'],
  [_('Router-originated business probe'), 'router_probe'], [_('LAN end-to-end probe'), 'lan_probe'],
  [_('External observer'), 'external_observer']
 ].map(function (entry) {
  return E('div', { 'class': 'nb-health-card' }, [ E('span', {}, entry[0]), pill(valid ? coverage[entry[1]] : 'unknown') ]);
 });
 rows.push(E('div', { 'class': 'nb-health-card' }, [ E('span', {}, _('Evidence freshness')), pill(valid ? 'PASS' : 'UNKNOWN') ]));
 box.appendChild(E('div', { 'class': 'nb-health-grid' }, rows));
 box.appendChild(E('p', {}, _('Without a configured reachable LAN probe, LAN end-to-end is NOT_CONFIGURED / UNKNOWN, never verified by router success.')));
 box.appendChild(pair(_('Sample time'), stamp(data && data.sampled_at)));
 box.appendChild(pair(_('Approved / executed / PASS / FAIL / UNKNOWN / not applicable / disabled'),
  ['expected_count', 'executed_count', 'pass_count', 'fail_count', 'unknown_count', 'not_applicable_count', 'disabled_count']
   .map(function (key) { return text(run[key]); }).join(' / ') + (valid ? '' : ' (' + _('historical counts only') + ')')));
 box.appendChild(pair(_('Run / configuration / scope'), text(run.run_id) + ' / ' + text(run.config_revision) + ' / ' + text(data && data.scope)));
 return box;
}
function evidenceNode(item, valid) {
 var status = valid && item.fresh === true && item.executed === true ? item.status :
  item.status === 'NOT_APPLICABLE' || item.status === 'DISABLED' ? item.status : 'UNKNOWN';
 var detail = E('details', { 'class': 'nb-health-evidence', 'data-check-id': item.id }, [
  E('summary', {}, [ pill(status), ' ', literal(item.id), ' — ', literal(item.code) ])
 ]);
 [ [_('Perspective / protocol layer'), text(item.vantage) + ' / ' + text(item.category)],
  [_('Source / target'), text(item.source) + ' / ' + text(item.target)],
  [_('Expected (including from / iif / mark / rules / routes)'), item.expected],
  [_('Observed / differences'), item.observed], [_('Evidence reference'), item.evidence_ref],
  [_('Sample / last success'), stamp(item.sampled_at) + ' / ' + stamp(item.last_success_at)],
  [_('Execution / parser / exit / duration ms'), text(item.executed) + ' / ' + text(item.parse_status) + ' / ' + text(item.exit_code) + ' / ' + text(item.duration_ms)]
 ].forEach(function (row) { detail.appendChild(E('div', {}, [ E('strong', {}, row[0]), E('pre', {}, literal(row[1])) ])); });
 return detail;
}
function allPages(call, limit) {
 var result = [], metadata, total, cursor = '', seen = {};
 function next() {
  return call(cursor, limit).then(checked).then(function (page) {
   if (!Array.isArray(page.items) || !Number.isInteger(page.total) || page.total < 0 || page.total > 4096 ||
    page.offset !== result.length || page.items.length > limit || page.items.length + result.length > page.total)
    throw new Error(_('Invalid or incomplete health page'));
   if (!metadata) { metadata = page.metadata; total = page.total; }
   if (!metadata || page.total !== total || JSON.stringify(page.metadata) !== JSON.stringify(metadata))
    throw new Error(_('Health evidence changed during pagination; refresh required'));
   result = result.concat(page.items);
   if (page.has_more) {
    if (!page.next_cursor || seen[page.next_cursor] || !page.items.length) throw new Error(_('Invalid health cursor'));
    cursor = page.next_cursor; seen[cursor] = true; return next();
   }
   if (result.length !== total) throw new Error(_('Incomplete health evidence'));
   return { items: result, metadata: metadata, total: total };
  });
 }
 return next();
}
function snapshot() {
 return Promise.all([ summary().then(checked), allPages(checks, 100), allPages(events, 100) ]).then(function (parts) {
  var data = parts[0], page = parts[1];
  if (!data.run || page.metadata.run_id !== data.run.run_id || page.metadata.config_revision !== data.run.config_revision ||
   page.total !== data.check_count || ['boot_id', 'baseline_revision', 'current_config_revision', 'event_sequence', 'sampled_at', 'max_age', 'scope', 'fresh']
    .some(function (key) { return page.metadata[key] !== data[key]; }))
   throw new Error(_('Summary and checks refer to different snapshots; refresh required'));
  return { summary: data, checks: page.items, events: parts[2] };
 });
}
function compact() {
 var box = E('section', { 'class': 'cbi-section nb-health', 'id': 'nb-health-status-summary' }, [
  E('h3', {}, _('Health inspection')), E('a', { 'href': L.url('admin/services/netbird/health') }, _('Open health inspection (read-only summary)'))
 ]), content = E('div'), last = null, failure = _('Loading cached evidence'), armExpiry = expiryGuard(box, paint);
 box.appendChild(content);
 function paint() { armExpiry(last); dom.content(content, summaryNode(last, failure)); }
 function refresh() {
  return summary().then(checked).then(function (data) { last = data; failure = null; paint(); })
   .catch(function (error) { failure = error.message; paint(); });
 }
 paint(); refresh();
 var attached = false;
 poll.add(function tick() {
  if (!box.isConnected) { if (attached) poll.remove(tick); return Promise.resolve(); }
  attached = true; paint(); return refresh();
 }, 5);
 return box;
}
return L.Class.extend({ checked: checked, text: text, literal: literal, stamp: stamp, pill: pill, fresh: fresh,
 summaryNode: summaryNode, evidenceNode: evidenceNode, snapshot: snapshot, compact: compact, expiryGuard: expiryGuard });
