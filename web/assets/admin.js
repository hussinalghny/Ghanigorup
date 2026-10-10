/* Ghani Group Rental — Admin panel */
(() => {
'use strict';

const BASE = document.querySelector('base')?.getAttribute('href') || '/';
const API = BASE + 'api/v1';
const root = document.getElementById('root');
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const h = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const cookie = n => { const m = document.cookie.match('(?:^|; )' + n + '=([^;]*)'); return m ? decodeURIComponent(m[1]) : ''; };
const num = n => Number(n || 0).toLocaleString('en');
const MONTHS = ['كانون2', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين1', 'تشرين2', 'كانون1'];
const fd = s => { if (!s) return '—'; const d = new Date(String(s).replace(' ', 'T')); return d.getDate() + ' ' + MONTHS[d.getMonth()]; };
const fdt = s => { if (!s) return '—'; const d = new Date(String(s).replace(' ', 'T')); return fd(s) + ' ' + String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); };
const STATUS = {
  pending: ['جديد — بانتظار المراجعة', 'warn'], quoted: ['أُرسل عرض السعر', 'ink'], confirmed: ['مؤكد', 'ok'],
  out: ['مُسلَّم للعميل', 'ok'], returned: ['مُرجَع — مكتمل', ''], cancelled: ['ملغي', 'red'],
};
const SHORT = { pending: 'جديد', quoted: 'عرض سعر', confirmed: 'مؤكد', out: 'مُسلَّم', returned: 'مُرجَع', cancelled: 'ملغي' };
const chip = s => `<span class="chip ${STATUS[s]?.[1] || ''}"><i></i>${SHORT[s] || h(s)}</span>`;

const IC = {
  dash: '<path d="M3 3h6v8H3zM11 3h6v4h-6zM11 9h6v8h-6zM3 13h6v4H3z"/>',
  orders: '<rect x="4" y="2.5" width="12" height="15" rx="2"/><path d="M7 7h6M7 10h6M7 13h3"/>',
  eq: '<rect x="2" y="6" width="11" height="9" rx="1.5"/><path d="m13 9 5-2.5v8L13 12"/>',
  cats: '<rect x="3" y="3" width="6" height="6" rx="1.5"/><rect x="11" y="3" width="6" height="6" rx="1.5"/><rect x="3" y="11" width="6" height="6" rx="1.5"/><rect x="11" y="11" width="6" height="6" rx="1.5"/>',
  kits: '<path d="M3 7h14v10H3zM7 7V4h6v3"/>',
  users: '<circle cx="8" cy="7" r="3"/><path d="M2.5 17c.8-3 3-4.5 5.5-4.5s4.7 1.5 5.5 4.5M14 4.5a3 3 0 0 1 0 5.5M15.5 12.8c1.2.6 2 1.8 2.3 3.7"/>',
  imp: '<path d="M10 3v10M6 9l4 4 4-4M3 15v2h14v-2"/>',
  set: '<circle cx="10" cy="10" r="2.5"/><path d="M10 2v2.5M10 15.5V18M2 10h2.5M15.5 10H18M4.3 4.3l1.8 1.8M13.9 13.9l1.8 1.8M4.3 15.7l1.8-1.8M13.9 6.1l1.8-1.8"/>',
  sys: '<rect x="3" y="3" width="14" height="5" rx="1.5"/><rect x="3" y="12" width="14" height="5" rx="1.5"/><path d="M6 5.5h.01M6 14.5h.01"/>',
  search: '<circle cx="9" cy="9" r="6"/><path d="m14 14 4 4"/>',
  menu: '<path d="M3 6h14M3 10h14M3 14h14"/>',
};
const svg = (k, s = 20) => `<svg width="${s}" height="${s}" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${IC[k]}</svg>`;

/* ---------- API ---------- */
async function api(path, { method = 'GET', body, query, form } = {}) {
  const url = new URL(API + path, location.href);
  if (query) Object.entries(query).forEach(([k, v]) => { if (v !== '' && v != null) url.searchParams.set(k, v); });
  const headers = { 'X-Client': 'web', Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (method !== 'GET') headers['X-CSRF-Token'] = cookie('gg_csrf');
  let res;
  try { res = await fetch(url, { method, headers, credentials: 'same-origin', body: form || (body !== undefined ? JSON.stringify(body) : undefined) }); }
  catch (e) { throw Object.assign(new Error('تعذر الاتصال بالسيرفر'), { status: 0 }); }
  const j = await res.json().catch(() => ({ ok: false, error: { message: 'استجابة غير متوقعة (' + res.status + ')' } }));
  if (!j.ok) {
    const err = Object.assign(new Error(j.error?.message || 'خطأ'), { status: res.status, code: j.error?.code, details: j.error?.details || {} });
    if (res.status === 401 && path !== '/auth/login') { S.user = null; renderLogin(); }
    throw err;
  }
  return j;
}

/* ---------- ui helpers ---------- */
let tT;
function toast(m, err = false) { const t = $('#toast'); t.textContent = m; t.classList.toggle('err', err); t.classList.add('on'); clearTimeout(tT); tT = setTimeout(() => t.classList.remove('on'), 2600); }
const fail = e => toast(e.message + (e.details && Object.keys(e.details).length && !e.details.shortages ? ' — ' + Object.entries(e.details).map(([k, v]) => k + ': ' + v).join('، ') : ''), true);
function drawer(title, body, foot = '') {
  const d = $('#drawer');
  d.innerHTML = `<div class="dh"><h2>${title}</h2><button class="x" id="dx" aria-label="إغلاق">×</button></div><div class="db">${body}</div>${foot ? `<div class="df">${foot}</div>` : ''}`;
  d.classList.add('on'); $('#scrim').classList.add('on');
  $('#dx').onclick = closeDrawer;
  return d;
}
function closeDrawer() { $('#drawer').classList.remove('on'); $('#scrim').classList.remove('on'); }
$('#scrim').onclick = closeDrawer;
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeDrawer(); });
function markErrors(form, details) {
  $$('.f', form).forEach(f => f.classList.remove('err'));
  Object.keys(details || {}).forEach(k => { const el = form.querySelector(`[name="${k}"]`); if (el) el.closest('.f')?.classList.add('err'); });
}
const val = form => {
  const o = {};
  $$('input,select,textarea', form).forEach(el => {
    if (!el.name || el.dataset.skip) return;
    o[el.name] = el.type === 'checkbox' ? el.checked : el.value;
  });
  return o;
};
let tip;
function tooltip(el, text) {
  if (!tip) { tip = document.createElement('div'); tip.className = 'tip'; document.body.appendChild(tip); }
  el.onmouseenter = el.onfocus = () => { tip.textContent = text; tip.classList.add('on'); const r = el.getBoundingClientRect(); tip.style.top = (r.top - 36) + 'px'; tip.style.left = Math.max(8, r.left + r.width / 2 - tip.offsetWidth / 2) + 'px'; };
  el.onmouseleave = el.onblur = () => tip.classList.remove('on');
}

/* ---------- state ---------- */
const S = { user: null, cats: [], page: 'dash' };

/* ---------- login ---------- */
function renderLogin(msg = '') {
  root.innerHTML = `<div class="login"><form class="box" id="lf">
    <div class="logo"><img src="assets/brand/mark.png" alt="" width="28" height="28">Ghani Group</div>
    <h1>لوحة التحكم</h1><p>${h(msg || 'سجّل الدخول بحساب المدير أو الموظف')}</p>
    <div class="fm"><div class="f"><label>البريد الإلكتروني</label><input name="email" type="email" dir="ltr" autocomplete="username" required></div>
    <div class="f"><label>كلمة المرور</label><input name="password" type="password" dir="ltr" autocomplete="current-password" required></div>
    <button class="btn block">دخول</button></div>
    <p style="margin:16px 0 0;text-align:center"><a href="./" class="muted" style="font-size:12.5px">← العودة للموقع</a></p></form></div>`;
  $('#lf').onsubmit = async e => {
    e.preventDefault();
    const b = $('#lf button'); b.disabled = true;
    try {
      const r = await api('/auth/login', { method: 'POST', body: val(e.target) });
      if (!['admin', 'staff'].includes(r.data.user.role)) { await api('/auth/logout', { method: 'POST' }); throw new Error('هذا الحساب ليس لديه صلاحية لوحة التحكم'); }
      S.user = r.data.user; shell();
    } catch (err) { b.disabled = false; toast(err.message, true); }
  };
}

/* ---------- shell ---------- */
const NAV = [
  ['dash', 'الرئيسية', 'dash'], ['orders', 'الطلبات', 'orders'], ['equipment', 'المعدات', 'eq'], ['categories', 'الأقسام', 'cats'],
  ['kits', 'الباقات', 'kits'], ['users', 'المستخدمون', 'users', 1], ['import', 'استيراد وتصدير', 'imp', 1], ['settings', 'الإعدادات', 'set', 1], ['system', 'النظام والسجل', 'sys', 1],
];
function shell() {
  const admin = S.user.role === 'admin';
  root.innerHTML = `<div class="shell"><nav class="side" id="side">
      <div class="logo"><img src="assets/brand/mark.png" alt="" width="28" height="28">Ghani Group</div>
      ${NAV.filter(n => admin || !n[3]).map(n => `<a href="admin#/${n[0]}" data-p="${n[0]}">${svg(n[2])}${n[1]}${n[0] === 'orders' ? '<span class="n" id="pendN" hidden></span>' : ''}</a>`).join('')}
      <div class="me"><b>${h(S.user.name)}</b>${S.user.role === 'admin' ? 'مدير' : 'موظف'} · <button id="out">خروج</button> · <a href="./" target="_blank">الموقع</a></div>
    </nav><main><div class="mtop"><div class="logo"><img src="assets/brand/mark.png" alt="" width="28" height="28">لوحة التحكم</div><button id="menu" aria-label="القائمة">${svg('menu')}</button></div><div id="page"></div></main></div>`;
  $('#out').onclick = async () => { try { await api('/auth/logout', { method: 'POST' }); } catch (e) { /* ignore */ } S.user = null; renderLogin('تم تسجيل الخروج'); };
  $('#menu').onclick = () => $('#side').classList.toggle('open');
  route();
}
const page = () => $('#page');
const head = (t, acts = '') => `<div class="head"><h1>${t}</h1><div class="acts">${acts}</div></div>`;

async function route() {
  if (!S.user) return;
  const [p, qs] = (location.hash.replace(/^#\/?/, '') || 'dash').split('?');
  S.page = p;
  $$('#side a').forEach(a => a.classList.toggle('on', a.dataset.p === p));
  $('#side')?.classList.remove('open');
  closeDrawer();
  page().innerHTML = '<div class="skel"></div>';
  const views = { dash: vDash, orders: vOrders, equipment: vEquipment, categories: vCategories, kits: vKits, users: vUsers, import: vImport, settings: vSettings, system: vSystem };
  try { await (views[p] || vDash)(new URLSearchParams(qs || '')); }
  catch (e) { if (e.status !== 401) page().innerHTML = `<div class="empty"><b>تعذر التحميل</b>${h(e.message)}</div>`; }
}
window.addEventListener('hashchange', route);

/* ---------- dashboard ---------- */
async function vDash() {
  const { data: d } = await api('/admin/stats');
  const st = d.orders_by_status || {};
  const pend = st.pending || 0;
  if ($('#pendN')) { $('#pendN').textContent = pend; $('#pendN').hidden = !pend; }
  const max = Math.max(1, ...d.orders_30d.map(x => x.orders));
  const step = max <= 4 ? 1 : Math.ceil(max / 4);
  const top = Math.ceil(max / step) * step;
  page().innerHTML = head('أهلاً، ' + h(S.user.name.split(' ')[0]), '<a class="btn" href="admin#/orders?status=pending">مراجعة الطلبات الجديدة</a>') + `
    <div class="kpis">
      <a class="kpi dark" href="admin#/orders?status=pending"><small>طلبات جديدة</small><b>${pend}</b><span>بانتظار المراجعة</span></a>
      <a class="kpi" href="admin#/orders?status=confirmed"><small>حجوزات مؤكدة</small><b>${st.confirmed || 0}</b><span>${st.quoted || 0} بانتظار رد العميل</span></a>
      <a class="kpi" href="admin#/orders?status=out"><small>معدات عند العملاء</small><b>${num(d.out_now)}</b><span>وحدة الآن</span></a>
      <a class="kpi" href="admin#/equipment"><small>الأسطول</small><b>${num(d.equipment_units)}</b><span>${d.equipment_items} صنف</span></a>
      <a class="kpi" href="admin#/users"><small>العملاء</small><b>${num(d.customers)}</b><span>حساب مسجّل</span></a>
    </div>
    <div class="grid3">
      <div class="card"><h3>الطلبات اليومية <small>آخر 30 يوم · ${num(d.orders_30d.reduce((a, b) => a + b.orders, 0))} طلب</small></h3>
        <div class="chart" id="chart" role="img" aria-label="عدد الطلبات اليومية خلال آخر 30 يوماً">
          ${[1, 2, 3, 4].map(i => (i * step <= top ? `<div class="grid-l" style="bottom:${22 + (i * step / top) * 178}px"><span>${i * step}</span></div>` : '')).join('')}
          ${d.orders_30d.map((x, i) => `<div class="b ${x.orders ? '' : 'zero'}" tabindex="0" data-i="${i}"><i style="height:${(x.orders / top) * 100}%"></i>${i % 5 === 0 || i === 29 ? `<em>${fd(x.date)}</em>` : ''}</div>`).join('')}
        </div>
        <details style="margin-top:14px"><summary class="muted" style="font-size:12px;cursor:pointer">عرض كجدول</summary>
          <div class="list" style="margin-top:8px">${d.orders_30d.filter(x => x.orders).map(x => `<div class="lr"><div class="t">${fd(x.date)}</div><b>${x.orders}</b></div>`).join('') || '<div class="muted">لا طلبات</div>'}</div></details>
      </div>
      <div class="card"><h3>الاستلامات القادمة <a class="muted" style="font-size:12px" href="admin#/orders">الكل</a></h3><div class="list">
        ${d.upcoming.length ? d.upcoming.map(o => `<a class="lr" href="admin#/orders?open=${o.id}"><div class="t"><b>${h(o.project || o.contact_name)}</b><small class="ltr">${h(o.ref)}</small> <small>· ${fd(o.start_date)} ← ${fd(o.end_date)}</small></div>${chip(o.status)}</a>`).join('') : '<div class="empty" style="padding:20px">لا توجد استلامات قادمة</div>'}
      </div></div>
    </div>
    <div class="grid2" style="margin-top:14px">
      <div class="card"><h3>الأكثر طلباً</h3><div class="list">${d.top_equipment.length ? d.top_equipment.map(t => `<div class="lr"><img src="${h(t.image || '')}" alt=""><div class="t"><b class="ltr" style="text-align:right">${h(t.name)}</b><small>${h(t.brand)} · ${t.orders} طلب</small></div><b>${num(t.units)}</b></div>`).join('') : '<div class="empty" style="padding:20px">لا بيانات بعد</div>'}</div></div>
      <div class="card"><h3>حالة الطلبات</h3><div class="list">${Object.keys(STATUS).map(s => `<a class="lr" href="admin#/orders?status=${s}"><div class="t">${STATUS[s][0]}</div><b>${st[s] || 0}</b></a>`).join('')}</div>
        <p class="muted" style="font-size:11.5px;margin-top:12px">كاش: ${h(d.system.cache)} · سيرفرات قراءة: ${d.system.replicas} · PHP ${h(d.system.php)} · v${h(d.system.version)}</p></div>
    </div>`;
  $$('#chart .b').forEach(b => { const x = d.orders_30d[+b.dataset.i]; tooltip(b, `${fd(x.date)} — ${x.orders} طلب`); });
}

/* ---------- orders ---------- */
async function vOrders(params) {
  const st = { status: params.get('status') || '', q: '', page: 1 };
  const stats = (await api('/admin/stats')).data.orders_by_status || {};
  page().innerHTML = head('الطلبات') + `<div class="filters">
      <div class="seg" id="sf"><button data-s="">الكل<i>${Object.values(stats).reduce((a, b) => a + b, 0)}</i></button>${Object.keys(STATUS).map(s => `<button data-s="${s}">${SHORT[s]}<i>${stats[s] || 0}</i></button>`).join('')}</div>
      <label class="search">${svg('search', 16)}<input id="oq" placeholder="رقم الطلب، الاسم، الهاتف، المشروع"></label></div>
    <div class="tbl"><table><thead><tr><th>الطلب</th><th>العميل</th><th>المشروع</th><th>المدة</th><th>القطع</th><th>الحالة</th><th>عرض السعر</th></tr></thead><tbody id="ob"></tbody></table><div class="pager" id="op"></div></div>`;
  const load = async () => {
    $$('#sf button').forEach(b => b.classList.toggle('on', b.dataset.s === st.status));
    const r = await api('/admin/orders', { query: { status: st.status, q: st.q, page: st.page } });
    $('#ob').innerHTML = r.data.length ? r.data.map(o => `<tr data-id="${o.id}"><td><b class="ltr">${h(o.ref)}</b><div class="sub">${fdt(o.created_at)}</div></td>
      <td><div class="nm">${h(o.contact_name)}</div><div class="sub ltr" style="text-align:right">${h(o.phone)}</div></td>
      <td>${h(o.project || '—')}<div class="sub">${h(o.location || '')}</div></td><td class="num">${fd(o.start_date)} ← ${fd(o.end_date)}<div class="sub">${o.days} يوم</div></td>
      <td class="num">${o.units}</td><td>${chip(o.status)}</td><td class="num">${o.quote_amount != null ? num(o.quote_amount) : '—'}</td></tr>`).join('')
      : '<tr><td colspan="7"><div class="empty"><b>لا توجد طلبات</b>غيّر الفلتر أو البحث</div></td></tr>';
    $$('#ob tr[data-id]').forEach(tr => tr.onclick = () => openOrder(+tr.dataset.id, load));
    $('#op').innerHTML = `<span>${r.meta.total} طلب</span><span>${r.meta.page > 1 ? '<button class="btn lt sm" id="pv">السابق</button> ' : ''}صفحة ${r.meta.page} من ${Math.max(1, r.meta.pages)}${r.meta.page < r.meta.pages ? ' <button class="btn lt sm" id="nx">التالي</button>' : ''}</span>`;
    if ($('#pv')) $('#pv').onclick = () => { st.page--; load(); };
    if ($('#nx')) $('#nx').onclick = () => { st.page++; load(); };
  };
  $$('#sf button').forEach(b => b.onclick = () => { st.status = b.dataset.s; st.page = 1; history.replaceState(null, '', 'admin#/orders' + (st.status ? '?status=' + st.status : '')); load(); });
  let t; $('#oq').oninput = e => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value.trim(); st.page = 1; load(); }, 300); };
  await load();
  if (params.get('open')) openOrder(+params.get('open'), load);
}

