/* Ghani Group Rental — Web app (vanilla JS, يتصل بالـ API) */
(() => {
'use strict';

const BASE = document.querySelector('base')?.getAttribute('href') || '/';
const API = BASE + 'api/v1';
const app = document.getElementById('app');
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const h = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const cookie = n => { const m = document.cookie.match('(?:^|; )' + n + '=([^;]*)'); return m ? decodeURIComponent(m[1]) : ''; };
const DAYS_AR = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const MONTHS_AR = ['كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'];
const ymd = d => d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
const fmtDate = s => { if (!s) return ''; const d = new Date(s + 'T00:00:00'); return d.getDate() + ' ' + MONTHS_AR[d.getMonth()]; };
const STATUS = {
  pending: ['بانتظار المراجعة', 'warn', 15], quoted: ['تم إرسال عرض السعر', 'ink', 35],
  confirmed: ['مؤكد', 'ok', 60], out: ['تم الاستلام', 'ok', 85], returned: ['مكتمل', '', 100], cancelled: ['ملغي', 'red', 100],
};

const I = {
  plus: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M8 3v10M3 8h10"/></svg>',
  check: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2"><path d="m3 8.5 3 3 7-7"/></svg>',
  back: '<svg viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="1.8"><path d="m7 4 5 5-5 5"/></svg>',
  arrow: '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M11 4 6 9l5 5"/></svg>',
  heart: '<svg viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M9 15S2.5 11.3 2.5 6.8A3.3 3.3 0 0 1 9 5.4a3.3 3.3 0 0 1 6.5 1.4C15.5 11.3 9 15 9 15z"/></svg>',
  search: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="9" cy="9" r="6"/><path d="m14 14 4 4"/></svg>',
  ok: '<svg width="34" height="34" viewBox="0 0 34 34" fill="none" stroke="currentColor" stroke-width="2.6"><path d="m8 17 6 6 12-12"/></svg>',
};

/* ---------------- API ---------------- */
const memo = new Map();
async function api(path, { method = 'GET', body, query, cache = false } = {}) {
  const url = new URL(API + path, location.href);
  if (query) Object.entries(query).forEach(([k, v]) => { if (v !== '' && v != null) url.searchParams.set(k, v); });
  const key = url.toString();
  if (cache && method === 'GET' && memo.has(key)) return memo.get(key);
  const headers = { 'X-Client': 'web', Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (method !== 'GET') { const c = cookie('gg_csrf'); if (c) headers['X-CSRF-Token'] = c; }
  let res;
  try {
    res = await fetch(url, { method, headers, credentials: 'same-origin', body: body !== undefined ? JSON.stringify(body) : undefined });
  } catch (e) { throw Object.assign(new Error('تعذر الاتصال بالسيرفر، تحقق من الإنترنت'), { status: 0 }); }
  const j = await res.json().catch(() => ({ ok: false, error: { message: 'استجابة غير متوقعة' } }));
  if (!j.ok) throw Object.assign(new Error(j.error?.message || 'خطأ'), { status: res.status, code: j.error?.code, details: j.error?.details || {} });
  if (cache && method === 'GET') memo.set(key, j);
  return j;
}

/* ---------------- state ---------------- */
const store = {
  get(k, d) { try { const v = localStorage.getItem('gg_' + k); return v ? JSON.parse(v) : d; } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem('gg_' + k, JSON.stringify(v)); } catch (e) { /* storage unavailable */ } },
};
const S = { user: null, settings: {}, cats: [], favs: new Set(), cart: store.get('cart', { items: {}, start: '', end: '' }) };
if (!S.cart.items) S.cart = { items: {}, start: '', end: '' };

const cartCount = () => Object.values(S.cart.items).reduce((a, b) => a + b.qty, 0);
function saveCart() {
  store.set('cart', S.cart);
  const n = cartCount();
  $$('[data-count]').forEach(el => { el.textContent = n; el.classList.toggle('on', n > 0); });
}
function inCart(slug) { return S.cart.items[slug]?.qty || 0; }
function addToCart(it, qty = 1) {
  S.cart.items[it.slug] = { id: it.id, slug: it.slug, name: it.name, brand: it.brand, image: it.image, max: it.qty_total, qty: Math.min(it.qty_total, qty) };
  saveCart();
}
function toggleCart(it) {
  if (inCart(it.slug)) { delete S.cart.items[it.slug]; saveCart(); toast('أزيلت من الطلب', it.image); return false; }
  addToCart(it, 1); toast(it.name + ' أضيفت للطلب', it.image); return true;
}

/* ---------------- ui helpers ---------------- */
let toastT;
function toast(msg, img = '') {
  $('#toastMsg').textContent = msg;
  $('#toastImg').src = img || '';
  $('#toast').classList.add('on');
  clearTimeout(toastT);
  toastT = setTimeout(() => $('#toast').classList.remove('on'), 2200);
}
function openSheet(html) {
  $('#sheet').innerHTML = '<div class="gb"></div>' + html;
  $('#scrim').classList.add('on');
  $('#sheet').classList.add('on');
}
function closeSheet() { $('#scrim').classList.remove('on'); $('#sheet').classList.remove('on'); }
$('#scrim').onclick = closeSheet;
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeSheet(); });

