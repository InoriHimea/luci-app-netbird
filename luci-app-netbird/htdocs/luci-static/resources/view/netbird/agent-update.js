// SPDX-License-Identifier: Apache-2.0
'use strict';
'require rpc';
'require ui';
'require dom';
'require poll';
'require view.netbird.dom-helpers as nb';

var getStatus = rpc.declare({ object: 'luci.netbird', method: 'get_agent_update_status', expect: {} });
var saveConfig = rpc.declare({ object: 'luci.netbird', method: 'set_agent_update_config',
	params: ['enabled', 'time', 'timezone', 'min_age_hours', 'probe_url', 'profile_dir'], expect: {} });
var checkUpdate = rpc.declare({ object: 'luci.netbird', method: 'check_agent_update', expect: {} });
var startUpdate = rpc.declare({ object: 'luci.netbird', method: 'start_agent_update', expect: {} });
var cancelUpdate = rpc.declare({ object: 'luci.netbird', method: 'cancel_agent_update', expect: {} });
var resetFailure = rpc.declare({ object: 'luci.netbird', method: 'reset_agent_update_failure', expect: {} });

function checked(res) {
	if (!res || !res.ok) throw new Error(res && res.message || _('Agent updater request failed.'));
	return res.data || {};
}
function stamp(epoch) { return epoch ? new Date(epoch * 1000).toLocaleString() : '—'; }