async function openOrder(id, reload) {
  const { data: o } = await api('/admin/orders/' + id);
  let status = o.status;
  const wa = String(o.phone).replace(/\D/g, '').replace(/^0/, '964');
  const d = drawer(`طلب <span class="ltr">${h(o.ref)}</span>`, `
    <div class="statusbar" id="sb">${Object.keys(STATUS).map(s => `<button data-s="${s}" class="${s === o.status ? 'on' : ''}">${SHORT[s]}</button>`).join('')}</div>
    <p class="muted" style="font-size:12px;margin-top:8px">الحالية: ${STATUS[o.status][0]} · آخر تحديث ${fdt(o.updated_at)}</p>
    ${o.shortages.length ? `<div class="alert warn" style="margin-top:12px"><b>تعارض في التوفر</b><br>${o.shortages.map(s => `• ${h(s.name)}: مطلوب ${s.requested} — متاح ${s.available}`).join('<br>')}</div>` : (['pending', 'quoted'].includes(o.status) ? '<div class="alert ok" style="margin-top:12px">كل المعدات متوفرة في هذه الفترة ✓</div>' : '')}
    <div class="sect">العميل والمشروع</div>
    <div class="info"><div><small>الاسم</small><b>${h(o.contact_name)}</b></div><div><small>الهاتف</small><b class="ltr">${h(o.phone)}</b></div>
      <div><small>المشروع</small><b>${h(o.project || '—')}</b></div><div><small>الموقع</small><b>${h(o.location || '—')}</b></div>
      <div><small>المدة</small><b>${fd(o.start_date)} ← ${fd(o.end_date)} (${o.days} يوم)</b></div><div><small>إضافات</small><b>${[o.technician ? 'فني مرافق' : '', o.delivery ? 'توصيل' : ''].filter(Boolean).join(' + ') || 'لا يوجد'}</b></div></div>
    ${o.notes ? `<div class="sect">ملاحظات العميل</div><div class="card" style="padding:14px">${h(o.notes)}</div>` : ''}
    <div class="sect">المعدات (${o.items.reduce((a, b) => a + b.qty, 0)} قطعة)</div>
    <div class="card oitems" style="padding:6px 14px"><div class="list">${o.items.map(i => `<div class="lr"><img src="${h(i.image || '')}" alt=""><div class="t"><b class="ltr" style="text-align:right">${h(i.name)}</b><small>${h(i.brand)}</small></div><b>×${i.qty}</b></div>`).join('')}</div></div>
    <div class="sect">التسعير والملاحظات الداخلية</div>
    <form class="fm" id="of"><div class="row"><div class="f"><label>مبلغ عرض السعر</label><input name="quote_amount" inputmode="decimal" dir="ltr" value="${o.quote_amount ?? ''}"></div>
      <div class="f"><label>تعديل التواريخ</label><div style="display:flex;gap:6px"><input type="date" name="start_date" value="${o.start_date}"><input type="date" name="end_date" value="${o.end_date}"></div></div></div>
      <div class="f"><label>ملاحظات داخلية (لا تظهر للعميل)</label><textarea name="admin_notes" rows="3">${h(o.admin_notes || '')}</textarea></div></form>
    <p class="muted" style="font-size:11.5px;margin-top:10px">IP: <span class="ltr">${h(o.ip || '')}</span> · أُنشئ ${fdt(o.created_at)}${o.user_id ? ' · عميل مسجّل #' + o.user_id : ' · بدون حساب'}</p>`,
    `<button class="btn" id="save">حفظ</button><a class="btn lt" target="_blank" rel="noopener" href="https://wa.me/${h(wa)}?text=${encodeURIComponent('مرحباً ' + o.contact_name + '، بخصوص طلبك ' + o.ref + ' من Ghani Group')}">واتساب العميل</a>`);
  $$('#sb button', d).forEach(b => b.onclick = () => { status = b.dataset.s; $$('#sb button', d).forEach(x => x.classList.toggle('on', x === b)); });
  const save = async (force = false) => {
    const body = val($('#of')); body.status = status; if (force) body.force = true;
    try { await api('/admin/orders/' + id, { method: 'PATCH', body }); toast('تم حفظ الطلب'); closeDrawer(); reload && reload(); }
    catch (e) {
      if (e.code === 'shortage' && confirm('الكمية غير كافية لبعض المعدات:\n' + e.details.shortages.map(s => `${s.name}: مطلوب ${s.requested}، متاح ${s.available}`).join('\n') + '\n\nتأكيد رغم ذلك؟')) return save(true);
      if (e.code !== 'shortage') fail(e);
    }
  };
  $('#save').onclick = () => save();
}