function card(it) {
  const on = inCart(it.slug) > 0;
  return `<article class="cd">
    ${it.is_new ? '<span class="tagn">جديد</span>' : ''}
    <a href="#/item/${h(it.slug)}" class="ph"><img src="${h(it.image || '')}" alt="${h(it.name)}" loading="lazy"></a>
    <div class="br">${h(it.brand)}</div>
    <a href="#/item/${h(it.slug)}" class="nm">${h(it.name)}</a>
    <div class="ft"><span class="qty">في الأسطول <b>${it.qty_total}</b></span>
      <button class="plus ${on ? 'on' : ''}" data-add="${h(it.slug)}" aria-label="أضف للطلب">${on ? I.check : I.plus}</button></div>
  </article>`;
}
const itemCache = new Map();
function bindCards(root, items) {
  items.forEach(i => itemCache.set(i.slug, i));
  $$('[data-add]', root).forEach(b => b.onclick = () => {
    const it = itemCache.get(b.dataset.add);
    const on = toggleCart(it);
    b.classList.toggle('on', on);
    b.innerHTML = on ? I.check : I.plus;
  });
}
const skelGrid = n => `<div class="grid">${'<div class="skel" style="height:250px"></div>'.repeat(n)}</div>`;
function errorView(e) {
  return `<div class="wrap page"><div class="empty"><h3>تعذر التحميل</h3><p>${h(e.message)}</p><button class="btn sm" style="margin-top:16px" onclick="location.reload()">إعادة المحاولة</button></div></div>`;
}
function setNav(name) {
  $$('[data-nav]').forEach(a => a.classList.toggle('on', a.dataset.nav === name));
  $('#accBtn').classList.toggle('on', name === 'account');
  document.body.classList.toggle('on-item', name === 'item');
  $('#bnav').classList.toggle('hide', name === 'item');
}
function fieldErrors(form, details) {
  $$('.fld', form).forEach(f => f.classList.remove('err'));
  Object.keys(details || {}).forEach(k => {
    const el = form.querySelector(`[name="${k}"]`);
    if (el) { const f = el.closest('.fld'); if (f) { f.classList.add('err'); const l = f.querySelector('label'); if (l && !l.dataset.o) { l.dataset.o = l.textContent; } if (l) l.textContent = l.dataset.o + ' — ' + details[k]; } }
  });
}

/* ---------------- views ---------------- */
async function viewHome() {
  setNav('home');
  app.innerHTML = `<div class="wrap page">${skelGrid(4)}</div>`;
  const [cats, feat, neu, kits] = await Promise.all([
    api('/categories', { cache: true }), api('/equipment', { query: { featured: 1, per_page: 8 } }),
    api('/equipment', { query: { new: 1, per_page: 8 } }), api('/kits', { cache: true }),
  ]);
  S.cats = cats.data;
  const hero = S.settings.hero_image;
  app.innerHTML = `<div class="wrap page">
    <section class="hero-a">
      <div>
        <h1 class="h1">ماذا ستصوّر<br><span>هذا الأسبوع؟</span></h1>
        <form class="srch" id="homeSearch">${I.search}<input name="q" placeholder="ابحث عن كاميرا، عدسة، إضاءة…" aria-label="بحث"><button class="go" aria-label="بحث">${I.arrow}</button></form>
      </div>
      <a class="banner" href="#/kits">${hero ? `<img src="${h(hero)}" alt="">` : ''}
        <div class="t"><div><small>${h((S.settings.company_name || 'GHANI GROUP').toUpperCase())} · FILM PRODUCTION</small><h3>أسطول وطاقم فني<br>من التحضير حتى التسليم</h3></div><span class="go">${I.arrow}</span></div></a>
    </section>
    ${installCard()}
    <div class="sec"><h2>الأقسام</h2><a href="#/browse">عرض الكل</a></div>
    <div class="deps">${cats.data.map(c => `<a class="dp" href="#/browse?cat=${h(c.slug)}"><div class="ph"><img src="${h(c.image || '')}" alt=""></div>${h(c.name_ar)}<small>${c.count} معدة</small></a>`).join('')}</div>
    <div class="sec"><h2>الأكثر طلباً</h2><a href="#/browse">عرض الكل</a></div>
    <div class="grid" id="feat">${feat.data.map(card).join('')}</div>
    ${kits.data.length ? `<div class="sec"><h2>باقات جاهزة</h2><a href="#/kits">كل الباقات</a></div><div class="kits" id="kits">${kits.data.map(kitCard).join('')}</div>` : ''}
    ${neu.data.length ? `<div class="sec"><h2>وصل حديثاً</h2><a href="#/browse?cat=light">الإضاءة</a></div><div class="grid" id="neu">${neu.data.map(card).join('')}</div>` : ''}
  </div>`;
  bindCards(app, [...feat.data, ...neu.data]);
  bindKits(kits.data);
  bindInstall();
  $('#homeSearch').onsubmit = e => { e.preventDefault(); location.hash = '#/browse?q=' + encodeURIComponent(e.target.q.value.trim()); };
}

function kitCard(k, i) {
  const all = k.items.length && k.items.every(x => inCart(x.slug));
  return `<div class="kt"><img src="${h(k.image || '')}" alt=""><div><h4>${h(k.name_ar)}</h4><p>${k.items.length} قطع · <span class="ltr">${h(k.name_en)}</span></p><button data-kit="${i}" class="${all ? 'on' : ''}">${all ? 'مضافة' : 'أضف الباقة'}</button></div></div>`;
}
function bindKits(kits) {
  $$('[data-kit]').forEach(b => b.onclick = () => {
    const k = kits[+b.dataset.kit];
    k.items.forEach(it => { if (!inCart(it.slug)) addToCart(it, it.qty || 1); });
    b.textContent = 'مضافة'; b.classList.add('on');
    toast(k.name_ar + ' أضيفت للطلب', k.image);
  });
}

