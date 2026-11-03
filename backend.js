/* Yanar Şömine Teklif — Supabase arka ucu.
   Uygulama kodu window.claude.use('db' | 'assets' | 'downloads' | 'user') çağrılarıyla çalışır;
   bu dosya aynı arayüzü Supabase ile sağlar. Tüm kayıtlar "docs" tablosunda (collection, id, data) tutulur. */
(function () {
  const cfg = window.YS_CONFIG || {};
  const ready = !!(window.supabase && cfg.SUPABASE_URL && !/PROJE-KODU/.test(cfg.SUPABASE_URL));
  const sb = ready ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY) : null;
  window.YS_SB = sb;

  let session = null, profile = null, resolveAuth;
  const authed = new Promise(r => (resolveAuth = r));

  /* ---------- login overlay ---------- */
  function loginUI(msg) {
    let o = document.getElementById('ys-login');
    if (!o) {
      o = document.createElement('div'); o.id = 'ys-login';
      o.innerHTML = `
      <form id="ys-lf" style="background:var(--panel,#fff);color:var(--ink,#1e1a19);border:1px solid var(--line,#e4dedb);border-radius:14px;padding:28px;width:min(380px,calc(100% - 32px));display:flex;flex-direction:column;gap:12px;box-shadow:0 10px 40px rgba(0,0,0,.15)">
        <img src="logo.png" alt="Yanar Şömine" style="height:34px;width:auto;align-self:flex-start">
        <div style="font-weight:700;font-size:17px">Teklif programına giriş</div>
        <label style="display:flex;flex-direction:column;gap:4px;font-size:12px;font-weight:600;color:var(--muted,#6f6764)">E-posta<input id="ys-em" type="email" autocomplete="username" required style="padding:9px 10px;border:1px solid var(--line,#e4dedb);border-radius:8px;font:inherit;font-size:14px;color:inherit;background:var(--bg,#f6f4f2)"></label>
        <label style="display:flex;flex-direction:column;gap:4px;font-size:12px;font-weight:600;color:var(--muted,#6f6764)">Şifre<input id="ys-pw" type="password" autocomplete="current-password" required style="padding:9px 10px;border:1px solid var(--line,#e4dedb);border-radius:8px;font:inherit;font-size:14px;color:inherit;background:var(--bg,#f6f4f2)"></label>
        <button style="padding:10px;border:0;border-radius:8px;background:var(--brand,#9a1b1f);color:#fff;font-weight:700;font-size:14px;cursor:pointer">Giriş yap</button>
        <div id="ys-lmsg" style="font-size:12.5px;color:var(--danger,#b42318);min-height:16px"></div>
      </form>`;
      o.style.cssText = 'position:fixed;inset:0;z-index:100;background:var(--bg,#f6f4f2);display:flex;align-items:center;justify-content:center';
      document.body.appendChild(o);
      o.querySelector('#ys-lf').addEventListener('submit', async e => {
        e.preventDefault();
        const m = o.querySelector('#ys-lmsg'); m.textContent = 'Giriş yapılıyor…';
        const { error } = await sb.auth.signInWithPassword({ email: o.querySelector('#ys-em').value.trim(), password: o.querySelector('#ys-pw').value });
        if (error) m.textContent = 'E-posta veya şifre hatalı.';
      });
    }
    o.hidden = false;
    if (msg) o.querySelector('#ys-lmsg').textContent = msg;
  }
  function hideLogin() { const o = document.getElementById('ys-login'); if (o) o.hidden = true; }

  async function onSession(s) {
    session = s;
    if (!s) { loginUI(); return; }
    const { data } = await sb.from('profiles').select('role,name').eq('id', s.user.id).maybeSingle();
    profile = data || { role: 'staff', name: '' };
    hideLogin(); addLogout(); resolveAuth(true);
  }
  function addLogout() {
    if (document.getElementById('ys-out')) return;
    const st = document.getElementById('status'); if (!st) return;
    const b = document.createElement('button'); b.id = 'ys-out'; b.className = 'btn sm ghost'; b.textContent = 'Çıkış';
    b.title = session?.user?.email || '';
    b.onclick = async () => { await sb.auth.signOut(); location.reload(); };
    st.after(b);
  }

  /* ---------- db adapter ---------- */
  const split = path => { const p = path.split('/'); return { col: p[0], id: p[1] }; };
  const snapDoc = (id, row) => ({ id, exists: !!row, data: () => row ? row.data : undefined, metadata: { fromCache: false, hasPendingWrites: false } });
  const subs = new Map(); // collection -> Set(fn)
  let channel = null;
  function ensureChannel() {
    if (channel) return;
    channel = sb.channel('docs-all').on('postgres_changes', { event: '*', schema: 'public', table: 'docs' }, payload => {
      const col = (payload.new && payload.new.collection) || (payload.old && payload.old.collection);
      (subs.get(col) || new Set()).forEach(fn => fn());
      if (!col) subs.forEach(set => set.forEach(fn => fn()));
    }).subscribe();
  }
  function watch(col, fn) { ensureChannel(); if (!subs.has(col)) subs.set(col, new Set()); subs.get(col).add(fn); fn(); return () => subs.get(col).delete(fn); }
  const fail = e => { const err = new Error(e.message || 'Kayıt hatası'); err.code = e.code || 'unavailable'; return err; };

  const db = {
    doc(path) {
      const { col, id } = split(path);
      return {
        id, path,
        async get() { const { data, error } = await sb.from('docs').select('data').eq('collection', col).eq('id', id).maybeSingle(); if (error) throw fail(error); return snapDoc(id, data); },
        async set(d) { const { error } = await sb.from('docs').upsert({ collection: col, id, data: d, updated_at: new Date().toISOString() }); if (error) throw fail(error); },
        async update(d) { const cur = await this.get(); await this.set({ ...(cur.data() || {}), ...d }); },
        async delete() { const { error } = await sb.from('docs').delete().eq('collection', col).eq('id', id); if (error) throw fail(error); },
        onSnapshot(next, err) {
          return watch(col, async () => { try { next(await this.get()); } catch (e) { err && err(e); } });
        }
      };
    },
    collection(col) {
      const q = {
        path: col,
        doc: id => db.doc(col + '/' + id),
        async get() {
          const { data, error } = await sb.from('docs').select('id,data').eq('collection', col).limit(5000); if (error) throw fail(error);
          const docs = (data || []).map(r => snapDoc(r.id, r));
          return { docs, size: docs.length, empty: !docs.length, docChanges: () => [], metadata: { fromCache: false, hasPendingWrites: false } };
        },
        onSnapshot(next, err) { return watch(col, async () => { try { next(await q.get()); } catch (e) { err && err(e); } }); },
        where() { return q; }, orderBy() { return q; }, limit() { return q; }
      };
      return q;
    }
  };

  /* ---------- assets (Supabase Storage, bucket "uploads") ---------- */
  const assets = {
    async upload(blob, opts) {
      const type = (opts && opts.type) || blob.type || 'image/jpeg';
      const ext = type.includes('png') ? 'png' : type.includes('webp') ? 'webp' : 'jpg';
      const name = `${new Date().toISOString().slice(0, 10)}/${Math.random().toString(36).slice(2)}.${ext}`;
      const { error } = await sb.storage.from('uploads').upload(name, blob, { contentType: type, upsert: false });
      if (error) throw fail(error);
      const { data } = sb.storage.from('uploads').getPublicUrl(name);
      return { id: name, url: data.publicUrl, sizeBytes: blob.size, contentType: type };
    }
  };

  /* ---------- downloads (normal browser download) ---------- */
  const downloads = {
    async save({ filename, data }) {
      const blob = data instanceof Blob ? data : new Blob([data]);
      const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = filename;
      document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 4000);
      return { status: 'saved' };
    }
  };

  /* ---------- user ---------- */
  const user = {
    async canEdit() { return profile?.role === 'admin'; },
    async isOwner() { return profile?.role === 'admin'; },
    async id() { return session?.user?.id || null; },
    async me() { return { id: session?.user?.id || null, name: profile?.name || '', email: session?.user?.email || null, isOwner: profile?.role === 'admin', canEdit: profile?.role === 'admin' }; }
  };

  window.claude = {
    async use(name) {
      if (!sb) return null;
      await authed;
      return { db, assets, downloads, user }[name] || null;
    }
  };

  if (!sb) {
    document.addEventListener('DOMContentLoaded', () => {
      const st = document.getElementById('status'); if (st) st.textContent = 'Sunucu bağlantısı ayarlanmamış (config.js)';
    });
    return;
  }
  const start = () => {
    sb.auth.getSession().then(({ data }) => onSession(data.session));
    sb.auth.onAuthStateChange((ev, s) => { if (ev === 'SIGNED_IN' && !session) onSession(s); if (ev === 'SIGNED_OUT') { session = null; loginUI(); } });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