/* ---------- equipment ---------- */
async function loadCats() { S.cats = (await api('/admin/categories')).data; return S.cats; }

async function vEquipment(params) {
  await loadCats();
  const st = { cat: params.get('cat') || '', q: '', active: '' };
  page().innerHTML = head('المعدات', '<button class="btn" id="addE">+ معدة جديدة</button>') + `<div class="filters">
    <label class="search">${svg('search', 16)}<input id="eq" placeholder="ابحث بالاسم أو الماركة"></label>
    <select class="inp" id="ec"><option value="">كل الأقسام</option>${S.cats.map(c => `<option value="${h(c.slug)}">${h(c.name_ar)} (${c.count})</option>`).join('')}</select>
    <select class="inp" id="ea"><option value="">الكل</option><option value="1">فعّالة</option><option value="0">مخفية</option></select></div>
    <div class="tbl"><table><thead><tr><th></th><th>المعدة</th><th>القسم</th><th>الكمية</th><th>علامات</th><th>الحالة</th></tr></thead><tbody id="eb"></tbody></table></div>`;
  $('#ec').value = st.cat;
  const load = async () => {
    const r = await api('/admin/equipment', { query: { category: st.cat, q: st.q, active: st.active } });
    $('#eb').innerHTML = r.data.length ? r.data.map(e => `<tr data-id="${e.id}"><td style="width:70px"><div class="im"><img src="${h(e.image || '')}" alt="" loading="lazy"></div></td>
      <td><div class="nm ltr" style="text-align:right">${h(e.name)}</div><div class="sub">${h(e.brand)} · <span class="ltr">${h(e.slug)}</span></div></td>
      <td>${h(e.category.name_ar)}</td><td class="num"><b>${e.qty_total}</b></td>
      <td>${e.is_featured ? '<span class="chip ink">مميز</span> ' : ''}${e.is_new ? '<span class="chip warn">جديد</span>' : ''}</td>
      <td>${e.is_active ? '<span class="chip ok"><i></i>ظاهر</span>' : '<span class="chip"><i></i>مخفي</span>'}</td></tr>`).join('')
      : '<tr><td colspan="6"><div class="empty"><b>لا توجد معدات</b></div></td></tr>';
    $$('#eb tr[data-id]').forEach(tr => tr.onclick = () => editEquipment(r.data.find(x => x.id === +tr.dataset.id), load));
  };
  let t; $('#eq').oninput = e => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value.trim(); load(); }, 250); };
  $('#ec').onchange = e => { st.cat = e.target.value; load(); };
  $('#ea').onchange = e => { st.active = e.target.value; load(); };
  $('#addE').onclick = () => editEquipment(null, load);
  await load();
}