async function viewKits() {
  setNav('kits');
  app.innerHTML = `<div class="wrap page">${skelGrid(4)}</div>`;
  const kits = await api('/kits', { cache: true });
  app.innerHTML = `<div class="wrap page"><h1 class="ttl">باقات جاهزة</h1><p class="muted" style="font-size:14px">مجموعات معدات مجرّبة لأنواع التصوير الأكثر طلباً. أضف الباقة كاملة ثم عدّل الكميات من صفحة الطلب.</p>
    ${kits.data.map((k, i) => `<div class="sec"><h2>${h(k.name_ar)} <small class="muted ltr" style="font-weight:400;font-size:13px">${h(k.name_en)}</small></h2><button class="btn sm" data-kit="${i}">أضف الباقة</button></div>
      <div class="grid">${k.items.map(card).join('')}</div>`).join('')}</div>`;
  bindKits(kits.data);
  bindCards(app, kits.data.flatMap(k => k.items));
}

async function viewBrowse(params) {
  setNav('browse');
  const st = { cat: params.get('cat') || '', q: params.get('q') || '', sort: params.get('sort') || 'default', page: 1, items: [] };
  const cats = (await api('/categories', { cache: true })).data;
  const total = cats.reduce((a, c) => a + c.count, 0);
  app.innerHTML = `<div class="wrap page">
    <h1 class="ttl">تصفّح المعدات</h1>
    <form class="srch" id="bSearch" style="margin-top:12px">${I.search}<input name="q" value="${h(st.q)}" placeholder="ALEXA، SkyPanel، Dolly…" aria-label="بحث"></form>
    <div class="pills">${[{ slug: '', name_ar: 'الكل', count: total }, ...cats].map(c => `<button class="pl ${st.cat === c.slug ? 'on' : ''}" data-cat="${h(c.slug)}">${h(c.name_ar)}<i>${c.count}</i></button>`).join('')}</div>
    <div class="tools"><span id="cnt"></span><select id="sort" aria-label="الترتيب"><option value="default">الأبرز</option><option value="name">الاسم</option><option value="brand">الماركة</option><option value="newest">الأحدث</option></select></div>
    <div class="grid g5" id="res">${'<div class="skel" style="height:250px"></div>'.repeat(8)}</div>
    <div class="more" id="more"></div></div>`;
  $('#sort').value = st.sort;
  const sync = () => { const p = new URLSearchParams(); if (st.cat) p.set('cat', st.cat); if (st.q) p.set('q', st.q); if (st.sort !== 'default') p.set('sort', st.sort); history.replaceState(null, '', '#/browse' + (p.toString() ? '?' + p : '')); };
  async function load(reset) {
    if (reset) { st.page = 1; st.items = []; $('#res').innerHTML = '<div class="skel" style="height:250px"></div>'.repeat(4); }
    const r = await api('/equipment', { query: { category: st.cat, q: st.q, sort: st.sort, page: st.page, per_page: 20 } });
    st.items.push(...r.data);
    $('#cnt').textContent = r.meta.total + ' معدة';
    $('#res').innerHTML = st.items.length ? st.items.map(card).join('') : `<div class="empty" style="grid-column:1/-1"><h3>لا توجد نتائج</h3><p>جرّب كلمة بحث أخرى أو قسماً آخر.</p></div>`;
    bindCards($('#res'), st.items);
    $('#more').innerHTML = r.meta.page < r.meta.pages ? '<button class="btn lt sm" id="moreBtn">عرض المزيد</button>' : '';
    if ($('#moreBtn')) $('#moreBtn').onclick = () => { st.page++; load(false); };
  }
  $$('[data-cat]').forEach(b => b.onclick = () => { st.cat = b.dataset.cat; $$('[data-cat]').forEach(x => x.classList.toggle('on', x === b)); sync(); load(true); });
  let t;
  $('#bSearch').oninput = e => { clearTimeout(t); t = setTimeout(() => { st.q = e.target.value.trim(); sync(); load(true); }, 300); };
  $('#bSearch').onsubmit = e => e.preventDefault();
  $('#sort').onchange = e => { st.sort = e.target.value; sync(); load(true); };
  await load(true);
}

