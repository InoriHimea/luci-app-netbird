// SPDX-License-Identifier: Apache-2.0
// Run with an authenticated Puppeteer page on an ISOLATED OpenWrt LuCI instance.
// `baseline` contains actual get_summary/get_checks/get_events data envelopes.
// RPC cache responses below are deliberately synthetic, not real LAN evidence.
export async function runHealthUiRegression(page, baseline) {
 const clone = value => JSON.parse(JSON.stringify(value));
 const ensure = (condition, message) => { if (!condition) throw new Error(message); };
 const names = { get_summary: 'summary', get_checks: 'checks', get_events: 'events' };
 let active, received = 0, held = [], paged = false;
 const results = [];
 function fixture(name) {
  const value = clone(baseline), summary = value.summary, run = summary.run;
  summary.fresh = true; summary.reason = null; summary.max_age = name === 'expiry' ? 8 : 120;
  run.run_id = 'synthetic-ui-' + name;
  run.flags = { stale: false, checking: false, maintenance: false };
  run.overall = 'healthy';
  run.coverage = Object.fromEntries(['local_structure', 'forward_lookup', 'router_probe', 'lan_probe', 'external_observer'].map(key => [key, 'healthy']));
  value.checks.items.forEach(item => {
   Object.assign(item, { status: 'PASS', fresh: true, executed: true, code: 'SYNTHETIC_PASS' });
   item.expected = { from: '192.0.2.10', iif: 'br-lan', mark: 12100, table: 9911, priority: 77 };
   item.observed = { description: '<img src=x onerror="alert(1)">', untrusted_url: 'javascript:alert(1)' };
  });
  function fail(suffix, status, code) {
   const item = value.checks.items.find(item => item.id.endsWith(suffix));
   ensure(item, 'Baseline lacks required category ' + suffix);
   item.status = status; item.code = code;
  }
  if (name === 'A01') {
   fail(':rules', 'FAIL', 'RULE_MISSING'); fail(':forward', 'FAIL', 'FORWARD_LOOKUP_MISMATCH');
   run.overall = run.coverage.local_structure = run.coverage.forward_lookup = 'unhealthy';
  } else if (name === 'A02') {
   fail(':rules', 'FAIL', 'NATIVE_RULE_DRIFT'); run.overall = run.coverage.local_structure = 'degraded';
  } else if (name === 'A06') {
   fail(':peer', 'FAIL', 'BACKUP_TAKEOVER'); run.overall = run.coverage.local_structure = 'degraded';
  } else if (name === 'A09') {
   fail(':lan', 'FAIL', 'LAN_PROBE_FAILED'); run.overall = run.coverage.lan_probe = 'unhealthy';
  } else if (name === 'A10') {
   fail(':lan', 'UNKNOWN', 'NOT_CONFIGURED'); run.overall = run.coverage.lan_probe = 'unknown';
  }
  const count = value.checks.items.length;
  Object.assign(run, { expected_count: count, executed_count: count,
   pass_count: value.checks.items.filter(item => item.status === 'PASS').length,
   fail_count: value.checks.items.filter(item => item.status === 'FAIL').length,
   unknown_count: value.checks.items.filter(item => item.status === 'UNKNOWN').length,
   not_applicable_count: 0, disabled_count: 0 });
  Object.assign(value.checks, { total: count, offset: 0, has_more: false, next_cursor: null });
  Object.assign(value.checks.metadata, { run_id: run.run_id, fresh: true, max_age: summary.max_age });
  Object.assign(value.events, { items: [], total: 0, offset: 0, has_more: false, next_cursor: null });
  summary.check_count = count;
  if (name === 'metadata-race') {
   value.checks.metadata.current_config_revision++;
   value.checks.metadata.fresh = false;
  }
  if (name === 'incomplete') value.checks.total++;
  if (name === 'last-page' || name === 'page-race') {
   value.checks.items = Array.from({ length: 101 }, (_, index) => ({ ...clone(value.checks.items[0]), id: 'check-' + index }));
   Object.assign(value.checks.items[100], { status: 'FAIL', code: 'LAST_PAGE_FAILURE' });
   Object.assign(run, { expected_count: 101, executed_count: 101, pass_count: 100, fail_count: 1, unknown_count: 0, overall: 'unhealthy' });
   run.coverage.local_structure = 'unhealthy'; value.checks.total = summary.check_count = 101;
  }
  return value;
 }
 const intercept = async request => {
  try {
   let payload;
   try { payload = JSON.parse(request.postData() || 'null'); } catch { /* non-RPC resource */ }
   const batch = Array.isArray(payload) ? payload : [payload];
   const matches = call => call?.params?.[1] === 'luci.netbird.health' && names[call.params[2]];
   const reads = batch.filter(matches);
   if (!reads.length) return request.continue();
   if (active.name === 'expiry' && received >= 3) { held.push(request); return; }
   if (!received) {
    active.data.summary.sampled_at = Math.floor(Date.now() / 1000);
    active.data.checks.metadata.sampled_at = active.data.summary.sampled_at;
   }
   let original = [];
   if (reads.length !== batch.length) {
    // Forward only the existing authenticated fixture request. Never log headers/body.
    const response = await fetch(request.url(), { method: request.method(), headers: request.headers(), body: request.postData() });
    const body = await response.json(); original = Array.isArray(body) ? body : [body];
   }
   const output = batch.map(call => {
    if (!matches(call)) return original.find(response => response.id === call.id);
    received++;
    let data = clone(active.data[names[call.params[2]]]);
    if (call.params[2] === 'get_checks' && (active.name === 'last-page' || active.name === 'page-race')) {
     const continuation = !!call.params[3]?.cursor;
     data.offset = continuation ? 100 : 0; data.items = data.items.slice(data.offset, data.offset + 100);
     data.has_more = !continuation; data.next_cursor = continuation ? null : 'synthetic-next-page';
     if (continuation) { paged = true; if (active.name === 'page-race') data.metadata.run_id += '-changed'; }
    }
    return { jsonrpc: '2.0', id: call.id, result: [0, { ok: true, data }] };
   });
   await request.respond({ status: 200, contentType: 'application/json', body: JSON.stringify(Array.isArray(payload) ? output : output[0]) });
  } catch {
   await request.abort().catch(() => {});
  }
 };
 await page.setCacheEnabled(false);
 await page.setRequestInterception(true);
 page.on('request', intercept);
 try {
  for (const name of ['A01', 'A02', 'A06', 'A09', 'A10', 'A19', 'last-page', 'metadata-race', 'incomplete', 'page-race', 'expiry']) {
   active = { name, data: fixture(name) }; received = 0; paged = false;
   await page.reload({ waitUntil: 'domcontentloaded' });
   const rejected = ['metadata-race', 'incomplete', 'page-race'].includes(name);
   await page.waitForFunction((id, failure) => {
    const text = document.querySelector('.nb-health-summary')?.textContent || '';
    return failure ? /different snapshots|Incomplete health evidence|changed during pagination/.test(text) : text.includes(id);
   }, { timeout: 60000 }, active.data.summary.run.run_id, rejected);
   if (name === 'expiry') await page.waitForFunction(sample => Date.now() / 1000 > sample + 9, { timeout: 15000 }, active.data.summary.sampled_at);
   const actual = await page.evaluate(() => ({
    states: Array.from(document.querySelectorAll('.nb-health-summary [data-health-state]')).map(node => node.getAttribute('data-health-state')),
    checkStates: Array.from(document.querySelectorAll('.nb-health-evidence [data-health-state]')).map(node => node.getAttribute('data-health-state')),
    codes: Array.from(document.querySelectorAll('.nb-health-evidence summary')).map(node => node.textContent),
    unsafe: !!document.querySelector('#nb-health-page img[onerror], #nb-health-page a[href^="javascript:"]'),
    literalMarkup: Array.from(document.querySelectorAll('.nb-health-evidence pre')).some(node => {
     try { return JSON.parse(node.textContent).description === '<img src=x onerror="alert(1)">'; } catch { return false; }
    }),
    evidenceCount: document.querySelectorAll('.nb-health-evidence').length
   }));
   ensure(!actual.unsafe, name + ': evidence became executable markup');
   if (rejected || name === 'expiry') {
    ensure(actual.states.every(state => state === 'unknown' || state === 'UNKNOWN'), name + ': expired/incoherent evidence remained healthy');
    ensure(actual.checkStates.every(state => state === 'UNKNOWN'), name + ': individual evidence retained PASS');
   } else {
    const expected = active.data.summary.run;
    ensure(actual.states[0] === expected.overall, name + ': incorrect overall state');
    ensure(actual.evidenceCount === active.data.summary.check_count, name + ': denominator/page loss');
    ensure(actual.literalMarkup, name + ': literal evidence text was lost');
    ensure(actual.states[3] === expected.coverage.router_probe && actual.states[4] === expected.coverage.lan_probe, name + ': probe perspectives merged');
   }
   if (name === 'last-page') ensure(paged && actual.codes.some(code => code.includes('LAST_PAGE_FAILURE')), 'Last-page failure was hidden');
   if (name === 'expiry') ensure(held.length > 0, 'Expiry case did not stall an actual RPC');
   results.push({ scenario: name, result: 'PASS', states: actual.states, evidenceCount: actual.evidenceCount });
  }
  return results;
 } finally {
  for (const request of held) await request.abort().catch(() => {});
  page.off('request', intercept);
  await page.setRequestInterception(false);
 }
}