function editEquipment(e, reload) {
  const isNew = !e;
  e = e || { brand: '', name: '', qty_total: 1, specs: {}, is_active: true, category_id: S.cats[0]?.id, sort: 0 };
  const specs = Object.entries(e.specs || {});
  const d = drawer(isNew ? 'معدة جديدة' : h(e.name), `
    ${isNew ? '' : `<div class="imgbox"><div class="im"><img id="mi" src="${h(e.image || '')}" alt=""></div><div style="flex:1"><b style="font-size:13.5px">الصورة الرئيسية</b><p class="muted" style="font-size:12px;margin:4px 0 8px">JPG / PNG / WEBP حتى 5MB — يتم تحسينها تلقائياً</p>
      <label class="btn lt sm" style="cursor:pointer">تغيير الصورة<input type="file" accept="image/*" id="upM" hidden data-skip="1"></label>
      <label class="btn ghost sm" style="cursor:pointer">+ صورة إضافية<input type="file" accept="image/*" id="upG" hidden data-skip="1"></label></div></div>
      <div class="gal" id="gal"></div>`}
    <form class="fm" id="ef" style="margin-top:14px">
      <div class="row"><div class="f"><label>الماركة</label><input name="brand" value="${h(e.brand)}" required></div><div class="f"><label>الاسم / الموديل</label><input name="name" value="${h(e.name)}" required></div></div>
      <div class="row"><div class="f"><label>القسم</label><select name="category_id">${S.cats.map(c => `<option value="${c.id}" ${c.id === e.category_id ? 'selected' : ''}>${h(c.name_ar)}</option>`).join('')}</select></div>
        <div class="f"><label>الكمية في الأسطول</label><input name="qty_total" type="number" min="0" value="${e.qty_total}"></div></div>
      <div class="row"><div class="f"><label>سعر اليوم (داخلي)</label><input name="daily_rate" inputmode="decimal" dir="ltr" value="${e.daily_rate ?? ''}"></div>
        <div class="f"><label>الترتيب</label><input name="sort" type="number" value="${e.sort || 0}"></div></div>
      <div class="f"><label>المعرّف في الرابط (slug)</label><input name="slug" dir="ltr" value="${h(e.slug || '')}" placeholder="يُولَّد تلقائياً"></div>
      <div class="f"><label>الوصف</label><textarea name="description" rows="3">${h(e.description || '')}</textarea></div>
      <div class="f"><label>المواصفات</label><div class="kv" id="kv">${specs.map(([k, v]) => kvRow(k, v)).join('')}</div><button type="button" class="btn ghost sm" id="addKv" style="margin-top:6px">+ مواصفة</button></div>
      <div class="checks"><label><input type="checkbox" name="is_active" ${e.is_active ? 'checked' : ''}>ظاهر في الموقع</label><label><input type="checkbox" name="is_featured" ${e.is_featured ? 'checked' : ''}>مميز</label><label><input type="checkbox" name="is_new" ${e.is_new ? 'checked' : ''}>جديد</label></div>
    </form>`,
    `<button class="btn" id="save">${isNew ? 'إضافة' : 'حفظ'}</button>${isNew || S.user.role !== 'admin' ? '' : '<button class="btn lt" id="del" style="flex:none;color:var(--red)">حذف</button>'}`);
  const bindKv = () => $$('#kv .del', d).forEach(b => b.onclick = () => b.closest('.r').remove());
  bindKv();
  $('#addKv').onclick = () => { $('#kv').insertAdjacentHTML('beforeend', kvRow('', '')); bindKv(); };
  const drawGal = g => { if ($('#gal')) { $('#gal').innerHTML = (g || []).map(x => `<div><img src="${h(x.url)}" alt=""><button type="button" data-g="${x.id}" aria-label="حذف">×</button></div>`).join(''); $$('#gal [data-g]').forEach(b => b.onclick = async () => { try { const r = await api('/admin/gallery/' + b.dataset.g, { method: 'DELETE' }); drawGal(r.data.gallery); } catch (er) { fail(er); } }); } };
  if (!isNew) api('/admin/equipment/' + e.id).then(r => drawGal(r.data.gallery)).catch(() => {});
  const up = (input, gallery) => input && (input.onchange = async () => {
    const f = input.files[0]; if (!f) return;
    const fdx = new FormData(); fdx.append('image', f); if (gallery) fdx.append('gallery', '1');
    toast('جاري رفع الصورة…');
    try { const r = await api(`/admin/equipment/${e.id}/image`, { method: 'POST', form: fdx }); $('#mi').src = r.data.image + '?t=' + Date.now(); drawGal(r.data.gallery); toast('تم رفع الصورة'); reload(); }
    catch (er) { fail(er); }
  });
  up($('#upM'), false); up($('#upG'), true);
  $('#save').onclick = async () => {
    const f = $('#ef');
    const body = val(f);
    body.specs = {};
    $$('#kv .r', d).forEach(r => { const [k, v] = $$('input', r).map(i => i.value.trim()); if (k) body.specs[k] = v; });
    delete body.k; delete body.v;
    if (!body.slug) delete body.slug;
    try {
      const r = await api(isNew ? '/admin/equipment' : '/admin/equipment/' + e.id, { method: isNew ? 'POST' : 'PATCH', body });
      toast(isNew ? 'تمت الإضافة — يمكنك الآن رفع الصورة' : 'تم الحفظ');
      reload();
      if (isNew) editEquipment({ ...r.data, category_id: r.data.category_id }, reload); else closeDrawer();
    } catch (er) { markErrors(f, er.details); fail(er); }
  };
  if ($('#del')) $('#del').onclick = async () => {
    if (!confirm('حذف هذه المعدة؟ إذا كانت مرتبطة بطلبات سابقة سيتم إخفاؤها فقط.')) return;
    try { const r = await api('/admin/equipment/' + e.id, { method: 'DELETE' }); toast(r.data.result === 'archived' ? 'تم إخفاؤها (مرتبطة بطلبات سابقة)' : 'تم الحذف'); closeDrawer(); reload(); } catch (er) { fail(er); }
  };
}
const kvRow = (k, v) => `<div class="r"><input name="k" placeholder="مثلاً: الدقة" value="${h(k)}" data-skip="1"><input name="v" placeholder="4K" value="${h(v)}" data-skip="1"><button type="button" class="del" aria-label="حذف">×</button></div>`;