async function viewItem(slug) {
  setNav('item');
  app.innerHTML = `<div class="wrap page"><div class="skel" style="height:360px;margin-top:10px"></div></div>`;
  const [r, av] = await Promise.all([api('/equipment/' + encodeURIComponent(slug)), api('/equipment/' + encodeURIComponent(slug) + '/availability', { query: { days: 21 } })]);
  const it = r.data;
  itemCache.set(it.slug, it);
  document.title = it.name + ' — Ghani Group';
  const days = av.data.days;
  const imgs = [it.image, ...(it.gallery || [])].filter(Boolean);
  const freeToday = days[0]?.available ?? it.qty_total;
  let qty = Math.max(1, inCart(it.slug) || 1), sel = [];
  if (S.cart.start) { const a = days.findIndex(d => d.date === S.cart.start), b = days.findIndex(d => d.date === S.cart.end); if (a >= 0 && b >= a) sel = [a, b]; }
  const specs = Object.entries(it.specs || {});

  app.innerHTML = `<div class="wrap page item"><div class="item-grid">
    <div class="dimg">
      <div class="dnav"><button class="cb" id="back" aria-label="رجوع">${I.back}</button><button class="cb ${S.favs.has(it.slug) ? 'on' : ''}" id="fav" aria-label="المفضلة">${I.heart}</button></div>
      <img id="mainImg" src="${h(imgs[0] || '')}" alt="${h(it.name)}">
      ${imgs.length > 1 ? `<div class="thumbs">${imgs.map((s, i) => `<button class="${i ? '' : 'on'}" data-img="${h(s)}"><img src="${h(s)}" alt=""></button>`).join('')}</div>` : ''}
    </div>
    <div class="dbody">
      <div class="br">${h(it.brand)} · ${h(it.category.name_ar)}</div>
      <h1>${h(it.name)}</h1>
      <span class="avl ${freeToday ? '' : 'no'}"><i></i>${freeToday ? `متوفر اليوم ${freeToday} من ${it.qty_total}` : 'محجوز اليوم — اختر أياماً أخرى'}</span>
      ${it.description ? `<p>${h(it.description)}</p>` : ''}
      ${specs.length ? `<div class="specs">${specs.map(([k, v]) => `<div class="sp"><small>${h(k)}</small><b>${h(v)}</b></div>`).join('')}</div>` : ''}
      <div class="sec"><h2>أيام الحجز</h2><span class="muted" id="dl" style="font-size:13px">اختر يوم الاستلام ثم الإرجاع</span></div>
      <div class="cal" id="cal"></div>
      <div class="opts">
        <div class="opt"><div><h4>فني / مشغّل مع المعدة</h4><p>يُضاف إلى ملاحظات الطلب</p></div><button class="sw ${S.cart.technician ? 'on' : ''}" id="sw1" aria-label="فني"></button></div>
        <div class="opt"><div><h4>توصيل إلى الموقع</h4><p>داخل بغداد</p></div><button class="sw ${S.cart.delivery ? 'on' : ''}" id="sw2" aria-label="توصيل"></button></div>
      </div>
      <div class="dock"><div class="stp"><button id="qp" aria-label="زيادة">+</button><span id="qv">${qty}</span><button id="qm" aria-label="إنقاص">−</button></div>
        <button class="btn" id="addB">${inCart(it.slug) ? 'تحديث الطلب' : 'أضف للطلب'} <small id="dd"></small></button></div>
    </div></div>
    ${it.related?.length ? `<div class="sec"><h2>من نفس القسم</h2><a href="#/browse?cat=${h(it.category.slug)}">عرض الكل</a></div><div class="grid g5">${it.related.map(card).join('')}</div>` : ''}
  </div>`;
  bindCards(app, it.related || []);
  $('#back').onclick = () => (history.length > 1 ? history.back() : (location.hash = '#/browse'));
  $$('[data-img]').forEach(b => b.onclick = () => { $('#mainImg').src = b.dataset.img; $$('[data-img]').forEach(x => x.classList.toggle('on', x === b)); });

  const maxFree = () => sel.length ? Math.min(...days.slice(sel[0], (sel[1] ?? sel[0]) + 1).map(d => d.available)) : it.qty_total;
  function drawCal() {
    $('#cal').innerHTML = days.map((d, i) => {
      const dt = new Date(d.date + 'T00:00:00');
      let c = d.available <= 0 ? 'bk' : '';
      if (sel.includes(i)) c = 'sel'; else if (sel.length === 2 && i > sel[0] && i < sel[1]) c = 'mid';
      return `<button class="dy ${c}" data-i="${i}" ${d.available <= 0 ? 'disabled' : ''}><small>${DAYS_AR[dt.getDay()]}</small><b>${dt.getDate()}</b><em>${d.available <= 0 ? 'محجوز' : d.available + ' متاح'}</em></button>`;
    }).join('');
    $$('#cal .dy').forEach(b => b.onclick = () => {
      const i = +b.dataset.i;
      if (sel.length !== 1) sel = [i];
      else {
        const lo = Math.min(sel[0], i), hi = Math.max(sel[0], i);
        sel = days.slice(lo, hi + 1).some(d => d.available <= 0) ? (toast('يوجد يوم محجوز ضمن المدة'), [i]) : [lo, hi];
      }
      drawCal();
    });
    const n = sel.length === 2 ? sel[1] - sel[0] + 1 : sel.length;
    $('#dl').textContent = n ? `${n} يوم · ${fmtDate(days[sel[0]].date)}${n > 1 ? ' ← ' + fmtDate(days[sel[1]].date) : ''}` : 'اختر يوم الاستلام ثم الإرجاع';
    $('#dd').textContent = n ? '· ' + n + ' يوم' : '';
    if (qty > maxFree()) { qty = Math.max(1, maxFree()); $('#qv').textContent = qty; }
  }
  drawCal();
  $('#qp').onclick = () => { const m = maxFree(); if (qty >= m) return toast('أقصى كمية متاحة: ' + m); qty++; $('#qv').textContent = qty; };
  $('#qm').onclick = () => { qty = Math.max(1, qty - 1); $('#qv').textContent = qty; };
  $('#sw1').onclick = e => { S.cart.technician = !S.cart.technician; e.currentTarget.classList.toggle('on', S.cart.technician); saveCart(); };
  $('#sw2').onclick = e => { S.cart.delivery = !S.cart.delivery; e.currentTarget.classList.toggle('on', S.cart.delivery); saveCart(); };
  $('#fav').onclick = async e => {
    if (!S.user) return toast('سجّل الدخول لحفظ المفضلة');
    const on = !S.favs.has(it.slug);
    try {
      await api('/me/favorites/' + it.slug, { method: on ? 'POST' : 'DELETE' });
      on ? S.favs.add(it.slug) : S.favs.delete(it.slug);
      e.currentTarget.classList.toggle('on', on);
      toast(on ? 'أضيفت إلى المفضلة' : 'أزيلت من المفضلة', it.image);
    } catch (err) { toast(err.message); }
  };
  $('#addB').onclick = () => {
    if (sel.length) { S.cart.start = days[sel[0]].date; S.cart.end = days[sel[1] ?? sel[0]].date; }
    addToCart(it, qty);
    toast(it.name + ' أضيفت للطلب', it.image);
    $('#addB').firstChild.textContent = 'تحديث الطلب ';
  };
}

