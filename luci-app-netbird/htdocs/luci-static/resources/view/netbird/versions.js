// SPDX-License-Identifier: Apache-2.0
'use strict';
'require view';
'require rpc';
'require ui';
'require dom';
'require view.netbird.dom-helpers as nb';

// 版本管理 Tab —— 三来源(NetBird-Release / NetBird-OpenWRT / 自定义下载链接)。
// 后端:get_binary_info(check_remote) / update_binary(url) / set_binary_source(source,version) / delete_custom_binary(version)。
//   - 进页只显本地信息(不联网);远端版本由「检测更新」按钮显式拉(避限流)。
//   - Release:检测更新后若有新版,「立即更新」按钮紧挨「检测更新」。
//   - OpenWRT:切换键非 active 即可点;无副本时后端非破坏性 opkg download 自动获取(免删 init.d)。
//   - 自定义:仅此选项显 URL 框 + 下载;下载按真二进制版本号存多版本,可切换/删除。架构由后端 ELF 头校验。
//   - 选中 active 来源不显示「此来源已生效」(隐藏切换键)。
//   - 纯操作按钮,无 Save&Apply / form.Map;binary_source 由 set_binary_source rpc 直写 UCI。
// 渲染全程 E()/dom-helpers(XSS 安全基线)。

var callBinaryInfo   = rpc.declare({ object: 'luci.netbird', method: 'get_binary_info',     params: ['check_remote'],      expect: {} });
var callUpdateBinary = rpc.declare({ object: 'luci.netbird', method: 'update_binary',        params: ['url', 'checksum'],   expect: {} });
var callSetSource    = rpc.declare({ object: 'luci.netbird', method: 'set_binary_source',    params: ['source', 'version'], expect: {} });
var callDeleteCustom = rpc.declare({ object: 'luci.netbird', method: 'delete_custom_binary', params: ['version'],           expect: {} });

function fmtVer(v) { return (v && v.length) ? ('v' + v) : null; }

function srcLabel(src) {
	if (src === 'release') return 'NetBird-Release';
	if (src === 'opkg')    return 'NetBird-OpenWrt';
	if (src === 'custom')  return _('Custom download');
	return src || '';
}