/* ---------- categories ---------- */
async function vCategories() {
  const cats = await loadCats();
  page().innerHTML = head('الأقسام', '<button class="btn" id="addC">+ قسم جديد</button>') + `<div class="tbl"><table><thead><tr><th></th><th>الاسم</th><th>بالإنجليزية</th><th>المعدات</th><th>الترتيب</th><th>الحالة</th></tr></thead><tbody>
    ${cats.map(c => `<tr data-id="${c.id}"><td style="width:70px"><div class="im"><img src="${h(c.image || '')}" alt=""></div></td><td class="nm">${h(c.name_ar)}</td><td class="ltr" style="text-align:right">${h(c.name_en)}</td><td class="num">${c.count}</td><td class="num">${c.sort}</td><td>${c.is_active ? '<span class="chip ok"><i></i>ظاهر</span>' : '<span class="chip"><i></i>مخفي</span>'}</td></tr>`).join('')}
    </tbody></table></div>`;
  const edit = c => {
    const isNew = !c; c = c || { name_ar: '', name_en: '', sort: cats.length + 1, is_active: true };
    drawer(isNew ? 'قسم جديد' : h(c.name_ar), `<form class="fm" id="cf"><div class="f"><label>الاسم بالعربية</label><input name="name_ar" value="${h(c.name_ar)}"></div><div class="f"><label>الاسم بالإنجليزية</label><input name="name_en" dir="ltr" value="${h(c.name_en)}"></div>
      <div class="row"><div class="f"><label>الترتيب</label><input type="number" name="sort" value="${c.sort}"></div><div class="f"><label>&nbsp;</label><div class="checks"><label><input type="checkbox" name="is_active" ${c.is_active ? 'checked' : ''}>ظاهر</label></div></div></div>
      ${isNew ? '' : `<p class="muted" style="font-size:12px">صورة القسم تُؤخذ من أول معدة فيه عند الاستيراد. المعرّف: <span class="ltr">${h(c.slug)}</span></p>`}</form>`,
      `<button class="btn" id="save">حفظ</button>${isNew || S.user.role !== 'admin' ? '' : '<button class="btn lt" id="del" style="flex:none;color:var(--red)">حذف</button>'}`);
    $('#save').onclick = async () => { try { await api(isNew ? '/admin/categories' : '/admin/categories/' + c.id, { method: isNew ? 'POST' : 'PATCH', body: val($('#cf')) }); toast('تم الحفظ'); closeDrawer(); vCategories(); } catch (e) { markErrors($('#cf'), e.details); fail(e); } };
    if ($('#del')) $('#del').onclick = async () => { if (!confirm('حذف القسم؟')) return; try { await api('/admin/categories/' + c.id, { method: 'DELETE' }); toast('تم الحذف'); closeDrawer(); vCategories(); } catch (e) { fail(e); } };
  };
  $('#addC').onclick = () => edit(null);
  $$('tr[data-id]').forEach(tr => tr.onclick = () => edit(cats.find(c => c.id === +tr.dataset.id)));
}