async function viewOrder() {
  setNav('order');
  const items = Object.values(S.cart.items);
  if (!items.length) {
    app.innerHTML = `<div class="wrap page"><h1 class="ttl">الطلب</h1><div class="empty"><h3>طلبك فارغ</h3><p>أضف معدات أو باقة جاهزة<br>ونرسل لك عرض السعر.</p><a class="btn" style="margin-top:22px" href="#/browse">تصفّح المعدات</a></div></div>`;
    return;
  }
  const today = ymd(new Date());
  const u = S.user || {};
  app.innerHTML = `<div class="wrap page"><h1 class="ttl">الطلب</h1><div style="height:14px"></div>
    <div class="order-grid">
      <div id="lines">${items.map(i => `<div class="oi" data-s="${h(i.slug)}"><a class="ph" href="#/item/${h(i.slug)}"><img src="${h(i.image || '')}" alt=""></a><div class="t"><b>${h(i.name)}</b><small>${h(i.brand)}</small></div>
        <div class="stp"><button data-q="1" aria-label="زيادة">+</button><span>${i.qty}</span><button data-q="-1" aria-label="إنقاص">−</button></div></div>`).join('')}
        <div class="sum"><span>${cartCount()} قطعة</span><button class="muted" id="clr" style="font-size:13px">إفراغ الطلب</button></div>
      </div>
      <form class="side" id="of" novalidate>
        <div class="sec" style="padding-top:0"><h2>تفاصيل التصوير</h2></div>
        <div class="form">
          <div class="f2"><div class="fld"><label>تاريخ الاستلام</label><input type="date" name="start_date" min="${today}" value="${h(S.cart.start || '')}" required></div>
          <div class="fld"><label>تاريخ الإرجاع</label><input type="date" name="end_date" min="${today}" value="${h(S.cart.end || '')}" required></div></div>
          <div class="fld"><label>اسم المشروع</label><input name="project" maxlength="150" placeholder="مثلاً: إعلان حملة الشتاء"></div>
          <div class="fld"><label>موقع التصوير</label><input name="location" maxlength="190" placeholder="بغداد — المنصور"></div>
        </div>
        <div class="opts">
          <div class="opt"><div><h4>فني / مشغّل مع المعدات</h4></div><button type="button" class="sw ${S.cart.technician ? 'on' : ''}" data-sw="technician"></button></div>
          <div class="opt"><div><h4>توصيل إلى الموقع</h4></div><button type="button" class="sw ${S.cart.delivery ? 'on' : ''}" data-sw="delivery"></button></div>
        </div>
        <div class="sec"><h2>بيانات التواصل</h2></div>
        <div class="form">
          <div class="fld"><label>الاسم</label><input name="contact_name" maxlength="120" value="${h(u.name || '')}" required autocomplete="name"></div>
          <div class="fld"><label>رقم الهاتف</label><input name="phone" type="tel" dir="ltr" style="text-align:right" value="${h(u.phone || '')}" required autocomplete="tel" placeholder="07xx xxx xxxx"></div>
          <div class="fld"><label>البريد (اختياري)</label><input name="email" type="email" dir="ltr" style="text-align:right" value="${h(u.email || '')}" autocomplete="email"></div>
          <div class="fld"><label>ملاحظات</label><textarea name="notes" rows="2" maxlength="2000"></textarea></div>
        </div>
        <input class="hp" name="website" tabindex="-1" autocomplete="off" aria-hidden="true">
        <div class="sum"><span>التسعير</span><b>عرض سعر رسمي من قسم التأجير</b></div>
        <button class="btn red block" style="margin-top:16px" id="sendB">إرسال طلب عرض السعر</button>
        ${S.user ? '' : '<p class="muted" style="font-size:12px;margin-top:10px;text-align:center">لديك حساب؟ <a href="#/account" style="text-decoration:underline">سجّل الدخول</a> لمتابعة طلباتك.</p>'}
      </form>
    </div></div>`;
  $$('#lines .oi').forEach(row => $$('[data-q]', row).forEach(b => b.onclick = () => {
    const it = S.cart.items[row.dataset.s];
    it.qty += +b.dataset.q;
    if (it.qty > it.max) { it.qty = it.max; toast('الحد الأقصى في الأسطول: ' + it.max); }
    if (it.qty <= 0) delete S.cart.items[row.dataset.s];
    saveCart(); viewOrder();
  }));
  $('#clr').onclick = () => { if (confirm('إفراغ الطلب بالكامل؟')) { S.cart = { items: {}, start: '', end: '' }; saveCart(); viewOrder(); } };
  $$('[data-sw]').forEach(b => b.onclick = () => { const k = b.dataset.sw; S.cart[k] = !S.cart[k]; b.classList.toggle('on', S.cart[k]); saveCart(); });
  const f = $('#of');
  ['start_date', 'end_date'].forEach(n => f[n].onchange = () => { S.cart.start = f.start_date.value; S.cart.end = f.end_date.value; if (f.end_date.value < f.start_date.value) f.end_date.value = f.start_date.value; saveCart(); });
  f.onsubmit = async e => {
    e.preventDefault();
    const body = Object.fromEntries(new FormData(f).entries());
    if (!body.end_date) body.end_date = body.start_date;
    body.technician = !!S.cart.technician; body.delivery = !!S.cart.delivery;
    body.items = Object.values(S.cart.items).map(i => ({ slug: i.slug, qty: i.qty }));
    const btn = $('#sendB'); btn.disabled = true; btn.textContent = 'جاري الإرسال…';
    try {
      const r = await api('/orders', { method: 'POST', body });
      const o = r.data;
      const lines = o.items.map(i => `- ${i.brand} ${i.name} ×${i.qty}`).join('\n');
      const waText = `طلب عرض سعر ${o.ref}\n${o.project ? 'المشروع: ' + o.project + '\n' : ''}${fmtDate(o.start_date)} ← ${fmtDate(o.end_date)}\n${lines}`;
      const wa = S.settings.whatsapp ? `https://wa.me/${encodeURIComponent(S.settings.whatsapp)}?text=${encodeURIComponent(waText)}` : '';
      store.set('last_order', { ref: o.ref, phone: o.phone });
      S.cart = { items: {}, start: '', end: '' }; saveCart();
      openSheet(`<div class="ok">${I.ok}</div><h3>وصل طلبك</h3>
        <p>رقم الطلب <b class="ltr">${h(o.ref)}</b><br>سيراجع قسم التأجير التوفر ويرسل لك عرض السعر.</p>
        ${o.availability_warnings?.length ? `<div class="warnlist">تنبيه: بعض المعدات محجوزة جزئياً في هذه الفترة وسيتواصل معك الفريق لاقتراح بديل:<br>${o.availability_warnings.map(w => `• ${h(w.name)} — المتاح ${w.available} من ${w.requested}`).join('<br>')}</div>` : ''}
        ${wa ? `<a class="btn" href="${h(wa)}" target="_blank" rel="noopener">متابعة عبر واتساب</a>` : ''}
        <a class="btn lt" href="${S.user ? '#/account' : '#/track?ref=' + encodeURIComponent(o.ref)}" id="afterB">${S.user ? 'طلباتي' : 'تتبع الطلب'}</a>`);
      $('#afterB').onclick = closeSheet;
      viewOrder();
    } catch (err) {
      btn.disabled = false; btn.textContent = 'إرسال طلب عرض السعر';
      fieldErrors(f, err.details);
      toast(err.message);
    }
  };
}