return view.extend({
	// 纯操作按钮页:去掉标准 Save&Apply 页脚(各动作即时按钮 + 各自确认/反馈)。
	handleSaveApply: null,
	handleSave:      null,
	handleReset:     null,

	load: function () {
		// 进页只拉本地信息(不联网);远端由「检测更新」按钮触发。
		return L.resolveDefault(callBinaryInfo(false), { ok: false });
	},

	render: function (res) {
		var self = this;
		self._bin = (res && res.ok && res.data) ? res.data : {};
		self._sel = self._bin.active_source || 'release';   // 默认显示当前 active 来源
		self._relLatest = null;                             // checkUpdate(release) 结果缓存

		var container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('NetBird') + ' — ' + _('Versions')),
			E('div', { 'class': 'cbi-map-descr' },
				_('The opkg package is the fallback baseline; the latest official build has more complete features.'))
		]);

		// ── 当前状态块 ───────────────────────────────────────────────────────
		self._statusBox = E('div', {});
		container.appendChild(self._statusBox);

		// ── 来源下拉(默认选中 active)─────────────────────────────────────────
		var mkOpt = function (v, label) {
			var attrs = { 'value': v };
			if (v === self._sel) attrs.selected = 'selected';
			return E('option', attrs, label);
		};
		var sel = E('select', {
			'class': 'cbi-input-select',
			'change': ui.createHandlerFn(self, 'onSelect')
		}, [
			mkOpt('release', 'NetBird-Release'),
			mkOpt('opkg', 'NetBird-OpenWrt'),
			mkOpt('custom', _('Custom download'))
		]);
		self._detailBox = E('div', {});

		container.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Binary source')),
			E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Select source')),
				E('div', { 'class': 'cbi-value-field' }, [ sel ])
			]),
			self._detailBox
		]));

		self.renderStatus();
		self.renderDetail();

		return container;
	},

	renderStatus: function () {
		var d = this._bin || {};
		var node = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Current')),
			E('div', { 'class': 'nb-conn-info' }, [
				E('div', { 'class': 'nb-pair' }, [
					E('span', { 'class': 'nb-pair-label' }, _('Active source')),
					E('span', { 'class': 'nb-pair-value' }, [
						nb.statusPill('connected', srcLabel(d.active_source || 'release'))
					])
				]),
				nb.pair(_('Running version'), fmtVer(d.running_version) || '-'),
				E('div', { 'class': 'nb-pair' }, [
					E('span', { 'class': 'nb-pair-label' }, _('luci-app-netbird')),
					E('span', { 'class': 'nb-pair-value' }, [
						fmtVer(d.luci_app_version) || '-',
						' ',
						E('a', { 'href': 'https://github.com/dont-touchme/luci-app-netbird', 'target': '_blank', 'rel': 'noopener noreferrer' }, 'GitHub')
					])
				]),
				nb.pair(_('Architecture'), d.arch ? (d.arch + (d.uname_m ? (' (' + d.uname_m + ')') : '')) : '-')
			])
		]);
		dom.content(this._statusBox, node);
	},

	onSelect: function (ev) {
		this._sel = ev.target.value;
		this._relLatest = null;
		this.renderDetail();
	},

	// 切换按钮(active 来源返 null,不显示「此来源已生效」);非 active 显示「切换到此来源」(就绪才可点)。
	// 与其它操作按钮同进 cbi-section-actions,保持同一左对齐轴(布局修复)。
	switchButton: function (source, available) {
		var self = this, active = (self._bin || {}).active_source || 'release';
		if (source === active)
			return null;
		var btn = E('button', {
			'class': 'btn cbi-button cbi-button-positive',
			'click': ui.createHandlerFn(self, 'switchSource', source)
		}, _('Switch to this source'));
		if (!available)
			btn.disabled = true;
		return btn;
	},

	// 按钮间插空格(同一 cbi-section-actions 内多按钮)。
	_spaced: function (arr) {
		var out = [];
		for (var i = 0; i < arr.length; i++) {
			if (i) out.push(' ');
			out.push(arr[i]);
		}
		return out;
	},

	// LuCI rpc.js 只读取全局 L.env.rpctimeout,没有 per-call timeout。下载/切换二进制可能
	// 超过默认 20s,临时拉长,避免前端先报超时而后端稍后成功落盘。
	_withRpcTimeout: function (seconds, fn) {
		var had = Object.prototype.hasOwnProperty.call(L.env, 'rpctimeout');
		var old = L.env.rpctimeout;
		L.env.rpctimeout = Math.max(Number(old) || 20, seconds);

		return fn().then(function (res) {
			if (had) L.env.rpctimeout = old;
			else delete L.env.rpctimeout;
			return res;
		}, function (err) {
			if (had) L.env.rpctimeout = old;
			else delete L.env.rpctimeout;
			throw err;
		});
	},

	renderDetail: function () {
		var self = this, d = self._bin || {}, sel = self._sel;
		var rows = [];

		if (sel === 'release') {
			var rel = d.release || {};
			rows.push(E('p', { 'class': 'cbi-section-descr' }, _('This is the official NetBird Release build.')));
			rows.push(nb.pair(_('Version'), rel.installed ? (fmtVer(rel.version) || '-') : _('Not installed')));
			rows.push(nb.pair(_('Path'), rel.path || '/usr/share/netbird/bin/netbird-release'));
			self._relCheck = E('div', { 'style': 'margin:.5em 0' });
			rows.push(self._relCheck);
			// 所有操作按钮同进一个 cbi-section-actions(左对齐):检测更新 +(有新版才)立即更新 +(非 active 才)切换。
			var acts = [
				E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(self, 'checkUpdate') }, _('Check for updates'))
			];
			if (self._relLatest && self._relLatest.update_available && self._relLatest.latest)
				acts.push(E('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': ui.createHandlerFn(self, 'updateLatest') }, _('Update now (v%s)').format(self._relLatest.latest)));
			var sbR = self.switchButton('release', !!rel.installed);
			if (sbR) acts.push(sbR);
			rows.push(E('div', { 'class': 'cbi-section-actions' }, self._spaced(acts)));
		}
		else if (sel === 'opkg') {
			var op = d.opkg || {};
			rows.push(E('p', { 'class': 'cbi-section-descr' }, _('This is the OpenWrt package-repository build.')));
			rows.push(nb.pair(_('Version'), op.version ? (fmtVer(op.version) || '-') : _('Not installed / not in opkg database')));
			rows.push(nb.pair(_('Path'), op.path || '/usr/bin/netbird'));
			// 提示:无副本但 feed 可用 → 切换时自动获取;feed 也无 → 红字
			if (!op.copy_preserved && op.binary_available)
				rows.push(E('p', { 'class': 'cbi-section-descr' },
					_('No local opkg binary copy is kept; switching will fetch it from the opkg feed automatically (opkg download).')));
			else if (!op.binary_available)
				rows.push(E('p', { 'class': 'cbi-section-descr', 'style': 'color:#a00' },
					_('The opkg feed does not provide netbird on this device, so switching is unavailable. Check your package sources.')));
			self._opkgCheck = E('div', { 'style': 'margin:.5em 0' });
			rows.push(self._opkgCheck);
			var acts2 = [
				E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(self, 'checkUpdate') }, _('Check for updates'))
			];
			var sbO = self.switchButton('opkg', !!op.binary_available);
			if (sbO) acts2.push(sbO);
			rows.push(E('div', { 'class': 'cbi-section-actions' }, self._spaced(acts2)));
		}
		else {
			// 自定义下载链接:仅此选项显 URL 框 + 下载 + 已下载版本列表
			rows.push(E('p', { 'class': 'cbi-section-descr' }, _('Download the NetBird client from a custom URL, kept by version so you can roll back anytime.')));
			// 保留已输入的 URL 跨重渲染(URL 不持久化到 UCI 是有意设计,但同一会话内重渲染不该清空)。
			var prevUrl = (self._urlInput && self._urlInput.value) ? String(self._urlInput.value) : (d.release_url || '');
			self._urlInput = E('input', {
				'type': 'text', 'class': 'cbi-input-text', 'style': 'width:32em;max-width:90%',
				'placeholder': 'https://…/netbird_<ver>_linux_' + (d.arch || 'amd64') + '.tar.gz',
				'value': prevUrl
			});
			rows.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Custom download URL')),
				E('div', { 'class': 'cbi-value-field' }, [
					self._urlInput,
					E('div', { 'class': 'cbi-value-description' },
						_('A NetBird tarball or a direct binary URL; after download it is checked against this CPU architecture.'))
				])
			]));
			// 可选校验和:填了就在执行前硬校验下载物(防 http:// 镜像被替换)。算法按长度自动判
			// (md5/sha1/sha256/sha512)。跨重渲染保留输入。
			var prevSha = (self._shaInput && self._shaInput.value) ? String(self._shaInput.value) : '';
			self._shaInput = E('input', {
				'type': 'text', 'class': 'cbi-input-text', 'style': 'width:32em;max-width:90%',
				'placeholder': _('optional — md5 / sha1 / sha256 / sha512 hex'),
				'value': prevSha
			});
			rows.push(E('div', { 'class': 'cbi-value' }, [
				E('label', { 'class': 'cbi-value-title' }, _('Checksum (optional)')),
				E('div', { 'class': 'cbi-value-field' }, [
					self._shaInput,
					E('div', { 'class': 'cbi-value-description' },
						_('If set, the download must match this checksum or it is rejected. Use sha256 or stronger for tamper protection; md5/sha1 only guard against corruption.'))
				])
			]));
			rows.push(E('div', { 'class': 'cbi-section-actions' }, [
				E('button', { 'class': 'btn cbi-button cbi-button-action', 'click': ui.createHandlerFn(self, 'download') }, _('Download'))
			]));

			var cust = d.custom || {};
			var vers = cust.versions || [];
			rows.push(E('h4', { 'style': 'margin-top:1em' }, _('Downloaded versions')));
			if (!vers.length) {
				rows.push(E('p', { 'class': 'cbi-section-descr' }, _('No custom versions downloaded yet. Enter a URL above and click Download.')));
			} else {
				var list = [];
				for (var i = 0; i < vers.length; i++) {
					var v = vers[i];
					var acts;
					if (v.active) {
						acts = [ nb.statusPill('connected', _('In use')) ];
					} else {
						acts = [
							E('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': ui.createHandlerFn(self, 'switchCustom', v.version) }, _('Switch to this version')),
							' ',
							E('button', { 'class': 'btn cbi-button cbi-button-negative', 'click': ui.createHandlerFn(self, 'deleteCustom', v.version) }, _('Delete'))
						];
					}
					list.push(E('div', { 'class': 'cbi-value' }, [
						E('label', { 'class': 'cbi-value-title' }, fmtVer(v.version) || v.version),
						E('div', { 'class': 'cbi-value-field' }, acts)
					]));
				}
				rows.push(E('div', {}, list));
			}
		}

		dom.content(this._detailBox, E('div', {}, rows));
	},

	// 检测更新:get_binary_info(check_remote=true) → 刷新本地态 + 显示远端结果。
	checkUpdate: function () {
		var self = this;
		var which = self._sel;
		var target = (which === 'release') ? self._relCheck : self._opkgCheck;
		if (target) dom.content(target, E('em', { 'style': 'color:#888' }, _('Checking…')));
		return L.resolveDefault(callBinaryInfo(true), { ok: false }).then(function (res) {
			if (!(res && res.ok && res.data)) {
				ui.addNotification(null, E('p', {}, _('Check for updates failed.')), 'error');
				return;
			}
			self._bin = res.data;
			var d = res.data;
			if (which === 'release')
				self._relLatest = { latest: d.latest_version, update_available: d.update_available };
			self.renderStatus();
			self.renderDetail();   // 重建 detail(release 详情会据 _relLatest 显示「立即更新」)
			if (which === 'release') {
				var msg;
				if (!d.latest_version)
					msg = E('p', { 'style': 'color:#888' }, _('Could not reach GitHub to check the latest version.'));
				else if (d.update_available)
					msg = E('span', { 'style': 'color:#080' }, _('Latest official: v%s').format(d.latest_version));
				else
					msg = E('p', { 'style': 'color:#080' }, _('Already on the latest official version (v%s).').format(d.latest_version));
				if (self._relCheck) dom.content(self._relCheck, msg);
			} else {
				// 升级命令按系统包管理器分流(apk=OWRT25+ / opkg=24.10-);apk 机上「opkg upgrade」
				// 是不存在的命令,故用 d.pkg_mgr(后端 binary_info 暴露)给对应系统的命令。
				var upgradeCmd = (d.pkg_mgr === 'apk') ? 'apk upgrade netbird' : 'opkg upgrade netbird';
				var m2 = d.opkg_upgradable
					? E('p', { 'style': 'color:#080' }, _('Package upgrade available: v%s (run "%s").').format(d.opkg_upgradable, upgradeCmd))
					: E('p', { 'style': 'color:#888' }, _('No package upgrade found in the cached package lists.'));
				if (self._opkgCheck) dom.content(self._opkgCheck, m2);
			}
		});
	},

	// 立即更新:从 GitHub 下载最新 release 写 netbird-release(空 url)。
	updateLatest: function () { return this._runUpdate(''); },

	// 自定义下载:读 URL + 可选 SHA-256 实时值;后端下载后 ELF 头硬校验,填了 SHA-256 则额外硬校验。
	download: function () {
		var self = this;
		var url = (self._urlInput && self._urlInput.value) ? String(self._urlInput.value).trim() : '';
		var sha = (self._shaInput && self._shaInput.value) ? String(self._shaInput.value).trim().toLowerCase() : '';
		if (!url) {
			ui.addNotification(null, E('p', {}, _('Enter a custom download URL first.')), 'warning');
			return;
		}
		if (sha && !/^([0-9a-f]{32}|[0-9a-f]{40}|[0-9a-f]{64}|[0-9a-f]{128})$/.test(sha)) {
			ui.addNotification(null, E('p', {}, _('Enter a valid checksum: md5 (32), sha1 (40), sha256 (64) or sha512 (128) hex characters.')), 'warning');
			return;
		}
		// http:// 且未提供校验和:下载物会以 root 执行,镜像/中间人可替换 → 二次确认。
		if (/^http:\/\//i.test(url) && !sha) {
			ui.showModal(_('Insecure download'), [
				E('p', {}, _('This is a plain http:// URL with no checksum. The downloaded file is executed as root, so a malicious mirror or a man-in-the-middle could run arbitrary code. Prefer https://, or paste a checksum above.')),
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
					E('button', { 'class': 'btn cbi-button cbi-button-negative important', 'click': ui.createHandlerFn(self, '_runUpdateConfirmed', url, sha) }, _('Download anyway'))
				])
			]);
			return;
		}
		return self._runUpdate(url, sha);
	},

	_runUpdateConfirmed: function (url, sha) { ui.hideModal(); return this._runUpdate(url, sha); },

	_runUpdate: function (url, sha) {
		var self = this;
		ui.showModal(_('Downloading NetBird binary'), [
			E('p', { 'class': 'spinning' }, _('Downloading, verifying (checksum + ELF architecture) and installing…'))
		]);
		return L.resolveDefault(self._withRpcTimeout(360, function () {
			return callUpdateBinary(url || '', sha || '');
		}), { ok: false }).then(function (res) {
			ui.hideModal();
			if (res && res.ok && res.data) {
				ui.addNotification(null, E('p', {}, _('Binary installed: v%s.').format(res.data.to || '?')), 'info');
				return self.refresh();
			}
			// 校验值不匹配：用稳定 code 给固定本地化提示（后端动态 message 含哈希、不进 PO，
			// zh 界面会回落英文 → 按 code 映射，K1 模式）；哈希明细附括号内便于核对。
			if (res && res.code === 'checksum_mismatch') {
				ui.addNotification(null, E('p', {},
					_('Checksum verification failed; the download was rejected.') +
					(res.message ? ' (' + res.message + ')' : '')), 'error');
				return;
			}
			// 空间不足：稳定 code → 固定本地化可操作提示（后端 message 仅放诊断明细，附括号内）。
			if (res && res.code === 'insufficient_space') {
				ui.addNotification(null, E('p', {},
					_('Not enough storage space. Delete unused downloaded versions and try again.') +
					(res.message ? ' (' + res.message + ')' : '')), 'error');
				return;
			}
			var msg = (res && res.message) ? _(res.message) : ((res && res.code) || _('Unknown error'));
			ui.addNotification(null, E('p', {}, _('Download/install failed: %s').format(msg)), 'error');
		});
	},

	switchSource: function (source) { return this._confirmSwitch(source, ''); },
	switchCustom: function (version) { return this._confirmSwitch('custom', version); },

	_confirmSwitch: function (source, version) {
		var self = this;
		var label = (source === 'custom') ? (srcLabel('custom') + ' v' + version) : srcLabel(source);
		var extra = (source === 'opkg')
			? E('p', { 'class': 'cbi-section-descr' }, _('If no local copy is kept, it will be fetched from the opkg feed first.'))
			: E('span', {});
		ui.showModal(_('Switch binary source'), [
			E('p', {}, _('Switch the active NetBird binary to %s? The NetBird service will restart briefly.').format(label)),
			extra,
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
				E('button', { 'class': 'btn cbi-button cbi-button-positive', 'click': function () { self._doSwitch(source, version); } }, _('Switch source'))
			])
		]);
	},

	_doSwitch: function (source, version) {
		var self = this;
		ui.hideModal();
		ui.showModal(_('Switching binary source'), [
			E('p', { 'class': 'spinning' }, _('Switching and restarting NetBird…'))
		]);
		return L.resolveDefault(self._withRpcTimeout(180, function () {
			return callSetSource(source, version || '');
		}), { ok: false }).then(function (res) {
			ui.hideModal();
			if (res && res.ok)
				ui.addNotification(null, E('p', {}, _('Active source is now %s (running v%s).').format(srcLabel(source), (res.data && res.data.running_version) || '?')), 'info');
			else if (res && res.code === 'insufficient_space')
				ui.addNotification(null, E('p', {}, _('Not enough storage space. Delete unused downloaded versions and try again.') + (res.message ? ' (' + res.message + ')' : '')), 'error');
			else
				ui.addNotification(null, E('p', {}, (res && res.message) ? _(res.message) : _('Switch failed.')), 'error');
			return self.refresh();
		});
	},

	deleteCustom: function (version) {
		var self = this;
		ui.showModal(_('Delete version'), [
			E('p', {}, _('Delete downloaded custom version v%s? This only removes the stored binary file.').format(version)),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
				E('button', { 'class': 'btn cbi-button cbi-button-negative important', 'click': function () { self._doDelete(version); } }, _('Delete'))
			])
		]);
	},

	_doDelete: function (version) {
		var self = this;
		ui.hideModal();
		return L.resolveDefault(callDeleteCustom(version), { ok: false }).then(function (res) {
			if (res && res.ok)
				ui.addNotification(null, E('p', {}, _('Deleted version v%s.').format(version)), 'info');
			else
				ui.addNotification(null, E('p', {}, (res && res.message) ? _(res.message) : _('Delete failed.')), 'error');
			return self.refresh();
		});
	},

	// 操作后刷新本地态(不联网);保持当前下拉选择。
	refresh: function () {
		var self = this;
		return L.resolveDefault(callBinaryInfo(false), { ok: false }).then(function (res) {
			self._bin = (res && res.ok && res.data) ? res.data : {};
			// 清陈旧「立即更新」缓存:更新/切换后版本已变,须重新「检测更新」才再显示(review MEDIUM)。
			self._relLatest = null;
			self.renderStatus();
			self.renderDetail();
		});
	}
});