/* ---------- kits ---------- */
async function vKits() {
  const [{ data: kits }, { data: eq }] = await Promise.all([api('/admin/kits'), api('/admin/equipment', { query: { active: 1 } })]);
  page().innerHTML = head('الباقات الجاهزة', '<button class="btn" id="addK">+ باقة جديدة</button>') + `<div class="grid2">${kits.map(k => `<div class="card" data-id="${k.id}" style="cursor:pointer">
    <h3>${h(k.name_ar)} ${k.is_active ? '' : '<span class="chip">مخفية</span>'}<small class="ltr">${h(k.name_en)}</small></h3><div class="list">${k.items.map(i => `<div class="lr"><div class="t ltr" style="text-align:right">${h(i.name)}</div><b>×${i.qty}</b></div>`).join('')}</div></div>`).join('') || '<div class="empty"><b>لا توجد باقات</b></div>'}</div>`;
  const edit = k => {
    const isNew = !k; k = k || { name_ar: '', name_en: '', sort: 0, is_active: true, items: [] };
    const row = (it = {}) => `<div class="r" style="grid-template-columns:1fr 70px 34px"><select data-skip="1">${eq.map(e => `<option value="${e.id}" ${e.id === it.equipment_id ? 'selected' : ''}>${h(e.brand + ' — ' + e.name)}</option>`).join('')}</select><input type="number" min="1" value="${it.qty || 1}" data-skip="1"><button type="button" class="del">×</button></div>`;
    const d = drawer(isNew ? 'باقة جديدة' : h(k.name_ar), `<form class="fm" id="kf"><div class="row"><div class="f"><label>الاسم بالعربية</label><input name="name_ar" value="${h(k.name_ar)}"></div><div class="f"><label>بالإنجليزية</label><input name="name_en" dir="ltr" value="${h(k.name_en)}"></div></div>
      <div class="row"><div class="f"><label>الترتيب</label><input type="number" name="sort" value="${k.sort}"></div><div class="f"><label>&nbsp;</label><div class="checks"><label><input type="checkbox" name="is_active" ${k.is_active ? 'checked' : ''}>ظاهرة</label></div></div></div>
      <div class="f"><label>محتوى الباقة</label><div class="kv" id="ki">${k.items.map(row).join('')}</div><button type="button" class="btn ghost sm" id="addI" style="margin-top:6px">+ معدة</button></div></form>`,
      `<button class="btn" id="save">حفظ</button>${isNew ? '' : '<button class="btn lt" id="del" style="flex:none;color:var(--red)">حذف</button>'}`);
    const bind = () => $$('#ki .del', d).forEach(b => b.onclick = () => b.closest('.r').remove());
    bind();
    $('#addI').onclick = () => { $('#ki').insertAdjacentHTML('beforeend', row()); bind(); };
    $('#save').onclick = async () => {
      const body = val($('#kf'));
      body.items = $$('#ki .r', d).map(r => ({ equipment_id: +$('select', r).value, qty: +$('input', r).value || 1 }));
      try { await api(isNew ? '/admin/kits' : '/admin/kits/' + k.id, { method: isNew ? 'POST' : 'PATCH', body }); toast('تم الحفظ'); closeDrawer(); vKits(); } catch (e) { markErrors($('#kf'), e.details); fail(e); }
    };
    if ($('#del')) $('#del').onclick = async () => { if (!confirm('حذف الباقة؟')) return; try { await api('/admin/kits/' + k.id, { method: 'DELETE' }); closeDrawer(); vKits(); } catch (e) { fail(e); } };
  };
  $('#addK').onclick = () => edit(null);
  $$('.card[data-id]').forEach(c => c.onclick = () => edit(kits.find(k => k.id === +c.dataset.id)));
}