function orderCard(o) {
  const [label, cls, pct] = STATUS[o.status] || [o.status, '', 0];
  const img = o.items?.[0]?.image || '';
  return `<div class="bk"><div class="im"><img src="${h(img)}" alt=""></div><div class="t">
    <div class="r"><h4>${h(o.project || 'طلب ' + o.ref)}</h4><span class="chip ${cls}">${label}</span></div>
    <small><span class="ltr">${h(o.ref)}</span> · ${fmtDate(o.start_date)} – ${fmtDate(o.end_date)} · ${o.items ? o.items.reduce((a, b) => a + b.qty, 0) + ' قطعة' : ''}</small>
    ${o.quote_amount != null ? `<small>عرض السعر: <b style="color:var(--ink)">${Number(o.quote_amount).toLocaleString('en')} ${h(S.settings.currency || 'IQD')}</b></small>` : ''}
    <div class="bar"><i style="width:${pct}%;${o.status === 'cancelled' ? 'background:var(--red)' : ''}"></i></div>
    ${o.status === 'pending' || o.status === 'quoted' ? `<button class="muted" style="font-size:12px;margin-top:10px" data-cancel="${h(o.ref)}">إلغاء الطلب</button>` : ''}
  </div></div>`;
}

async function viewAccount(params) {
  setNav('account');
  if (!S.user) return viewAuth(params.get('tab') || 'login');
  const tab = params.get('tab') || 'orders';
  const u = S.user;
  app.innerHTML = `<div class="wrap page"><h1 class="ttl">حسابي</h1><div style="height:12px"></div><div class="acc-grid">
    <div>
      <div class="prof"><div class="av">${h((u.name || '?').trim().slice(0, 1))}</div><div><b>${h(u.name)}</b><small class="ltr">${h(u.email)}</small></div><button id="logout">خروج</button></div>
      ${['admin', 'staff'].includes(u.role) ? '<a class="btn block" style="margin-top:12px" href="admin">لوحة التحكم</a>' : ''}
      <div class="contact" style="margin-top:12px"><h3>قسم التأجير</h3><p>${h(S.settings.address || '')}<br><span class="ltr">${h(S.settings.phone || '')}</span></p>
        <div class="row">${S.settings.whatsapp ? `<a href="https://wa.me/${h(S.settings.whatsapp)}" target="_blank" rel="noopener">واتساب</a>` : ''}${S.settings.phone ? `<a href="tel:${h(String(S.settings.phone).replace(/\s/g, ''))}">اتصال</a>` : ''}</div></div>
    </div>
    <div>
      <div class="tabs" style="margin-top:0"><button data-t="orders">طلباتي</button><button data-t="favs">المفضلة</button><button data-t="profile">الحساب</button></div>
      <div id="tabBody"><div class="skel" style="height:120px"></div></div>
    </div></div></div>`;
  $$('.tabs [data-t]').forEach(b => { b.classList.toggle('on', b.dataset.t === tab); b.onclick = () => (location.hash = '#/account?tab=' + b.dataset.t); });
  $('#logout').onclick = async () => { try { await api('/auth/logout', { method: 'POST' }); } catch (e) { /* ignore */ } S.user = null; S.favs.clear(); toast('تم تسجيل الخروج'); location.hash = '#/'; };
  const body = $('#tabBody');

  if (tab === 'orders') {
    const r = await api('/me/orders');
    body.innerHTML = r.data.length ? r.data.map(orderCard).join('') : `<div class="empty"><h3>لا توجد طلبات بعد</h3><p>طلباتك وعروض الأسعار ستظهر هنا.</p><a class="btn sm" style="margin-top:16px" href="#/browse">تصفّح المعدات</a></div>`;
    $$('[data-cancel]', body).forEach(b => b.onclick = async () => {
      if (!confirm('إلغاء هذا الطلب؟')) return;
      try { await api('/me/orders/' + b.dataset.cancel + '/cancel', { method: 'POST' }); toast('تم إلغاء الطلب'); viewAccount(params); } catch (e) { toast(e.message); }
    });
  } else if (tab === 'favs') {
    const r = await api('/me/favorites');
    body.innerHTML = r.data.length ? `<div class="grid">${r.data.map(card).join('')}</div>` : `<div class="empty"><h3>لا توجد مفضلة</h3><p>اضغط ♡ في صفحة أي معدة لحفظها هنا.</p></div>`;
    bindCards(body, r.data);
  } else {
    body.innerHTML = `<form class="form" id="pf"><div class="fld"><label>الاسم</label><input name="name" value="${h(u.name)}"></div>
      <div class="fld"><label>الهاتف</label><input name="phone" dir="ltr" style="text-align:right" value="${h(u.phone || '')}"></div>
      <div class="fld"><label>الشركة</label><input name="company" value="${h(u.company || '')}"></div></form>
      <button class="btn block" style="margin-top:12px" id="saveP">حفظ</button>
      <div class="sec"><h2>تغيير كلمة المرور</h2></div>
      <form class="form" id="pw"><div class="fld"><label>كلمة المرور الحالية</label><input type="password" name="current" autocomplete="current-password"></div>
      <div class="fld"><label>كلمة المرور الجديدة</label><input type="password" name="new" autocomplete="new-password"></div></form>
      <button class="btn lt block" style="margin-top:12px" id="saveW">تغيير كلمة المرور</button>`;
    $('#saveP').onclick = async () => { const f = $('#pf'); try { const r = await api('/auth/me', { method: 'PATCH', body: Object.fromEntries(new FormData(f)) }); S.user = { ...S.user, ...r.data }; toast('تم الحفظ'); } catch (e) { fieldErrors(f, e.details); toast(e.message); } };
    $('#saveW').onclick = async () => { const f = $('#pw'); try { await api('/auth/password', { method: 'POST', body: Object.fromEntries(new FormData(f)) }); f.reset(); toast('تم تغيير كلمة المرور'); } catch (e) { fieldErrors(f, e.details); toast(e.message); } };
  }
}