return L.Class.extend({
	load: function () { return getStatus(); },
	render: function (initial) {
		var state = {}, fields = {}, controls = [], actionBusy = false;
		var box = E('div', { 'class': 'cbi-section', 'id': 'nb-agent-auto-update' });
		var statusBox = E('div', { 'aria-live': 'polite' });
		var errorBox = E('div', { 'class': 'alert-message error', 'style': 'display:none' });
		var checkBox = E('p', { 'class': 'cbi-value-description' });
		var formBox = E('div');
		function showError(error) {
			errorBox.style.display = error ? '' : 'none';
			dom.content(errorBox, error ? String(error.message || error) : '');
		}
		function refreshControls() {
			var busy = !!(state.status && state.status.active);
			Object.keys(fields).forEach(function (key) { fields[key].disabled = actionBusy || busy; });
			controls.forEach(function (item) {
				item.node.disabled = actionBusy || (item.cancel ? !busy : busy);
			});
		}
		function display(data, fill) {
			state = data;
			var cfg = data.config || {}, s = data.status || {}, ready = data.readiness || {};
			if (fill) {
				fields.enabled.checked = !!cfg.enabled;
				['time', 'timezone', 'min_age_hours', 'probe_url', 'profile_dir'].forEach(function (key) {
					fields[key].value = cfg[key] == null ? '' : String(cfg[key]);
				});
			}
			function pair(label, value) {
				return E('div', { 'class': 'nb-pair' }, [ E('span', { 'class': 'nb-pair-label' }, label),
					E('span', { 'class': 'nb-pair-value' }, value || '—') ]);
			}
			dom.content(statusBox, [
				E('p', {}, [ nb.statusPill(s.paused ? 'error' : s.active ? 'unknown' : ready.ok ? 'connected' : 'disconnected',
					s.paused ? _('Automatic updates paused') : s.active ? _('Agent maintenance active') : cfg.enabled ? _('Enabled') : _('Disabled')) ]),
				!ready.ok && (!s.active || s.paused) ? E('p', { 'class': 'alert-message warning' }, ready.reason || _('Not ready for unattended updates.')) : null,
				E('div', { 'class': 'nb-conn-info' }, [ pair(_('Next scheduled check'), data.next_run),
					pair(_('Update phase'), s.phase), pair(_('Latest result'), s.result),
					pair(_('Version transition'), (s.from_version || '—') + ' → ' + (s.to_version || '—')),
					pair(_('Started'), stamp(s.started_at)), pair(_('Activation deadline'), stamp(s.deadline)),
					pair(_('Blocked version'), (s.blocked_versions || []).join(', ') || s.blocked_version) ]),
				s.message ? E('p', { 'class': 'cbi-value-description' }, s.message) : null,
				s.paused ? E('p', { 'class': 'cbi-value-description' }, _('Rollback is unresolved. Repair locally and run the recovery command before clearing the failure block.')) : null
			].filter(function (node) { return node != null; }));
			refreshControls();
		}
		function refresh() {
			return getStatus().then(checked).then(function (data) { display(data, false); showError(null); })
				.catch(function (error) { showError(error); });
		}
		function action(fn) {
			return function () {
				actionBusy = true; refreshControls(); showError(null);
				return Promise.resolve().then(fn).then(checked).then(function () { return refresh(); })
					.catch(showError).finally(function () { actionBusy = false; refreshControls(); });
			};
		}
		function button(text, fn, cancel) {
			var node = E('button', { 'class': 'btn cbi-button cbi-button-action', 'type': 'button', 'click': action(fn) }, text);
			controls.push({ node: node, cancel: !!cancel });
			return node;
		}
		function field(key, label, value, description, type) {
			var input = E('input', { 'class': type === 'checkbox' ? '' : 'cbi-input-text', 'type': type || 'text', 'value': value,
				'id': 'nb-agent-auto-' + key });
			if (key === 'time') { input.min = '03:00'; input.max = '04:59'; input.step = '60'; }
			if (key === 'min_age_hours') { input.min = '48'; input.max = '720'; input.step = '1'; }
			fields[key] = input;
			formBox.appendChild(E('div', { 'class': 'cbi-value' }, [ E('label', { 'class': 'cbi-value-title', 'for': input.id }, label),
				E('div', { 'class': 'cbi-value-field' }, [ input,
					description ? E('div', { 'class': 'cbi-value-description' }, description) : null ]) ]));
		}
		field('enabled', _('Enable scheduled agent updates'), '', _('Disabled by default. Updates the NetBird agent only, never the LuCI package.'), 'checkbox');
		field('time', _('Nightly check time'), '03:30', _('Only 03:00–05:00 in the selected timezone. Missed checks are not caught up during daytime.'), 'time');
		field('timezone', _('Schedule timezone'), 'UTC-8', _('POSIX UTC-8 means Beijing UTC+08:00. Use system for the device timezone. The system timezone is never changed.'));
		field('min_age_hours', _('Minimum release age (hours)'), 48, _('Only official stable releases at least 48 hours old are eligible.'), 'number');
		field('probe_url', _('Mesh service health URL'), '', _('Required HTTP(S) service reachable over the NetBird interface; a public Internet check is not sufficient.'), 'url');
		field('profile_dir', _('Persistent identity directory'), '/var/lib/netbird', _('Must match the running daemon profile directory and resolve to persistent storage.'));
		var save = button(_('Save auto-update settings'), function () {
			return saveConfig(fields.enabled.checked, fields.time.value, fields.timezone.value,
				Number(fields.min_age_hours.value), fields.probe_url.value, fields.profile_dir.value)
				.then(function (res) { checked(res); ui.addNotification(null, E('p', {}, _('Schedule saved without reconnecting NetBird.')), 'info'); return res; });
		});
		var check = button(_('Check eligible stable release'), function () {
			return checkUpdate().then(function (res) {
				var d = checked(res);
				dom.content(checkBox, d.eligible ? _('Eligible stable release: v%s').format(d.version) : d.reason || _('No eligible release.'));
				return res;
			});
		});
		var start = button(_('Run safe update now'), function () {
			return new Promise(function (resolve) {
				ui.showModal(_('Run safe agent update'), [
					E('p', {}, _('This restarts the NetBird agent and briefly interrupts Mesh traffic. The same stable-release, backup, health and rollback checks apply.')),
					E('p', { 'class': 'right' }, [
						E('button', { 'class': 'btn', 'click': function () { ui.hideModal(); resolve({ ok: true }); } }, _('Cancel')),
						' ', E('button', { 'class': 'btn cbi-button-positive', 'click': function () { ui.hideModal(); resolve(startUpdate()); } }, _('Start update'))
					])
				]);
			});
		});
		var cancel = button(_('Cancel and restore if needed'), function () { return cancelUpdate(); }, true);
		var reset = button(_('Clear failed-version block'), function () { return resetFailure(); });
		box.appendChild(E('h3', {}, _('Agent automatic updates')));
		box.appendChild(E('p', { 'class': 'cbi-section-descr' }, _('Persistent rollback is mandatory. The new agent must reconnect within 120 seconds and remain healthy for five minutes before commit.')));
		box.appendChild(errorBox); box.appendChild(statusBox); box.appendChild(formBox);
		box.appendChild(E('div', { 'class': 'cbi-section-actions' }, [ save, ' ', check, ' ', start, ' ', cancel, ' ', reset ]));
		box.appendChild(checkBox);
		try { display(checked(initial), true); } catch (error) { showError(error); refreshControls(); }
		var attached = false;
		var tick = function () {
			if (!box.isConnected) { if (attached) poll.remove(tick); return Promise.resolve(); }
			attached = true;
			return refresh();
		};
		poll.add(tick, 5);
		return box;
	}
});