/* ---------- users ---------- */
async function vUsers() {
  const st = { q: '', role: '' };
  page().innerHTML = head('المستخدمون', '<button class="btn" id="addU">+ موظف / مدير</button>') + `<div class="filters"><label class="search">${svg('search', 16)}<input id="uq" placeholder="الاسم، البريد، الهاتف"></label>
    <div class="seg" id="ur"><button data-r="" class="on">الكل</button><button data-r="customer">عملاء</button><button data-r="staff">موظفون</button><button data-r="admin">مدراء</button></div></div>
    <div class="tbl"><table><thead><tr><th>المستخدم</th><th>الهاتف</th><th>الدور</th><th>الطلبات</th><th>آخر دخول</th><th>الحالة</th></tr></thead><tbody id="ub"></tbody></table></div>`;
  const ROLE = { customer: 'عميل', staff: 'موظف', admin: 'مدير' };
  const load = async () => {
    const { data } = await api('/admin/users', { query: st });
    $('#ub').innerHTML = data.map(u => `<tr data-id="${u.id}"><td><div class="nm">${h(u.name)}</div><div class="sub ltr" style="text-align:right">${h(u.email)}</div></td><td class="ltr" style="text-align:right">${h(u.phone || '—')}</td>
      <td><span class="chip ${u.role === 'admin' ? 'ink' : ''}">${ROLE[u.role]}</span></td><td class="num">${u.orders}</td><td class="sub">${fdt(u.last_login_at)}</td>
      <td>${u.status === 'active' ? '<span class="chip ok"><i></i>فعّال</span>' : '<span class="chip red"><i></i>معطّل</span>'}</td></tr>`).join('') || '<tr><td colspan="6"><div class="empty"><b>لا نتائج</b></div></td></tr>';
    $$('#ub tr[data-id]').forEach(tr => tr.onclick = () => edit(data.find(u => u.id === +tr.dataset.id)));
  };
  const edit = u => {
    const isNew = !u;
    drawer(isNew ? 'حساب موظف جديد' : h(u.name), `<form class="fm" id="uf">
      ${isNew ? '<div class="f"><label>الاسم</label><input name="name"></div><div class="row"><div class="f"><label>البريد</label><input name="email" type="email" dir="ltr"></div><div class="f"><label>الهاتف</label><input name="phone" dir="ltr"></div></div>' : `<div class="info"><div><small>البريد</small><b class="ltr">${h(u.email)}</b></div><div><small>الشركة</small><b>${h(u.company || '—')}</b></div><div><small>تاريخ التسجيل</small><b>${fdt(u.created_at)}</b></div><div><small>الطلبات</small><b>${u.orders}</b></div></div>`}
      <div class="row"><div class="f"><label>الدور</label><select name="role">${Object.entries(ROLE).map(([k, v]) => `<option value="${k}" ${(u?.role || 'staff') === k ? 'selected' : ''}>${v}</option>`).join('')}</select></div>
      ${isNew ? '' : `<div class="f"><label>الحالة</label><select name="status"><option value="active" ${u.status === 'active' ? 'selected' : ''}>فعّال</option><option value="disabled" ${u.status === 'disabled' ? 'selected' : ''}>معطّل</option></select></div>`}</div>
      <div class="f"><label>${isNew ? 'كلمة المرور' : 'كلمة مرور جديدة (اتركها فارغة لعدم التغيير)'}</label><input name="password" type="password" autocomplete="new-password"></div>
      <p class="muted" style="font-size:12px">تغيير الدور أو الحالة أو كلمة المرور يُنهي كل جلسات المستخدم.</p></form>`, '<button class="btn" id="save">حفظ</button>');
    $('#save').onclick = async () => {
      const body = val($('#uf')); if (!body.password) delete body.password;
      try { await api(isNew ? '/admin/users' : '/admin/users/' + u.id, { method: isNew ? 'POST' : 'PATCH', body }); toast('تم الحفظ'); closeDrawer(); load(); } catch (e) { markErrors($('#uf'), e.details); fail(e); }
    };
  };
  let t; $('#uq').oninput = e => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value.trim(); load(); }, 300); };
  $$('#ur button').forEach(b => b.onclick = () => { st.role = b.dataset.r; $$('#ur button').forEach(x => x.classList.toggle('on', x === b)); load(); });
  $('#addU').onclick = () => edit(null);
  await load();
}

/* ---------- import / export ---------- */
async function vImport() {
  page().innerHTML = head('استيراد وتصدير البيانات') + `<div class="grid2">
    <div class="card"><h3>استيراد معدات</h3>
      <label class="drop" id="drop"><b>اسحب ملف JSON أو CSV هنا</b><span class="muted" style="font-size:12.5px">أو اضغط للاختيار — حتى 20MB</span><input type="file" id="file" accept=".json,.csv,application/json,text/csv" hidden></label>
      <p class="muted" style="font-size:12.5px;line-height:1.9;margin-top:12px">• المعدات الموجودة (نفس الـ slug) تُحدَّث ولا تتكرر.<br>• الأقسام غير الموجودة تُنشأ تلقائياً.<br>• حقل الصورة يقبل رابط http(s) — يُنزَّل ويُحسَّن تلقائياً على السيرفر.</p>
      <div id="rep" style="margin-top:12px"></div></div>
    <div class="card"><h3>تصدير ونماذج</h3>
      <div class="list"><div class="lr"><div class="t"><b>تصدير كل المعدات (JSON)</b><small>نسخة احتياطية، أو لنقلها لسيرفر آخر</small></div><button class="btn lt sm" id="exp">تنزيل</button></div>
      <div class="lr"><div class="t"><b>نموذج CSV</b><small>افتحه في Excel واملأه ثم استورده</small></div><button class="btn lt sm" id="tpl">تنزيل</button></div></div>
      <div class="sect">صيغة JSON</div>
      <pre class="code">{
  "categories": [{"slug":"cam","name_ar":"كاميرات","name_en":"Cameras"}],
  "equipment": [{
    "category": "cam", "brand": "ARRI", "name": "ALEXA 35",
    "qty": 1, "image": "https://example.com/alexa35.jpg",
    "description": "...", "featured": true,
    "specs": {"الحساس":"Super 35","الدقة":"4.6K"}
  }]
}</pre></div></div>`;
  const run = async file => {
    const fdx = new FormData(); fdx.append('file', file);
    $('#rep').innerHTML = '<div class="alert warn">جاري الاستيراد… قد يستغرق دقيقة إذا كانت هناك صور من روابط.</div>';
    try {
      const { data: r } = await api('/admin/import', { method: 'POST', form: fdx });
      $('#rep').innerHTML = `<div class="alert ok">تم: ${r.equipment} معدة، ${r.categories} قسم، ${r.kits} باقة، ${r.images} صورة</div>${r.errors.length ? `<div class="alert red" style="margin-top:8px">${r.errors.slice(0, 20).map(h).join('<br>')}</div>` : ''}`;
    } catch (e) { $('#rep').innerHTML = `<div class="alert red">${h(e.message)}</div>`; }
  };
  const drop = $('#drop');
  $('#file').onchange = e => e.target.files[0] && run(e.target.files[0]);
  ['dragenter', 'dragover'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.add('on'); }));
  ['dragleave', 'drop'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.remove('on'); }));
  drop.addEventListener('drop', e => e.dataTransfer.files[0] && run(e.dataTransfer.files[0]));
  const dl = (name, blob) => { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 1000); };
  $('#exp').onclick = async () => { try { const { data } = await api('/admin/export'); dl('ghani-equipment-' + new Date().toISOString().slice(0, 10) + '.json', new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })); } catch (e) { fail(e); } };
  $('#tpl').onclick = () => dl('equipment-template.csv', new Blob(['﻿category,brand,name,qty,image,description,featured,is_new,specs\ncam,ARRI,ALEXA 35,1,https://example.com/alexa35.jpg,كاميرا سينمائية,1,1,الحساس=Super 35;الدقة=4.6K\n'], { type: 'text/csv' }));
}