function viewAuth(tab) {
  app.innerHTML = `<div class="wrap page narrow"><h1 class="ttl">${tab === 'login' ? 'تسجيل الدخول' : 'حساب جديد'}</h1>
    <div class="tabs"><button data-t="login" class="${tab === 'login' ? 'on' : ''}">دخول</button><button data-t="register" class="${tab === 'register' ? 'on' : ''}">حساب جديد</button></div>
    <form class="form" id="af" novalidate>
      ${tab === 'register' ? `<div class="fld"><label>الاسم</label><input name="name" required autocomplete="name"></div>
        <div class="fld"><label>رقم الهاتف</label><input name="phone" type="tel" dir="ltr" style="text-align:right" required autocomplete="tel"></div>
        <div class="fld"><label>الشركة (اختياري)</label><input name="company" autocomplete="organization"></div>` : ''}
      <div class="fld"><label>البريد الإلكتروني</label><input name="email" type="email" dir="ltr" style="text-align:right" required autocomplete="email"></div>
      <div class="fld"><label>كلمة المرور</label><input name="password" type="password" required autocomplete="${tab === 'login' ? 'current-password' : 'new-password'}"></div>
    </form>
    <button class="btn block" style="margin-top:14px" id="aB">${tab === 'login' ? 'دخول' : 'إنشاء الحساب'}</button>
    <p class="muted" style="text-align:center;font-size:13px;margin-top:18px">طلبت بدون حساب؟ <a href="#/track" style="text-decoration:underline">تتبع طلبك برقم الطلب</a></p></div>`;
  $$('.tabs [data-t]').forEach(b => b.onclick = () => viewAuth(b.dataset.t));
  const f = $('#af');
  const submit = async () => {
    const btn = $('#aB'); btn.disabled = true;
    try {
      const r = await api('/auth/' + tab, { method: 'POST', body: Object.fromEntries(new FormData(f)) });
      S.user = r.data.user;
      await loadFavs();
      toast('أهلاً ' + S.user.name);
      route();
    } catch (e) { fieldErrors(f, e.details); toast(e.message); btn.disabled = false; }
  };
  $('#aB').onclick = submit;
  f.onsubmit = e => { e.preventDefault(); submit(); };
  f.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); submit(); } });
}

async function viewTrack(params) {
  setNav('track');
  const last = store.get('last_order', {});
  app.innerHTML = `<div class="wrap page narrow"><h1 class="ttl">تتبع طلب</h1><p class="muted" style="font-size:14px">أدخل رقم الطلب ورقم الهاتف المستخدم في الطلب.</p>
    <form class="form" id="tf" style="margin-top:16px"><div class="fld"><label>رقم الطلب</label><input name="ref" dir="ltr" style="text-align:right" placeholder="GG-XXXXXX" value="${h(params.get('ref') || last.ref || '')}"></div>
    <div class="fld"><label>رقم الهاتف</label><input name="phone" type="tel" dir="ltr" style="text-align:right" value="${h(last.phone || '')}"></div></form>
    <button class="btn block" style="margin-top:12px" id="tB">عرض الحالة</button><div id="tr" style="margin-top:18px"></div></div>`;
  const go = async () => {
    const f = $('#tf');
    try {
      const r = await api('/orders/track', { query: { ref: f.ref.value.trim().toUpperCase(), phone: f.phone.value.trim() } });
      $('#tr').innerHTML = orderCard({ ...r.data, status: r.data.status }).replace(/<button[^>]*data-cancel[^>]*>.*?<\/button>/, '') +
        `<div class="form">${r.data.items.map(i => `<div class="fld" style="display:flex;justify-content:space-between"><span class="ltr" style="font-size:14px;color:var(--ink)">${h(i.brand)} ${h(i.name)}</span><b>×${i.qty}</b></div>`).join('')}</div>`;
    } catch (e) { $('#tr').innerHTML = `<div class="empty" style="padding:30px"><h3>لم يتم العثور على الطلب</h3><p>${h(e.message)}</p></div>`; }
  };
  $('#tB').onclick = go;
  $('#tf').onsubmit = e => { e.preventDefault(); go(); };
  if (params.get('ref') && last.phone) go();
}

