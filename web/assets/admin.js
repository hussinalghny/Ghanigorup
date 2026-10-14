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
  store: '<path d="M3 8 10 3l7 5v9H3z"/><path d="M7 17v-5h6v5"/>',
  banner: '<rect x="2.5" y="4" width="15" height="10" rx="2"/><path d="m5 11 3-3 2.5 2.5L13 8l2.5 3M6 17h8"/>',
  brand: '<path d="M10 2.5 12.2 7l5 .7-3.6 3.5.8 5L10 13.8 5.6 16.2l.8-5L2.8 7.7l5-.7z"/>',
  bell: '<path d="M5 8a5 5 0 0 1 10 0c0 5 2 6 2 6H3s2-1 2-6M8.5 17a1.8 1.8 0 0 0 3 0"/>',
  sign: '<path d="M3 15c2-1 3-5 5-5s0 5 2 5 2-3 3.5-3 1 2 3.5 2M3 18h14"/>',
};
const ROLE = { customer: 'عميل', staff: 'موظف', storekeeper: 'أمين مخزن', technician: 'فني', admin: 'مدير' };
const can = p => !!S.user && (S.user.perms || []).some(x => x === '*' || x === p);
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
  d.classList.remove('wide'); d.classList.add('on'); $('#scrim').classList.add('on');
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
    <h1>لوحة التحكم</h1><p>${h(msg || 'سجّل الدخول بحساب المدير أو الموظف أو أمين المخزن')}</p>
    <div class="fm"><div class="f"><label>البريد الإلكتروني</label><input name="email" type="email" dir="ltr" autocomplete="username" required></div>
    <div class="f"><label>كلمة المرور</label><input name="password" type="password" dir="ltr" autocomplete="current-password" required></div>
    <button class="btn block">دخول</button></div>
    <p style="margin:16px 0 0;text-align:center"><a href="./" class="muted" style="font-size:12.5px">← العودة للموقع</a></p></form></div>`;
  $('#lf').onsubmit = async e => {
    e.preventDefault();
    const b = $('#lf button'); b.disabled = true;
    try {
      const r = await api('/auth/login', { method: 'POST', body: val(e.target) });
      if (!['admin', 'staff', 'storekeeper'].includes(r.data.user.role)) { await api('/auth/logout', { method: 'POST' }); throw new Error('هذا الحساب ليس لديه صلاحية لوحة التحكم'); }
      S.user = r.data.user; shell();
    } catch (err) { b.disabled = false; toast(err.message, true); }
  };
}

/* ---------- shell ---------- */
// [المسار، الاسم، الأيقونة، الصلاحية المطلوبة]
const NAV = [
  ['dash', 'الرئيسية', 'dash', 'dashboard'], ['orders', 'الطلبات', 'orders', 'orders.view'], ['store', 'المخزن — تسليم وإرجاع', 'store', 'handover'],
  ['equipment', 'المعدات', 'eq', 'equipment.edit'], ['categories', 'الأقسام', 'cats', 'catalog.edit'], ['kits', 'الباقات', 'kits', 'catalog.edit'],
  ['brands', 'الماركات', 'brand', 'brands'], ['banners', 'البنرات الإعلانية', 'banner', 'banners'], ['notifications', 'الإشعارات', 'bell', 'notifications'],
  ['users', 'المستخدمون', 'users', 'admin'], ['import', 'استيراد وتصدير', 'imp', 'admin'], ['settings', 'الإعدادات', 'set', 'admin'], ['system', 'النظام والسجل', 'sys', 'admin'],
];
const navOk = n => n[3] === 'admin' ? S.user.role === 'admin' : can(n[3]);
function shell() {
  root.innerHTML = `<div class="shell"><nav class="side" id="side">
      <div class="logo"><img src="assets/brand/mark.png" alt="" width="28" height="28">Ghani Group</div>
      ${NAV.filter(navOk).map(n => `<a href="admin#/${n[0]}" data-p="${n[0]}">${svg(n[2])}${n[1]}${n[0] === 'orders' ? '<span class="n" id="pendN" hidden></span>' : ''}${n[0] === 'store' ? '<span class="n" id="storeN" hidden></span>' : ''}</a>`).join('')}
      <div class="me"><b>${h(S.user.name)}</b>${ROLE[S.user.role] || ''} · <button id="out">خروج</button> · <a href="./" target="_blank">الموقع</a></div>
    </nav><main><div class="mtop"><div class="logo"><img src="assets/brand/mark.png" alt="" width="28" height="28">لوحة التحكم</div><button id="menu" aria-label="القائمة">${svg('menu')}</button></div><div id="page"></div></main></div>`;
  $('#out').onclick = async () => { try { await api('/auth/logout', { method: 'POST' }); } catch (e) { /* ignore */ } S.user = null; renderLogin('تم تسجيل الخروج'); };
  $('#menu').onclick = () => $('#side').classList.toggle('open');
  route();
  updateStoreBadge();
}
const page = () => $('#page');
const head = (t, acts = '') => `<div class="head"><h1>${t}</h1><div class="acts">${acts}</div></div>`;

async function route() {
  if (!S.user) return;
  let [p, qs] = (location.hash.replace(/^#\/?/, '') || (S.user.role === 'storekeeper' ? 'store' : 'dash')).split('?');
  const nav = NAV.find(n => n[0] === p);
  if (nav && !navOk(nav)) p = S.user.role === 'storekeeper' ? 'store' : 'dash';
  S.page = p;
  $$('#side a').forEach(a => a.classList.toggle('on', a.dataset.p === p));
  $('#side')?.classList.remove('open');
  closeDrawer();
  page().innerHTML = '<div class="skel"></div>';
  const views = { dash: vDash, orders: vOrders, store: vStore, equipment: vEquipment, categories: vCategories, kits: vKits, brands: vBrands, banners: vBanners, notifications: vNotifications, users: vUsers, import: vImport, settings: vSettings, system: vSystem };
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
      <a class="kpi" href="${S.user.role === 'admin' ? 'admin#/users' : 'admin#/dash'}"><small>العملاء</small><b>${num(d.customers)}</b><span>حساب مسجّل</span></a>
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
  const edit = can('orders.edit');
  const wa = String(o.phone).replace(/\D/g, '').replace(/^0/, '964');
  const canOut = can('handover') && ['pending', 'quoted', 'confirmed'].includes(o.status);
  const canRet = can('handover') && o.status === 'out';
  const d = drawer(`طلب <span class="ltr">${h(o.ref)}</span>`, `
    ${edit ? `<div class="statusbar" id="sb">${Object.keys(STATUS).map(s => `<button data-s="${s}" class="${s === o.status ? 'on' : ''}">${SHORT[s]}</button>`).join('')}</div>` : chip(o.status)}
    <p class="muted" style="font-size:12px;margin-top:8px">الحالية: ${STATUS[o.status][0]} · آخر تحديث ${fdt(o.updated_at)}</p>
    ${canOut || canRet ? `<div class="hoact">${canOut ? `<button class="btn" id="doOut">${svg('sign', 18)} تسليم المعدات للعميل بالتوقيع</button>` : ''}${canRet ? `<button class="btn" id="doRet">${svg('sign', 18)} استلام المعدات المُرجَعة بالتوقيع</button>` : ''}</div>` : ''}
    ${o.shortages.length ? `<div class="alert warn" style="margin-top:12px"><b>تعارض في التوفر</b><br>${o.shortages.map(s => `• ${h(s.name)}: مطلوب ${s.requested} — متاح ${s.available}`).join('<br>')}</div>` : (['pending', 'quoted'].includes(o.status) ? '<div class="alert ok" style="margin-top:12px">كل المعدات متوفرة في هذه الفترة ✓</div>' : '')}
    ${o.handovers.length ? `<div class="sect">محاضر التسليم والإرجاع</div><div class="list card" style="padding:4px 14px">${o.handovers.map(x => `<div class="lr"><div class="t"><b>${x.type === 'checkout' ? 'تسليم للعميل' : 'إرجاع'} — ${h(x.receiver_name)}</b><small>${fdt(x.created_at)} · الموظف: ${h(x.employee_name)}${x.technician_name ? ' · الفني: ' + h(x.technician_name) : ''}</small></div><button class="btn lt sm" data-ho="${x.id}">عرض / طباعة</button></div>`).join('')}</div>` : ''}
    <div class="sect">العميل والمشروع</div>
    <div class="info"><div><small>الاسم</small><b>${h(o.contact_name)}</b></div><div><small>الهاتف</small><b class="ltr">${h(o.phone)}</b></div>
      <div><small>المشروع</small><b>${h(o.project || '—')}</b></div><div><small>الموقع</small><b>${h(o.location || '—')}</b></div>
      <div><small>المدة</small><b>${fd(o.start_date)} ← ${fd(o.end_date)} (${o.days} يوم)</b></div><div><small>إضافات</small><b>${[o.technician ? 'فني مرافق' : '', o.delivery ? 'توصيل' : ''].filter(Boolean).join(' + ') || 'لا يوجد'}</b></div></div>
    ${o.notes ? `<div class="sect">ملاحظات العميل</div><div class="card" style="padding:14px">${h(o.notes)}</div>` : ''}
    <div class="sect">المعدات (${o.items.reduce((a, b) => a + b.qty, 0)} قطعة)</div>
    <div class="card oitems" style="padding:6px 14px"><div class="list">${o.items.map(i => `<div class="lr"><img src="${h(i.image || '')}" alt=""><div class="t"><b class="ltr" style="text-align:right">${h(i.name)}</b><small>${h(i.brand)}</small></div><b>×${i.qty}</b></div>`).join('')}</div></div>
    ${edit ? `<div class="sect">التسعير والملاحظات الداخلية</div>
    <form class="fm" id="of"><div class="row"><div class="f"><label>مبلغ عرض السعر</label><input name="quote_amount" inputmode="decimal" dir="ltr" value="${o.quote_amount ?? ''}"></div>
      <div class="f"><label>تعديل التواريخ</label><div style="display:flex;gap:6px"><input type="date" name="start_date" value="${o.start_date}"><input type="date" name="end_date" value="${o.end_date}"></div></div></div>
      <div class="f"><label>ملاحظات داخلية (لا تظهر للعميل)</label><textarea name="admin_notes" rows="3">${h(o.admin_notes || '')}</textarea></div></form>
    <p class="muted" style="font-size:11.5px;margin-top:10px">تغيير الحالة يرسل إشعاراً للعميل في التطبيق تلقائياً.</p>` : (o.admin_notes ? `<div class="sect">ملاحظات داخلية</div><div class="card" style="padding:14px">${h(o.admin_notes)}</div>` : '')}
    <p class="muted" style="font-size:11.5px;margin-top:10px">IP: <span class="ltr">${h(o.ip || '')}</span> · أُنشئ ${fdt(o.created_at)}${o.user_id ? ' · عميل مسجّل #' + o.user_id : ' · بدون حساب'}</p>`,
    `${edit ? '<button class="btn" id="save">حفظ</button>' : ''}<a class="btn lt" target="_blank" rel="noopener" href="https://wa.me/${h(wa)}?text=${encodeURIComponent('مرحباً ' + o.contact_name + '، بخصوص طلبك ' + o.ref + ' من Ghani Group')}">واتساب العميل</a>`);
  $$('#sb button', d).forEach(b => b.onclick = () => { status = b.dataset.s; $$('#sb button', d).forEach(x => x.classList.toggle('on', x === b)); });
  $$('[data-ho]', d).forEach(b => b.onclick = () => printHandover(o, o.handovers.find(x => x.id === +b.dataset.ho)));
  if ($('#doOut')) $('#doOut').onclick = () => handoverForm(o, 'checkout', reload);
  if ($('#doRet')) $('#doRet').onclick = () => handoverForm(o, 'return', reload);
  const save = async (force = false) => {
    const body = val($('#of')); body.status = status; if (force) body.force = true;
    try { await api('/admin/orders/' + id, { method: 'PATCH', body }); toast('تم حفظ الطلب'); closeDrawer(); reload && reload(); }
    catch (e) {
      if (e.code === 'shortage' && confirm('الكمية غير كافية لبعض المعدات:\n' + e.details.shortages.map(s => `${s.name}: مطلوب ${s.requested}، متاح ${s.available}`).join('\n') + '\n\nتأكيد رغم ذلك؟')) return save(true);
      if (e.code !== 'shortage') fail(e);
    }
  };
  if ($('#save')) $('#save').onclick = () => save();
}

/* ---------- التوقيع الإلكتروني ---------- */
function sigPad(host, label) {
  host.innerHTML = `<div class="sig"><canvas></canvas><span class="sig-ph">${h(label)}</span><button type="button" class="sig-clr">مسح</button><i class="sig-line"></i></div>`;
  const box = $('.sig', host), c = $('canvas', box), ctx = c.getContext('2d');
  let pts = [], drawing = false, empty = true, lastW = 2.6;
  const fit = () => {
    const r = box.getBoundingClientRect(), dpr = Math.max(1, Math.min(3, window.devicePixelRatio || 1));
    c.width = Math.round(r.width * dpr); c.height = Math.round(r.height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = '#141414'; ctx.fillStyle = '#141414';
  };
  requestAnimationFrame(fit);
  const pos = e => { const r = c.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top, t: performance.now() }; };
  c.addEventListener('pointerdown', e => {
    e.preventDefault(); if (!c.width) fit();
    c.setPointerCapture(e.pointerId); drawing = true; pts = [pos(e)]; lastW = 2.6;
    if (empty) { empty = false; box.classList.add('on'); }
    const p = pts[0]; ctx.beginPath(); ctx.arc(p.x, p.y, 1.3, 0, Math.PI * 2); ctx.fill();
  });
  c.addEventListener('pointermove', e => {
    if (!drawing) return;
    const events = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
    for (const ev of events) {
      const p = pos(ev), q = pts[pts.length - 1];
      const dist = Math.hypot(p.x - q.x, p.y - q.y); if (dist < 1) continue;
      const speed = dist / Math.max(1, p.t - q.t);
      const w = Math.max(1.2, Math.min(3.4, 3.6 - speed * 1.1)); lastW = lastW * .7 + w * .3;
      pts.push(p);
      const n = pts.length; if (n < 3) continue;
      const a = pts[n - 3], b = pts[n - 2];
      ctx.lineWidth = lastW; ctx.beginPath();
      ctx.moveTo((a.x + b.x) / 2, (a.y + b.y) / 2); ctx.quadraticCurveTo(b.x, b.y, (b.x + p.x) / 2, (b.y + p.y) / 2); ctx.stroke();
    }
  });
  const end = () => { drawing = false; };
  c.addEventListener('pointerup', end); c.addEventListener('pointercancel', end);
  $('.sig-clr', box).onclick = () => { ctx.clearRect(0, 0, c.width, c.height); empty = true; box.classList.remove('on'); };
  return { isEmpty: () => empty, data: () => (empty ? '' : c.toDataURL('image/png')) };
}

let staffCache = null;
async function handoverForm(o, type, reload) {
  const out = type === 'checkout';
  if (!staffCache) staffCache = (await api('/admin/staff')).data;
  const techs = staffCache.filter(u => u.role === 'technician');
  const emps = staffCache.filter(u => u.role !== 'technician');
  const cond = i => out ? '' : `<select data-c="${i.equipment_id}"><option value="ok">سليمة</option><option value="damaged">متضررة</option><option value="missing">ناقصة</option></select>`;
  const d = drawer(out ? 'محضر تسليم معدات' : 'محضر إرجاع معدات', `
    <div class="alert ${out ? 'ok' : 'warn'}">${out ? 'افحص القطع مع العميل، أشّر على المسلَّم منها، ثم يوقّع المستلم.' : 'افحص كل قطعة مُرجَعة وحدد حالتها، ثم يوقّع الشخص الذي أرجعها.'} الطلب <b class="ltr">${h(o.ref)}</b> — ${h(o.project || o.contact_name)}</div>
    <div class="sect">القطع (${o.items.length})</div>
    <div class="hoitems">${o.items.map(i => `<label class="hoi"><input type="checkbox" data-e="${i.equipment_id}" checked><img src="${h(i.image || '')}" alt=""><span class="t"><b class="ltr">${h(i.name)}</b><small>${h(i.brand)} · المطلوب ${i.qty}</small></span>
      <input type="number" min="0" max="${i.qty}" value="${i.qty}" data-q="${i.equipment_id}" aria-label="الكمية">${cond(i)}<input data-n="${i.equipment_id}" placeholder="ملاحظة" class="hon"></label>`).join('')}</div>
    <form class="fm" id="hf" style="margin-top:14px">
      <div class="row"><div class="f"><label>${out ? 'اسم المستلم (من طرف العميل)' : 'اسم الشخص الذي أرجع المعدات'}</label><input name="receiver_name" value="${h(o.contact_name)}"></div>
        <div class="f"><label>هاتفه</label><input name="receiver_phone" dir="ltr" value="${h(o.phone)}"></div></div>
      <div class="row"><div class="f"><label>الموظف المسؤول</label><select name="employee_id">${emps.map(u => `<option value="${u.id}" ${u.id === S.user.id ? 'selected' : ''}>${h(u.name)} — ${ROLE[u.role]}</option>`).join('')}</select></div>
        <div class="f"><label>${out ? 'الفني الذي خرج مع المعدات' : 'الفني المرافق'}</label><select name="technician_id"><option value="">${o.technician ? '— اختر الفني —' : 'بدون فني'}</option>${techs.map(u => `<option value="${u.id}">${h(u.name)}</option>`).join('')}<option value="other">اسم آخر…</option></select></div></div>
      <div class="f" id="tnBox" hidden><label>اسم الفني</label><input name="technician_name"></div>
      <div class="f"><label>ملاحظات ${out ? 'التسليم' : 'الإرجاع'}</label><textarea name="notes" rows="2" placeholder="${out ? 'مثلاً: البطاريات مشحونة، الكارت فارغ' : 'مثلاً: خدش على الغطاء'}"></textarea></div>
    </form>
    <div class="sect">توقيع ${out ? 'المستلم' : 'المُرجِع'} *</div><div id="sig1"></div>
    <details class="sigmore"><summary>إضافة توقيع الموظف (اختياري)</summary><div id="sig2" style="margin-top:8px"></div></details>
    <p class="muted" style="font-size:11.5px;margin-top:10px">يُحفظ التوقيع مع التاريخ والوقت واسم الموظف وعنوان IP، ولا يمكن تعديل المحضر بعد حفظه. ${out ? 'حالة الطلب ستصبح "مُسلَّم".' : 'حالة الطلب ستصبح "مُرجَع".'}</p>`,
    `<button class="btn" id="hsave">${svg('sign', 18)} حفظ المحضر</button><button class="btn lt" id="hback" style="flex:none">رجوع</button>`);
  d.classList.add('wide');
  const p1 = sigPad($('#sig1'), out ? 'وقّع هنا — المستلم' : 'وقّع هنا — المُرجِع');
  let p2 = null;
  $('.sigmore', d).addEventListener('toggle', e => { if (e.target.open && !p2) p2 = sigPad($('#sig2'), 'توقيع الموظف'); });
  $('[name=technician_id]', d).onchange = e => { $('#tnBox').hidden = e.target.value !== 'other'; };
  $$('.hoi input[type=checkbox]', d).forEach(cb => cb.onchange = () => cb.closest('.hoi').classList.toggle('off', !cb.checked));
  $('#hback').onclick = () => openOrder(o.id, reload);
  const submit = async (force = false) => {
    if (p1.isEmpty()) { toast('التوقيع مطلوب', true); $('#sig1').scrollIntoView({ behavior: 'smooth', block: 'center' }); return; }
    const f = val($('#hf'));
    const body = { type, receiver_name: f.receiver_name, receiver_phone: f.receiver_phone, employee_id: +f.employee_id || undefined, notes: f.notes, signature: p1.data() };
    if (f.technician_id === 'other') body.technician_name = f.technician_name; else if (f.technician_id) body.technician_id = +f.technician_id;
    if (p2 && !p2.isEmpty()) body.employee_signature = p2.data();
    if (force) body.force = true;
    body.items = $$('.hoi', d).map(row => {
      const id = +$('[data-e]', row).dataset.e, checked = $('[data-e]', row).checked;
      return { equipment_id: id, qty: checked ? +$('[data-q]', row).value : 0, condition: out ? 'ok' : (checked ? $('[data-c]', row).value : 'missing'), note: $('[data-n]', row).value };
    }).filter(x => out ? x.qty > 0 : true);
    const btn = $('#hsave'); btn.disabled = true;
    try {
      const r = await api(`/admin/orders/${o.id}/handover`, { method: 'POST', body });
      toast(out ? 'تم التسليم وحفظ المحضر ✓' : 'تم استلام الإرجاع وحفظ المحضر ✓');
      reload && reload();
      updateStoreBadge();
      const fresh = (await api('/admin/orders/' + o.id)).data;
      printHandover(fresh, r.data);
      openOrder(o.id, reload);
    } catch (e) {
      btn.disabled = false;
      if (e.code === 'shortage' && confirm('الكمية غير متوفرة لبعض القطع في هذه الفترة:\n' + e.details.shortages.map(s => `${s.name}: مطلوب ${s.requested}، متاح ${s.available}`).join('\n') + '\n\nالتسليم رغم ذلك؟')) return submit(true);
      if (e.code !== 'shortage') { markErrors($('#hf'), e.details); fail(e); }
    }
  };
  $('#hsave').onclick = () => submit();
}

/* محضر قابل للطباعة مع صور التواقيع (تُجلب من API محمي) */
async function printHandover(o, x) {
  const sigUrl = async who => {
    try {
      const res = await fetch(`${API}/admin/handovers/${x.id}/signature?who=${who}`, { credentials: 'same-origin', headers: { 'X-Client': 'web' } });
      return res.ok ? URL.createObjectURL(await res.blob()) : '';
    } catch (e) { return ''; }
  };
  const [s1, s2] = await Promise.all([sigUrl('customer'), x.has_employee_signature ? sigUrl('employee') : Promise.resolve('')]);
  const out = x.type === 'checkout';
  const CND = { ok: 'سليمة', damaged: 'متضررة', missing: 'ناقصة' };
  let el = $('#print');
  if (!el) { el = document.createElement('div'); el.id = 'print'; document.body.appendChild(el); }
  el.innerHTML = `<div class="pbar"><button class="btn" id="pp">طباعة / حفظ PDF</button><button class="btn lt" id="pc">إغلاق</button></div>
  <article class="paper">
    <header><img src="assets/brand/mark.png" alt=""><div><b>Ghani Group</b><small>قسم تأجير المعدات</small></div><div class="pt"><b>${out ? 'محضر تسليم معدات' : 'محضر إرجاع معدات'}</b><small>رقم المحضر #${x.id} · ${fdt(x.created_at)}</small></div></header>
    <div class="pgrid"><div><small>رقم الطلب</small><b class="ltr">${h(o.ref)}</b></div><div><small>العميل</small><b>${h(o.contact_name)}</b></div><div><small>المشروع</small><b>${h(o.project || '—')}</b></div>
      <div><small>مدة الإيجار</small><b>${fd(o.start_date)} ← ${fd(o.end_date)} (${o.days} يوم)</b></div><div><small>الموظف المسؤول</small><b>${h(x.employee_name)}</b></div><div><small>الفني المرافق</small><b>${h(x.technician_name || '—')}</b></div></div>
    <table><thead><tr><th>#</th><th>القطعة</th><th>المطلوب</th><th>${out ? 'المسلَّم' : 'المُرجَع'}</th>${out ? '' : '<th>الحالة</th>'}<th>ملاحظة</th></tr></thead><tbody>
      ${x.items.map((i, n) => `<tr><td>${n + 1}</td><td><b class="ltr">${h(i.name)}</b><small>${h(i.brand)}</small></td><td>${i.ordered}</td><td>${i.qty}</td>${out ? '' : `<td class="c-${i.condition}">${CND[i.condition]}</td>`}<td>${h(i.note || '')}</td></tr>`).join('')}
    </tbody></table>
    ${x.notes ? `<p class="pnote"><b>ملاحظات:</b> ${h(x.notes)}</p>` : ''}
    <p class="pdecl">${out ? 'أقرّ أنا الموقّع أدناه باستلام المعدات المذكورة أعلاه بحالة سليمة وصالحة للعمل، وأتحمّل مسؤولية المحافظة عليها وإعادتها في الموعد المحدد.' : 'تم استلام المعدات المذكورة أعلاه وفحصها بحضور الطرفين وتسجيل حالتها كما هو مبيّن.'}</p>
    <div class="psig"><div><small>${out ? 'توقيع المستلم' : 'توقيع المُرجِع'}</small>${s1 ? `<img src="${s1}" alt="التوقيع">` : '<i></i>'}<b>${h(x.receiver_name)}</b><span class="ltr">${h(x.receiver_phone || '')}</span></div>
      <div><small>توقيع الموظف المسؤول</small>${s2 ? `<img src="${s2}" alt="">` : '<i></i>'}<b>${h(x.employee_name)}</b></div></div>
    <footer>وثيقة إلكترونية صادرة من نظام Ghani Group — ${new Date().toLocaleString('en-GB')}</footer>
  </article>`;
  el.classList.add('on');
  $('#pp').onclick = () => window.print();
  $('#pc').onclick = () => { el.classList.remove('on'); [s1, s2].forEach(u => u && URL.revokeObjectURL(u)); };
}

/* ---------- المخزن: لوحة التسليم والإرجاع ---------- */
async function updateStoreBadge() {
  if (!can('handover') || !$('#storeN')) return;
  try {
    const { data } = await api('/admin/handovers/board');
    const n = data.to_checkout.filter(o => o.days_left <= 0 && o.status === 'confirmed').length + data.to_return.filter(o => o.days_left < 0).length;
    $('#storeN').textContent = n; $('#storeN').hidden = !n;
  } catch (e) { /* ignore */ }
}
async function vStore() {
  const [{ data: b }, { data: log }] = await Promise.all([api('/admin/handovers/board'), api('/admin/handovers')]);
  const when = o => {
    const n = o.days_left;
    if (o.status === 'out') return n < 0 ? `<span class="chip red"><i></i>متأخر ${-n} يوم</span>` : (n === 0 ? '<span class="chip warn"><i></i>يُرجَع اليوم</span>' : `<span class="chip"><i></i>بعد ${n} يوم</span>`);
    return n < 0 ? `<span class="chip red"><i></i>فات موعده ${-n} يوم</span>` : (n === 0 ? '<span class="chip warn"><i></i>اليوم</span>' : `<span class="chip"><i></i>بعد ${n} يوم</span>`);
  };
  const row = o => `<a class="lr" href="admin#/store?open=${o.id}" data-o="${o.id}"><div class="t"><b>${h(o.project || o.contact_name)}</b><small class="ltr">${h(o.ref)}</small> <small>· ${o.units} قطعة · ${fd(o.start_date)} ← ${fd(o.end_date)}${+o.technician ? ' · فني مرافق' : ''}</small></div>${o.status !== 'out' ? chip(o.status) : ''}${when(o)}</a>`;
  page().innerHTML = head('المخزن — التسليم والإرجاع') + `<div class="grid2">
    <div class="card"><h3>للتسليم خلال 7 أيام <small>${b.to_checkout.length} طلب</small></h3><div class="list">${b.to_checkout.map(row).join('') || '<div class="empty" style="padding:24px">لا توجد طلبات للتسليم</div>'}</div></div>
    <div class="card"><h3>عند العملاء — بانتظار الإرجاع <small>${b.to_return.length} طلب</small></h3><div class="list">${b.to_return.map(row).join('') || '<div class="empty" style="padding:24px">لا توجد معدات خارج المخزن</div>'}</div></div></div>
    <div class="card" style="margin-top:14px"><h3>سجل المحاضر <small>آخر 300</small></h3><div class="tbl" style="box-shadow:none"><table><thead><tr><th>الوقت</th><th>النوع</th><th>الطلب</th><th>المستلم/المُرجِع</th><th>الموظف</th><th>الفني</th><th>ملاحظات القطع</th></tr></thead><tbody>
      ${log.map(x => `<tr data-x="${x.id}"><td class="sub">${fdt(x.created_at)}</td><td>${x.type === 'checkout' ? '<span class="chip ok"><i></i>تسليم</span>' : '<span class="chip ink">إرجاع</span>'}</td><td><b class="ltr">${h(x.ref)}</b><div class="sub">${h(x.project || x.contact_name)}</div></td><td>${h(x.receiver_name)}</td><td>${h(x.employee_name)}</td><td>${h(x.technician_name || '—')}</td><td class="sub">${x.items.filter(i => i.condition !== 'ok' || i.qty < i.ordered).map(i => h(i.name) + ': ' + ({ damaged: 'متضررة', missing: 'ناقصة', ok: 'ناقصة العدد' }[i.condition])).join('، ') || '—'}</td></tr>`).join('') || '<tr><td colspan="7"><div class="empty">لا توجد محاضر بعد</div></td></tr>'}
    </tbody></table></div></div>`;
  const reload = () => vStore();
  $$('[data-o]').forEach(a => a.onclick = e => { e.preventDefault(); openOrder(+a.dataset.o, reload); });
  $$('tr[data-x]').forEach(tr => tr.onclick = async () => { const x = log.find(l => l.id === +tr.dataset.x); const { data: o } = await api('/admin/orders/' + x.order_id); printHandover(o, x); });
  updateStoreBadge();
  const q = new URLSearchParams(location.hash.split('?')[1] || '');
  if (q.get('open')) openOrder(+q.get('open'), reload);
}

/* ---------- equipment ---------- */
async function loadCats() { S.cats = (await api('/admin/categories')).data; return S.cats; }

async function vEquipment(params) {
  await loadCats();
  api('/admin/brands').then(r => { S.brands = r.data; }).catch(() => {});
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
      <div class="row"><div class="f"><label>الماركة</label><input name="brand" value="${h(e.brand)}" list="brandList" required><datalist id="brandList">${(S.brands || []).map(b => `<option value="${h(b.name)}">`).join('')}</datalist></div><div class="f"><label>الاسم / الموديل</label><input name="name" value="${h(e.name)}" required></div></div>
      <div class="row"><div class="f"><label>القسم</label><select name="category_id">${S.cats.map(c => `<option value="${c.id}" ${c.id === e.category_id ? 'selected' : ''}>${h(c.name_ar)}</option>`).join('')}</select></div>
        <div class="f"><label>الكمية في الأسطول</label><input name="qty_total" type="number" min="0" value="${e.qty_total}"></div></div>
      <div class="row">${can('orders.price') ? `<div class="f"><label>سعر اليوم (داخلي)</label><input name="daily_rate" inputmode="decimal" dir="ltr" value="${e.daily_rate ?? ''}"></div>` : ''}
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
      ${isNew ? '<p class="muted" style="font-size:12px">احفظ القسم أولاً ثم افتحه لرفع صورته.</p>' : `<div class="imgbox"><div class="im">${c.image ? `<img src="${h(c.image)}" alt="">` : ''}</div><div style="flex:1"><b style="font-size:13.5px">صورة القسم</b><p class="muted" style="font-size:12px;margin:4px 0 8px">تظهر في الواجهة والتطبيق — JPG أو PNG، يُفضّل خلفية بيضاء</p><div style="display:flex;gap:6px;flex-wrap:wrap"><label class="btn lt sm" style="cursor:pointer">${c.image ? 'تغيير الصورة' : 'رفع صورة'}<input type="file" accept="image/*" id="cimg" hidden data-skip="1"></label>${c.image ? '<button type="button" class="btn lt sm" id="cimgx">صورة أول معدة</button>' : ''}</div></div></div>
      <p class="muted" style="font-size:12px">المعرّف: <span class="ltr">${h(c.slug)}</span></p>`}</form>`,
      `<button class="btn" id="save">حفظ</button>${isNew || S.user.role !== 'admin' ? '' : '<button class="btn lt" id="del" style="flex:none;color:var(--red)">حذف</button>'}`);
    $('#save').onclick = async () => { try { await api(isNew ? '/admin/categories' : '/admin/categories/' + c.id, { method: isNew ? 'POST' : 'PATCH', body: val($('#cf')) }); toast('تم الحفظ'); closeDrawer(); vCategories(); } catch (e) { markErrors($('#cf'), e.details); fail(e); } };
    const reopen = all => { vCategories().then(() => edit(all.find(x => x.id === c.id))); };
    if ($('#cimg')) upload($('#cimg'), `/admin/categories/${c.id}/image`).then(reopen).catch(() => {});
    if ($('#cimgx')) $('#cimgx').onclick = async () => { const fdx = new FormData(); fdx.append('remove', '1'); try { const r = await api(`/admin/categories/${c.id}/image`, { method: 'POST', form: fdx }); toast('تم'); reopen(r.data); } catch (e) { fail(e); } };
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
  page().innerHTML = head('المستخدمون', '<button class="btn" id="addU">+ موظف / أمين مخزن / فني</button>') + `<div class="filters"><label class="search">${svg('search', 16)}<input id="uq" placeholder="الاسم، البريد، الهاتف"></label>
    <div class="seg" id="ur"><button data-r="" class="on">الكل</button><button data-r="customer">عملاء</button><button data-r="staff">موظفون</button><button data-r="storekeeper">أمناء مخزن</button><button data-r="technician">فنيون</button><button data-r="admin">مدراء</button></div></div>
    <div class="tbl"><table><thead><tr><th>المستخدم</th><th>الهاتف</th><th>الدور</th><th>الطلبات</th><th>آخر دخول</th><th>الحالة</th></tr></thead><tbody id="ub"></tbody></table></div>`;
  const load = async () => {
    const { data } = await api('/admin/users', { query: st });
    $('#ub').innerHTML = data.map(u => `<tr data-id="${u.id}"><td><div class="nm">${h(u.name)}</div><div class="sub ltr" style="text-align:right">${h(u.email)}</div></td><td class="ltr" style="text-align:right">${h(u.phone || '—')}</td>
      <td><span class="chip ${u.role === 'admin' ? 'ink' : (u.role === 'storekeeper' ? 'warn' : (u.role === 'technician' ? 'ok' : ''))}">${ROLE[u.role] || h(u.role)}</span></td><td class="num">${u.orders}</td><td class="sub">${fdt(u.last_login_at)}</td>
      <td>${u.status === 'active' ? '<span class="chip ok"><i></i>فعّال</span>' : '<span class="chip red"><i></i>معطّل</span>'}</td></tr>`).join('') || '<tr><td colspan="6"><div class="empty"><b>لا نتائج</b></div></td></tr>';
    $$('#ub tr[data-id]').forEach(tr => tr.onclick = () => edit(data.find(u => u.id === +tr.dataset.id)));
  };
  const edit = u => {
    const isNew = !u;
    drawer(isNew ? 'حساب جديد' : h(u.name), `<form class="fm" id="uf">
      ${isNew ? '<div class="f"><label>الاسم</label><input name="name"></div><div class="row"><div class="f"><label>البريد</label><input name="email" type="email" dir="ltr"></div><div class="f"><label>الهاتف</label><input name="phone" dir="ltr"></div></div>' : `<div class="row"><div class="f"><label>الاسم</label><input name="name" value="${h(u.name)}"></div><div class="f"><label>الهاتف</label><input name="phone" dir="ltr" value="${h(u.phone || '')}"></div></div><div class="info"><div><small>البريد</small><b class="ltr">${h(u.email)}</b></div><div><small>الشركة</small><b>${h(u.company || '—')}</b></div><div><small>تاريخ التسجيل</small><b>${fdt(u.created_at)}</b></div><div><small>الطلبات</small><b>${u.orders}</b></div></div>`}
      <div class="row"><div class="f"><label>الدور</label><select name="role">${Object.entries(ROLE).map(([k, v]) => `<option value="${k}" ${(u?.role || 'staff') === k ? 'selected' : ''}>${v}</option>`).join('')}</select></div>
      ${isNew ? '' : `<div class="f"><label>الحالة</label><select name="status"><option value="active" ${u.status === 'active' ? 'selected' : ''}>فعّال</option><option value="disabled" ${u.status === 'disabled' ? 'selected' : ''}>معطّل</option></select></div>`}</div>
      <div class="f"><label>${isNew ? 'كلمة المرور' : 'كلمة مرور جديدة (اتركها فارغة لعدم التغيير)'}</label><input name="password" type="password" autocomplete="new-password"></div>
      <div class="alert ok" style="font-size:12px"><b>الصلاحيات:</b><br>• مدير: كل شيء.<br>• موظف: الطلبات والأسعار، الكتالوج، البنرات، الماركات، الإشعارات، التسليم والإرجاع.<br>• أمين مخزن: عرض الطلبات بدون أسعار، تسليم وإرجاع المعدات بالتوقيع، تعديل كميات المعدات.<br>• فني: لا يدخل اللوحة — يظهر اسمه لاختياره كفني مرافق عند التسليم.</div>
      <p class="muted" style="font-size:12px">تغيير الدور أو الحالة أو كلمة المرور يُنهي كل جلسات المستخدم.</p></form>`, '<button class="btn" id="save">حفظ</button>');
    $('#save').onclick = async () => {
      const body = val($('#uf')); if (!body.password) delete body.password; if (!isNew && !body.phone) delete body.phone;
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
  const imgBox = (key, label, hint) => `<div class="imgbox"><div class="im wide">${s[key] ? `<img src="${h(s[key])}" alt="">` : '<span class="muted" style="font-size:11px">لا توجد</span>'}</div><div style="flex:1"><b style="font-size:13.5px">${label}</b><p class="muted" style="font-size:12px;margin:4px 0 8px">${hint}</p>
    <label class="btn lt sm" style="cursor:pointer">${s[key] ? 'تغيير' : 'رفع صورة'}<input type="file" accept="image/*" data-img="${key}" hidden data-skip="1"></label>${s[key] ? ` <button type="button" class="btn ghost sm" data-rm="${key}">إزالة</button>` : ''}</div></div>`;
  page().innerHTML = head('الإعدادات') + `<div class="setgrid">
    <div class="card"><h3>الواجهة الرئيسية</h3><form class="fm" id="hf">
      <div class="row"><div class="f"><label>العنوان الرئيسي</label><input name="home_title" value="${h(s.home_title)}" placeholder="ماذا ستصوّر"></div><div class="f"><label>السطر الثاني (بلون خافت)</label><input name="home_subtitle" value="${h(s.home_subtitle)}" placeholder="هذا الأسبوع؟"></div></div>
      ${imgBox('hero_image', 'صورة بطاقة الباقات', 'تظهر في الصفحة الرئيسية خلف بطاقة "أسطول وطاقم فني"')}
    </form></div>
    <div class="card"><h3>رسالة الترحيب <small>تظهر عند فتح التطبيق والموقع</small></h3><form class="fm" id="wf">
      <div class="checks"><label><input type="checkbox" id="wen" data-skip="1" ${s.welcome_enabled === '1' ? 'checked' : ''}>تفعيل رسالة الترحيب</label></div>
      <div class="f"><label>العنوان</label><input name="welcome_title" value="${h(s.welcome_title)}" maxlength="120"></div>
      <div class="f"><label>النص</label><textarea name="welcome_body" rows="3" maxlength="1000">${h(s.welcome_body)}</textarea></div>
      <div class="row"><div class="f"><label>نص الزر</label><input name="welcome_button" value="${h(s.welcome_button)}" maxlength="40"></div>
        <div class="f"><label>تظهر</label><select name="welcome_frequency"><option value="once" ${s.welcome_frequency === 'once' ? 'selected' : ''}>مرة واحدة لكل مستخدم</option><option value="daily" ${s.welcome_frequency === 'daily' ? 'selected' : ''}>مرة يومياً</option><option value="always" ${s.welcome_frequency === 'always' ? 'selected' : ''}>عند كل فتح</option></select></div></div>
      <div class="f"><label>رابط الزر (اختياري)</label><input name="welcome_link" dir="ltr" value="${h(s.welcome_link)}" placeholder="https://… أو اتركه فارغاً لإغلاق الرسالة فقط"></div>
      ${imgBox('welcome_image', 'صورة الرسالة', 'اختيارية — مقاس مقترح 1200×800')}
      <p class="muted" style="font-size:11.5px">أي تعديل على الرسالة يجعلها تظهر من جديد لكل المستخدمين.</p>
    </form></div>
    <div class="card" style="grid-column:1/-1"><h3>بيانات الشركة والتطبيق</h3><form class="fm" id="sf">
    <div class="row">${F.map(([k, l, ltr]) => `<div class="f"><label>${l}</label><input name="${k}" ${ltr ? 'dir="ltr"' : ''} value="${h(s[k])}"></div>`).join('')}</div>
    <div class="f"><label>العنوان</label><input name="address" value="${h(s.address)}"></div>
    <div class="checks"><label><input type="checkbox" id="sp" ${s.show_prices === '1' ? 'checked' : ''} data-skip="1">إظهار سعر اليوم للعملاء في الموقع والتطبيق</label></div>
    </form></div></div>
    <div class="card fbcard" id="fb" style="max-width:1100px;margin-top:14px"><div class="skel" style="height:80px"></div></div>
    <div class="savebar"><button class="btn" id="saveAll">حفظ كل الإعدادات</button></div>`;
  drawFirebase();
  $('#saveAll').onclick = async () => {
    const body = { ...val($('#sf')), ...val($('#hf')), ...val($('#wf')) };
    body.show_prices = $('#sp').checked ? '1' : '0';
    body.welcome_enabled = $('#wen').checked ? '1' : '0';
    try { await api('/admin/settings', { method: 'PUT', body }); toast('تم حفظ الإعدادات'); } catch (er) { fail(er); }
  };
  $$('[data-img]').forEach(inp => upload(inp, '/admin/settings/image', { key: inp.dataset.img }).then(() => vSettings()));
  $$('[data-rm]').forEach(b => b.onclick = async () => {
    const fdx = new FormData(); fdx.append('key', b.dataset.rm); fdx.append('remove', '1');
    try { await api('/admin/settings/image', { method: 'POST', form: fdx }); toast('تمت الإزالة'); vSettings(); } catch (e) { fail(e); }
  });
}

/* ---------- Firebase: الإشعارات الفورية ---------- */
async function drawFirebase() {
  const box = $('#fb'); if (!box) return;
  let f;
  try { f = (await api('/admin/firebase')).data; } catch (e) { box.innerHTML = `<div class="alert red">${h(e.message)}</div>`; return; }
  const P = { ios: 'iPhone', android: 'Android', web: 'ويب' };
  const devs = f.devices.length ? f.devices.map(d => `<span class="chip">${P[d.platform] || d.platform}: ${num(d.n)} جهاز${+d.users ? ` · ${num(d.users)} مسجّل` : ''} · ${num(d.promo)} يقبل العروض</span>`).join(' ') : '<span class="muted" style="font-size:12px">لا توجد أجهزة مسجّلة بعد — تُسجَّل تلقائياً عند فتح نسخة التطبيق المربوطة بـ Firebase</span>';
  box.innerHTML = `<h3>الإشعارات الفورية — Firebase ${f.configured ? '<span class="chip ok"><i></i>مفعّلة</span>' : '<span class="chip"><i></i>غير مفعّلة</span>'}</h3>
    ${f.configured ? `<div class="info" style="margin-bottom:12px"><div><small>المشروع</small><b class="ltr">${h(f.project_id)}</b></div><div><small>حساب الخدمة</small><b class="ltr" style="font-size:12px;word-break:break-all">${h(f.client_email)}</b></div></div>` :
      `<p class="muted" style="font-size:12.5px;line-height:1.9;margin-bottom:12px">حتى تصل الإشعارات للهاتف والتطبيق مغلق: Firebase Console ← ⚙️ Project settings ← <b>Service accounts</b> ← <b>Generate new private key</b>، ثم ارفع ملف JSON هنا. (الملف يُحفظ على السيرفر في مكان غير عام)</p>`}
    <div style="margin-bottom:12px">${devs}</div>
    ${!f.requirements.openssl || !f.requirements.curl ? '<div class="alert red" style="margin-bottom:10px">السيرفر يحتاج إضافات PHP: openssl و curl</div>' : ''}
    <div style="display:flex;gap:8px;flex-wrap:wrap">
      <label class="btn ${f.configured ? 'lt' : ''} sm" style="cursor:pointer">${f.configured ? 'استبدال ملف الخدمة' : 'رفع ملف الخدمة (JSON)'}<input type="file" accept=".json,application/json" id="fbFile" hidden></label>
      ${f.configured ? '<button class="btn sm" id="fbTest">اختبار الاتصال</button><button class="btn ghost sm" id="fbDel" style="color:var(--red)">إيقاف</button>' : ''}
    </div><div id="fbMsg" style="margin-top:10px"></div>`;
  $('#fbFile').onchange = async e => {
    const file = e.target.files[0]; if (!file) return;
    const fdx = new FormData(); fdx.append('file', file);
    try { await api('/admin/firebase', { method: 'POST', form: fdx }); toast('تم ربط Firebase ✓'); drawFirebase(); } catch (er) { fail(er); }
  };
  if ($('#fbTest')) $('#fbTest').onclick = async () => {
    $('#fbMsg').innerHTML = '<div class="alert warn">جاري الاتصال بـ Google…</div>';
    try {
      const { data } = await api('/admin/firebase/test', { method: 'POST' });
      $('#fbMsg').innerHTML = `<div class="alert ok">الاتصال بـ Firebase يعمل ✓ ${data.sent_to_my_devices ? `— أُرسل إشعار تجربة إلى ${data.sent_to_my_devices} من أجهزتك` : '— سجّل دخولك بالتطبيق بنفس حسابك لتصلك رسالة تجربة'}</div>`;
    } catch (er) { $('#fbMsg').innerHTML = `<div class="alert red">${h(er.message)}</div>`; }
  };
  if ($('#fbDel')) $('#fbDel').onclick = async () => { if (!confirm('إيقاف الإشعارات الفورية وحذف ملف الخدمة من السيرفر؟')) return; try { await api('/admin/firebase', { method: 'DELETE' }); drawFirebase(); } catch (er) { fail(er); } };
}

/* ---------- روابط البنرات والإشعارات ---------- */
const LINKS = { none: 'بدون رابط', category: 'قسم', brand: 'ماركة', equipment: 'معدة', kits: 'صفحة الباقات', url: 'رابط خارجي' };
async function linkPicker(form, type, value) {
  if (!S.cats.length) await loadCats().catch(() => {});
  if (!S.brands) S.brands = (await api('/admin/brands').catch(() => ({ data: [] }))).data;
  const box = $('.lnk', form);
  const draw = (t, v = '') => {
    let input = '';
    if (t === 'category') input = `<select name="link_value">${S.cats.map(c => `<option value="${h(c.slug)}" ${c.slug === v ? 'selected' : ''}>${h(c.name_ar)}</option>`).join('')}</select>`;
    else if (t === 'brand') input = `<select name="link_value">${S.brands.map(b => `<option value="${h(b.name)}" ${b.name === v ? 'selected' : ''}>${h(b.name)}</option>`).join('')}</select>`;
    else if (t === 'equipment') input = `<input name="link_value" dir="ltr" value="${h(v)}" placeholder="slug المعدة، مثل arri-alexa-35" list="eqSlugs"><datalist id="eqSlugs"></datalist>`;
    else if (t === 'url') input = `<input name="link_value" dir="ltr" value="${h(v)}" placeholder="https://">`;
    box.innerHTML = `<div class="row"><div class="f"><label>عند الضغط يفتح</label><select name="link_type">${Object.entries(LINKS).map(([k, l]) => `<option value="${k}" ${k === t ? 'selected' : ''}>${l}</option>`).join('')}</select></div>${input ? `<div class="f"><label>${LINKS[t]}</label>${input}</div>` : '<div></div>'}</div>`;
    $('[name=link_type]', box).onchange = e => draw(e.target.value);
    if (t === 'equipment') api('/admin/equipment', { query: { active: 1 } }).then(r => { const dl = $('#eqSlugs', box); if (dl) dl.innerHTML = r.data.map(e => `<option value="${h(e.slug)}">${h(e.brand + ' ' + e.name)}</option>`).join(''); }).catch(() => {});
  };
  draw(type || 'none', value || '');
}
function upload(input, url, extra = {}) {
  return new Promise((resolve, reject) => {
    input.onchange = async () => {
      const f = input.files[0]; if (!f) return;
      const fdx = new FormData(); fdx.append('image', f); Object.entries(extra).forEach(([k, v]) => fdx.append(k, v));
      toast('جاري رفع الصورة…');
      try { const r = await api(url, { method: 'POST', form: fdx }); toast('تم رفع الصورة'); resolve(r.data); } catch (e) { fail(e); reject(e); }
      input.value = '';
    };
  });
}

/* ---------- البنرات الإعلانية ---------- */
async function vBanners() {
  const { data: list } = await api('/admin/banners');
  page().innerHTML = head('البنرات الإعلانية', '<button class="btn" id="addB">+ بنر جديد</button>') + `
    <p class="muted" style="margin:-10px 0 16px;font-size:12.5px">تظهر كشرائح متحركة أعلى الصفحة الرئيسية في التطبيق والموقع. المقاس المقترح 1600×700 بكسل. البنر بدون صورة لا يظهر.</p>
    <div class="bgrid">${list.map((b, i) => `<div class="bcard ${b.is_active ? '' : 'off'}" data-id="${b.id}">
      <div class="bimg">${b.image ? `<img src="${h(b.image)}" alt="">` : '<span>بدون صورة</span>'}<div class="bov"><b>${h(b.title || '')}</b><small>${h(b.subtitle || '')}</small></div></div>
      <div class="bmeta"><span class="chip ${b.is_active ? 'ok' : ''}"><i></i>${b.is_active ? 'ظاهر' : 'مخفي'}</span><small>${LINKS[b.link_type]}${b.link_value ? ': ' + h(b.link_value) : ''}${b.ends_at ? ' · حتى ' + fd(b.ends_at) : ''}</small>
        <span class="mv"><button data-mv="-1" ${i ? '' : 'disabled'} aria-label="تقديم">▲</button><button data-mv="1" ${i < list.length - 1 ? '' : 'disabled'} aria-label="تأخير">▼</button></span></div></div>`).join('') || '<div class="empty"><b>لا توجد بنرات</b>أضف أول بنر إعلاني</div>'}</div>`;
  const edit = b => {
    const isNew = !b; b = b || { title: '', subtitle: '', button_text: '', link_type: 'none', is_active: true };
    const d = drawer(isNew ? 'بنر جديد' : 'تعديل البنر', `
      ${isNew ? '<div class="alert ok">احفظ البنر أولاً ثم ارفع صورته.</div>' : `<div class="bprev" id="bp">${b.image ? `<img src="${h(b.image)}" alt="">` : ''}<div class="bov"><b>${h(b.title || '')}</b><small>${h(b.subtitle || '')}</small>${b.button_text ? `<em>${h(b.button_text)}</em>` : ''}</div></div>
      <label class="btn lt sm" style="cursor:pointer;margin:10px 0 4px">${b.image ? 'تغيير الصورة' : 'رفع الصورة'}<input type="file" accept="image/*" id="bimg" hidden data-skip="1"></label>`}
      <form class="fm" id="bf" style="margin-top:10px">
        <div class="f"><label>العنوان (اختياري)</label><input name="title" value="${h(b.title || '')}" maxlength="120"></div>
        <div class="f"><label>النص الفرعي</label><input name="subtitle" value="${h(b.subtitle || '')}" maxlength="200"></div>
        <div class="f"><label>نص الزر (اختياري)</label><input name="button_text" value="${h(b.button_text || '')}" maxlength="40" placeholder="اطلب الآن"></div>
        <div class="lnk"></div>
        <div class="row"><div class="f"><label>يبدأ العرض (اختياري)</label><input type="date" name="starts_at" value="${b.starts_at || ''}"></div><div class="f"><label>ينتهي العرض (اختياري)</label><input type="date" name="ends_at" value="${b.ends_at || ''}"></div></div>
        <div class="checks"><label><input type="checkbox" name="is_active" ${b.is_active ? 'checked' : ''}>ظاهر</label></div>
      </form>`, `<button class="btn" id="save">${isNew ? 'إضافة' : 'حفظ'}</button>${isNew ? '' : '<button class="btn lt" id="del" style="flex:none;color:var(--red)">حذف</button>'}`);
    linkPicker($('#bf', d), b.link_type, b.link_value);
    if ($('#bimg')) upload($('#bimg'), `/admin/banners/${b.id}/image`).then(x => { edit(x); vBanners(); });
    $('#save').onclick = async () => {
      const body = val($('#bf'));
      try { const r = await api(isNew ? '/admin/banners' : '/admin/banners/' + b.id, { method: isNew ? 'POST' : 'PATCH', body }); toast('تم الحفظ'); vBanners(); if (isNew) edit(r.data); else closeDrawer(); }
      catch (e) { markErrors($('#bf'), e.details); fail(e); }
    };
    if ($('#del')) $('#del').onclick = async () => { if (!confirm('حذف البنر؟')) return; try { await api('/admin/banners/' + b.id, { method: 'DELETE' }); closeDrawer(); vBanners(); } catch (e) { fail(e); } };
  };
  $('#addB').onclick = () => edit(null);
  $$('.bcard').forEach(c => c.onclick = e => {
    const mv = e.target.closest('[data-mv]');
    if (mv) {
      e.stopPropagation();
      const ids = list.map(x => x.id), i = ids.indexOf(+c.dataset.id), j = i + +mv.dataset.mv;
      [ids[i], ids[j]] = [ids[j], ids[i]];
      api('/admin/banners/sort', { method: 'POST', body: { ids } }).then(vBanners).catch(fail);
      return;
    }
    edit(list.find(x => x.id === +c.dataset.id));
  });
}

/* ---------- الماركات ---------- */
async function vBrands() {
  const { data: list } = await api('/admin/brands');
  S.brands = list;
  page().innerHTML = head('الماركات / العلامات التجارية', '<button class="btn lt" id="syncB">مزامنة من المعدات</button><button class="btn" id="addBr">+ ماركة</button>') + `
    <p class="muted" style="margin:-10px 0 16px;font-size:12.5px">الماركات المميزة (★) تظهر في الواجهة الرئيسية للتطبيق والموقع مع شعارها، والضغط عليها يعرض معداتها. يُفضَّل شعار PNG بخلفية شفافة.</p>
    <div class="tbl"><table><thead><tr><th></th><th>الماركة</th><th>المعدات</th><th>الواجهة الرئيسية</th><th>الترتيب</th><th>الحالة</th></tr></thead><tbody>
    ${list.map(b => `<tr data-id="${b.id}"><td style="width:90px"><div class="logo-cell">${b.logo ? `<img src="${h(b.logo)}" alt="">` : `<span>${h(b.name.slice(0, 2))}</span>`}</div></td><td class="nm ltr" style="text-align:right">${h(b.name)}</td><td class="num">${b.count}</td>
      <td>${b.is_featured ? '<span class="chip ink">★ مميزة</span>' : '<span class="muted">—</span>'}</td><td class="num">${b.sort}</td><td>${b.is_active ? '<span class="chip ok"><i></i>ظاهرة</span>' : '<span class="chip"><i></i>مخفية</span>'}</td></tr>`).join('') || '<tr><td colspan="6"><div class="empty"><b>لا توجد ماركات</b>اضغط "مزامنة من المعدات"</div></td></tr>'}
    </tbody></table></div>`;
  const edit = b => {
    const isNew = !b; b = b || { name: '', sort: 100, is_active: true, is_featured: true };
    const d = drawer(isNew ? 'ماركة جديدة' : h(b.name), `
      ${isNew ? '' : `<div class="imgbox"><div class="im logo-cell">${b.logo ? `<img id="bl" src="${h(b.logo)}" alt="">` : `<span>${h(b.name.slice(0, 2))}</span>`}</div><div style="flex:1"><b style="font-size:13.5px">الشعار</b><p class="muted" style="font-size:12px;margin:4px 0 8px">PNG شفاف أو JPG — يُحسَّن تلقائياً</p><label class="btn lt sm" style="cursor:pointer">${b.logo ? 'تغيير الشعار' : 'رفع الشعار'}<input type="file" accept="image/*" id="blogo" hidden data-skip="1"></label></div></div>`}
      <form class="fm" id="brf" style="margin-top:14px"><div class="f"><label>اسم الماركة (كما يُكتب في المعدات)</label><input name="name" dir="ltr" value="${h(b.name)}"></div>
        <div class="f"><label>الترتيب (الأصغر أولاً)</label><input type="number" name="sort" value="${b.sort}"></div>
        <div class="checks"><label><input type="checkbox" name="is_featured" ${b.is_featured ? 'checked' : ''}>تظهر في الواجهة الرئيسية</label><label><input type="checkbox" name="is_active" ${b.is_active ? 'checked' : ''}>فعّالة</label></div>
        ${isNew ? '' : `<p class="muted" style="font-size:12px">${b.count} معدة بهذه الماركة. تغيير الاسم يُحدّث كل المعدات المرتبطة.</p>`}</form>`,
      `<button class="btn" id="save">حفظ</button>${isNew ? '' : '<button class="btn lt" id="del" style="flex:none;color:var(--red)">حذف</button>'}`);
    if ($('#blogo')) upload($('#blogo'), `/admin/brands/${b.id}/logo`).then(all => { vBrands(); edit(all.find(x => x.id === b.id)); });
    $('#save').onclick = async () => { try { const r = await api(isNew ? '/admin/brands' : '/admin/brands/' + b.id, { method: isNew ? 'POST' : 'PATCH', body: val($('#brf')) }); toast('تم الحفظ'); vBrands(); if (isNew) { const nb = r.data.find(x => x.name === val($('#brf')).name); nb ? edit(nb) : closeDrawer(); } else closeDrawer(); } catch (e) { markErrors($('#brf'), e.details); fail(e); } };
    if ($('#del')) $('#del').onclick = async () => { if (!confirm('حذف الماركة؟')) return; try { await api('/admin/brands/' + b.id, { method: 'DELETE' }); closeDrawer(); vBrands(); } catch (e) { fail(e); } };
  };
  $('#addBr').onclick = () => edit(null);
  $('#syncB').onclick = async () => { try { await api('/admin/brands/sync', { method: 'POST' }); toast('تمت المزامنة'); vBrands(); } catch (e) { fail(e); } };
  $$('tr[data-id]').forEach(tr => tr.onclick = () => edit(list.find(x => x.id === +tr.dataset.id)));
}

/* ---------- الإشعارات ---------- */
async function vNotifications(params) {
  const st = { type: params.get('type') || '' };
  page().innerHTML = head('الإشعارات') + `<div class="grid2 ntf">
    <div class="card"><h3>إرسال إشعار إعلاني <small>يصل لكل مستخدمي التطبيق</small></h3>
      <form class="fm" id="nf">
        <div class="f"><label>العنوان *</label><input name="title" maxlength="150" placeholder="مثلاً: خصم 20% على باقات الإضاءة"></div>
        <div class="f"><label>النص</label><textarea name="body" rows="3" maxlength="1000" placeholder="تفاصيل العرض…"></textarea></div>
        <div class="f"><label>صورة (اختياري)</label><input type="file" name="image" accept="image/*" data-skip="1" id="nimg"></div>
        <div class="lnk"></div>
        <div class="row"><div class="f"><label>النوع</label><select name="type"><option value="promo">إعلاني — للموافقين على العروض فقط</option><option value="info">تنبيه خدمة — لكل المستخدمين (بدون تسويق)</option></select></div><div></div></div>
        <button class="btn" id="nsend" type="submit">${svg('bell', 18)} إرسال الآن</button>
      </form></div>
    <div><div class="phone"><div class="pn-top">الآن · Ghani Group</div><div class="pn"><img src="assets/brand/mark.png" alt=""><div><b id="pvT">عنوان الإشعار</b><span id="pvB">نص الإشعار يظهر هنا</span></div></div><img id="pvI" class="pn-img" alt="" hidden></div>
      <div class="alert warn" style="margin-top:12px;font-size:12px">يظهر الإشعار داخل التطبيق (صندوق الإشعارات + تنبيه أعلى الشاشة عند فتح التطبيق)، وفي الموقع. إشعارات تغيّر حالة الطلب ومحاضر التسليم والإرجاع تُرسل للعميل تلقائياً.</div></div>
  </div>
  <div class="filters" style="margin-top:18px"><div class="seg" id="nt"><button data-t="">الكل</button><button data-t="promo">إعلانية</button><button data-t="order">الطلبات</button><button data-t="info">تنبيهات</button></div></div>
  <div class="tbl"><table><thead><tr><th>الإشعار</th><th>النوع</th><th>إلى</th><th>الوقت</th><th></th></tr></thead><tbody id="nb"></tbody></table></div>`;
  const nf = $('#nf');
  linkPicker(nf, 'none', '');
  const pv = () => { $('#pvT').textContent = nf.title.value || 'عنوان الإشعار'; $('#pvB').textContent = nf.body.value || 'نص الإشعار يظهر هنا'; };
  nf.title.oninput = nf.body.oninput = pv;
  $('#nimg').onchange = e => { const f = e.target.files[0]; const im = $('#pvI'); if (f) { im.src = URL.createObjectURL(f); im.hidden = false; } else im.hidden = true; };
  const TY = { promo: ['إعلاني', 'ink'], order: ['طلب', 'ok'], info: ['تنبيه', 'warn'] };
  const load = async () => {
    $$('#nt button').forEach(b => b.classList.toggle('on', b.dataset.t === st.type));
    const { data } = await api('/admin/notifications', { query: { type: st.type } });
    $('#nb').innerHTML = data.map(n => `<tr style="cursor:default"><td><div class="nm">${h(n.title)}</div><div class="sub">${h((n.body || '').slice(0, 120))}</div></td><td><span class="chip ${TY[n.type][1]}">${TY[n.type][0]}</span></td>
      <td class="sub">${n.broadcast ? 'الجميع' : (n.order_ref ? `<span class="ltr">${h(n.order_ref)}</span>` : '')}${n.user_name ? ' · ' + h(n.user_name) : ''}</td><td class="sub">${fdt(n.created_at)}${n.by_name ? '<br>' + h(n.by_name) : ''}</td>
      <td><button class="btn lt sm" data-del="${n.id}">حذف</button></td></tr>`).join('') || '<tr><td colspan="5"><div class="empty"><b>لا توجد إشعارات</b></div></td></tr>';
    $$('[data-del]').forEach(b => b.onclick = async () => { if (!confirm('حذف الإشعار؟ سيختفي من صندوق إشعارات المستخدمين.')) return; try { await api('/admin/notifications/' + b.dataset.del, { method: 'DELETE' }); load(); } catch (e) { fail(e); } });
  };
  $$('#nt button').forEach(b => b.onclick = () => { st.type = b.dataset.t; load(); });
  nf.onsubmit = async e => {
    e.preventDefault();
    if (!nf.title.value.trim()) { toast('اكتب عنوان الإشعار', true); return; }
    if (!confirm('إرسال هذا الإشعار لكل المستخدمين؟')) return;
    const fdx = new FormData();
    Object.entries(val(nf)).forEach(([k, v]) => fdx.append(k, v));
    if ($('#nimg').files[0]) fdx.append('image', $('#nimg').files[0]);
    $('#nsend').disabled = true;
    try { const r = await api('/admin/notifications', { method: 'POST', form: fdx }); toast(r.data.push ? 'تم الإرسال — داخل التطبيق + إشعار فوري للهواتف ✓' : 'تم الإرسال داخل التطبيق ✓ (فعّل Firebase من الإعدادات للإشعارات الفورية)'); nf.reset(); linkPicker(nf, 'none', ''); $('#pvI').hidden = true; pv(); load(); }
    catch (er) { markErrors(nf, er.details); fail(er); }
    $('#nsend').disabled = false;
  };
  await load();
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
    if (r.data && ['admin', 'staff', 'storekeeper'].includes(r.data.role)) { S.user = r.data; shell(); return; }
  } catch (e) { /* not logged in */ }
  renderLogin();
})();
})();
