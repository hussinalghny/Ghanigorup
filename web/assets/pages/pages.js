(() => {
  const f = document.getElementById('delForm');
  if (!f) return;
  const btn = document.getElementById('delBtn');
  const msg = document.getElementById('delMsg');
  const base = document.querySelector('base')?.getAttribute('href') || '/';
  document.getElementById('cf').onchange = e => { btn.disabled = !e.target.checked; };
  f.onsubmit = async e => {
    e.preventDefault();
    btn.disabled = true;
    msg.className = 'msg';
    try {
      const r = await fetch(base + 'api/v1/auth/delete-account', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ email: f.email.value.trim(), password: f.password.value }),
      });
      const j = await r.json();
      if (!j.ok) throw new Error(j.error?.message || 'تعذر الحذف');
      f.reset();
      msg.className = 'msg ok';
      msg.textContent = 'تم حذف حسابك نهائياً. / Your account has been deleted.';
    } catch (err) {
      msg.className = 'msg err';
      msg.textContent = err.message;
      btn.disabled = !document.getElementById('cf').checked;
    }
  };
})();