/* ---------------- تثبيت التطبيق على الشاشة الرئيسية (PWA) ---------------- */
const isStandalone = () => window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
const isIOS = () => /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
let deferredPrompt = null;
window.addEventListener('beforeinstallprompt', e => { e.preventDefault(); deferredPrompt = e; const c = $('#installCard'); if (c) c.hidden = false; });
window.addEventListener('appinstalled', () => { deferredPrompt = null; const c = $('#installCard'); if (c) c.remove(); toast('تم تثبيت التطبيق ✓'); });

function installCard() {
  if (isStandalone() || store.get('install_dismissed', 0) > Date.now()) return '';
  const canShow = isIOS() || deferredPrompt;
  return `<div class="install" id="installCard" ${canShow ? '' : 'hidden'}>
    <img class="ic" src="assets/brand/icon-192.png" alt="">
    <div><b>ثبّت تطبيق Ghani Group</b><small>على شاشتك الرئيسية — يفتح مثل أي تطبيق وبدون متجر</small></div>
    <div class="act"><button id="installBtn">تثبيت</button><button class="x" id="installX" aria-label="إغلاق">×</button></div></div>`;
}
function bindInstall() {
  const btn = $('#installBtn');
  if (!btn) return;
  $('#installX').onclick = () => { store.set('install_dismissed', Date.now() + 7 * 864e5); $('#installCard').remove(); };
  btn.onclick = async () => {
    if (deferredPrompt) {
      deferredPrompt.prompt();
      await deferredPrompt.userChoice.catch(() => null);
      deferredPrompt = null;
      return;
    }
    const share = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#0A84FF" stroke-width="2"><path d="M12 3v12M8 7l4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/></svg>';
    const plus = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#141414" stroke-width="2"><rect x="4" y="4" width="16" height="16" rx="4"/><path d="M12 8v8M8 12h8"/></svg>';
    openSheet(`<img src="assets/brand/icon-192.png" alt="" style="width:72px;height:72px;border-radius:18px;margin:0 auto 14px;display:block">
      <h3>تثبيت على الآيفون</h3><p>بدون متجر وبدون شهادة — خطوتين فقط:</p>
      <div class="steps-ios">١. افتح الموقع من <b>Safari</b> واضغط زر المشاركة <span class="k">${share}</span> أسفل الشاشة<br>
      ٢. اختر <b>إضافة إلى الشاشة الرئيسية</b> <span class="k">${plus}</span> ثم <b>إضافة</b></div>
      <button class="btn lt" id="gotIt">تمام</button>`);
    $('#gotIt').onclick = closeSheet;
  };
}

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => { navigator.serviceWorker.register('sw.js').catch(() => {}); });
}

/* ---------------- router ---------------- */
async function route() {
  const raw = location.hash.replace(/^#/, '') || '/';
  const [path, qs] = raw.split('?');
  const params = new URLSearchParams(qs || '');
  const parts = path.split('/').filter(Boolean);
  document.title = 'Ghani Group — تأجير معدات التصوير السينمائي';
  window.scrollTo({ top: 0 });
  closeSheet();
  try {
    switch (parts[0]) {
      case undefined: await viewHome(); break;
      case 'browse': await viewBrowse(params); break;
      case 'kits': await viewKits(); break;
      case 'item': await viewItem(decodeURIComponent(parts[1] || '')); break;
      case 'order': await viewOrder(); break;
      case 'account': await viewAccount(params); break;
      case 'track': await viewTrack(params); break;
      default: app.innerHTML = '<div class="wrap page"><div class="empty"><h3>الصفحة غير موجودة</h3><a class="btn sm" style="margin-top:16px" href="#/">الرئيسية</a></div></div>';
    }
  } catch (e) {
    console.error(e);
    app.innerHTML = e.status === 404 ? '<div class="wrap page"><div class="empty"><h3>غير موجود</h3><p>ربما تم حذف هذه المعدة.</p><a class="btn sm" style="margin-top:16px" href="#/browse">تصفّح المعدات</a></div></div>' : errorView(e);
  }
}

async function loadFavs() {
  S.favs.clear();
  if (!S.user) return;
  try { (await api('/me/favorites')).data.forEach(f => S.favs.add(f.slug)); } catch (e) { /* ignore */ }
}

function footer() {
  const s = S.settings;
  $('#foot').innerHTML = `<div><b>${h(s.company_name_ar || s.company_name || 'Ghani Group')}</b><br>تأجير معدات التصوير السينمائي وخدمات الإنتاج.<br><span class="ltr">${h(s.address || '')}</span></div>
    <div><b>تواصل</b><span class="ltr">${h(s.phone || '')}</span><span class="ltr">${h(s.email || '')}</span></div>
    <div><b>روابط</b><br><a href="#/browse">المعدات</a> · <a href="#/kits">الباقات</a> · <a href="#/track">تتبع طلب</a><br><a href="privacy">الخصوصية</a> · <a href="terms">الشروط</a> · <a href="support">الدعم</a> · <a href="delete-account">حذف الحساب</a></div>`;
}

$('#topSearch').onsubmit = e => { e.preventDefault(); location.hash = '#/browse?q=' + encodeURIComponent(e.target.q.value.trim()); e.target.q.value = ''; };
window.addEventListener('hashchange', route);

(async function init() {
  saveCart();
  try {
    const [s, me] = await Promise.all([api('/settings', { cache: true }), api('/auth/me')]);
    S.settings = s.data || {};
    S.user = me.data;
    footer();
    await loadFavs();
  } catch (e) { /* يكمل حتى لو فشل */ }
  route();
})();
})();