/* ---------- settings ---------- */
async function vSettings() {
  const { data: s } = await api('/admin/settings');
  const F = [['company_name', 'اسم الشركة (EN)'], ['company_name_ar', 'اسم الشركة (عربي)'], ['phone', 'الهاتف', 1], ['whatsapp', 'واتساب الطلبات (بدون +)', 1], ['email', 'البريد', 1], ['website', 'الموقع', 1], ['instagram', 'Instagram', 1], ['facebook', 'Facebook', 1], ['currency', 'العملة', 1], ['notify_email', 'بريد استلام إشعارات الطلبات', 1],
    ['app_latest_version', 'التطبيق: آخر إصدار (مثل 1.0.0)', 1], ['app_min_version_ios', 'أقل إصدار مسموح — iOS (إجبار التحديث)', 1], ['app_min_version_android', 'أقل إصدار مسموح — Android', 1], ['app_store_url', 'رابط App Store', 1], ['play_store_url', 'رابط Google Play', 1], ['maintenance_message', 'رسالة صيانة (تظهر في التطبيق، اتركها فارغة لإيقافها)']];
  page().innerHTML = head('الإعدادات') + `<div class="card" style="max-width:760px"><form class="fm" id="sf">
    <div class="row">${F.map(([k, l, ltr]) => `<div class="f"><label>${l}</label><input name="${k}" ${ltr ? 'dir="ltr"' : ''} value="${h(s[k])}"></div>`).join('')}</div>
    <div class="f"><label>العنوان</label><input name="address" value="${h(s.address)}"></div>
    <div class="checks"><label><input type="checkbox" id="sp" ${s.show_prices === '1' ? 'checked' : ''} data-skip="1">إظهار سعر اليوم للعملاء في الموقع والتطبيق</label></div>
    <button type="submit" class="btn" style="justify-self:start">حفظ الإعدادات</button></form></div>`;
  $('#sf').onsubmit = async e => {
    e.preventDefault();
    const body = val(e.target); body.show_prices = $('#sp').checked ? '1' : '0';
    try { await api('/admin/settings', { method: 'PUT', body }); toast('تم حفظ الإعدادات'); } catch (er) { fail(er); }
  };
}

/* ---------- system ---------- */
async function vSystem() {
  const [{ data: s }, { data: log }] = await Promise.all([api('/admin/system'), api('/admin/audit')]);
  page().innerHTML = head('النظام والسجل', '<button class="btn lt" id="cc">مسح الكاش</button>') + `<div class="grid2">
    <div class="card"><h3>الخادم</h3><div class="info">
      <div><small>الإصدار</small><b>v${h(s.version)}</b></div><div><small>PHP</small><b>${h(s.php)}</b></div>
      <div><small>قاعدة البيانات</small><b class="ltr">${h(s.db_version)}</b></div><div><small>محرك الكاش</small><b>${h(s.cache_driver)}${s.cache_driver === 'file' ? ' <span class="muted" style="font-size:11px">(فعّل APCu أو Redis لأداء أعلى)</span>' : ''}</b></div>
      <div><small>OPcache</small><b>${s.opcache ? 'مفعّل ✓' : 'غير مفعّل'}</b></div><div><small>HTTPS</small><b>${s.https ? 'مفعّل ✓' : 'غير مفعّل ⚠'}</b></div></div>
      <div class="sect">توزيع الأحمال على القاعدة</div>
      <div class="list"><div class="lr"><div class="t"><b class="ltr" style="text-align:right">${h(s.primary)}</b><small>الرئيسي — كل عمليات الكتابة</small></div><span class="chip ok"><i></i>متصل</span></div>
      ${s.replicas.length ? s.replicas.map(r => `<div class="lr"><div class="t"><b class="ltr" style="text-align:right">${h(r.host)}</b><small>قراءة${r.ok ? ` · ${r.ms}ms${r.lag_seconds != null ? ' · تأخر ' + r.lag_seconds + 's' : ''}` : ''}</small></div>${r.ok ? '<span class="chip ok"><i></i>متصل</span>' : '<span class="chip red"><i></i>متوقف</span>'}</div>`).join('') : '<div class="lr"><div class="t"><small>لا توجد سيرفرات قراءة — القراءة والكتابة على الرئيسي. أضفها في config/config.php ← db.replicas</small></div></div>'}</div></div>
    <div class="card"><h3>الجداول</h3><div class="list">${s.tables.map(t => `<div class="lr"><div class="t ltr" style="text-align:right">${h(t.name)}</div><small>${num(t.rows)} صف · ${num(t.kb)} KB</small></div>`).join('')}</div></div></div>
    <div class="card" style="margin-top:14px"><h3>سجل العمليات <small>آخر 300 عملية</small></h3>
      <div class="tbl" style="box-shadow:none"><table><thead><tr><th>الوقت</th><th>المستخدم</th><th>العملية</th><th>العنصر</th><th>IP</th></tr></thead><tbody>
      ${log.map(a => `<tr style="cursor:default"><td class="sub">${fdt(a.created_at)}</td><td>${h(a.user_name || '—')}</td><td class="ltr" style="text-align:right">${h(a.action)}</td><td class="sub">${h(a.entity || '')}${a.entity_id ? ' #' + a.entity_id : ''}</td><td class="sub ltr" style="text-align:right">${h(a.ip)}</td></tr>`).join('')}
      </tbody></table></div></div>`;
  $('#cc').onclick = async () => { try { await api('/admin/cache/clear', { method: 'POST' }); toast('تم مسح الكاش'); } catch (e) { fail(e); } };
}

/* ---------- init ---------- */
(async () => {
  try {
    const r = await api('/auth/me');
    if (r.data && ['admin', 'staff'].includes(r.data.role)) { S.user = r.data; shell(); return; }
  } catch (e) { /* not logged in */ }
  renderLogin();
})();
})();
