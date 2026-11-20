/* Yanar Şömine Teklif — Supabase arka ucu.
   Uygulama kodu window.claude.use('db' | 'assets' | 'downloads' | 'user' | 'archive' | 'files') çağrılarıyla çalışır;
   bu dosya aynı arayüzü Supabase ile sağlar. Tüm kayıtlar "docs" tablosunda (collection, id, data) tutulur. */
(function () {
  const cfg = window.YS_CONFIG || {};
  const ready = !!(window.supabase && cfg.SUPABASE_URL && !/PROJE-KODU/.test(cfg.SUPABASE_URL));
  // Ağ isteği asılı kalmasın: 60 sn içinde yanıt gelmezse hata verir (telefonda zayıf bağlantı)
  const tfetch = (u, o = {}) => { const c = new AbortController(); const t = setTimeout(() => c.abort(), 60000);
    if (o.signal) o.signal.addEventListener('abort', () => c.abort());
    return fetch(u, { ...o, signal: c.signal }).finally(() => clearTimeout(t)); };
  const sb = ready ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, { global: { fetch: tfetch } }) : null;
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
        <div style="font-weight:700;font-size:17px">Müşteri ve teklif programına giriş</div>
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
    const { data, error } = await sb.from('profiles').select('role,name').eq('id', s.user.id).maybeSingle();
    if (error) { loginUI('Bağlantı hatası, sayfayı yenileyin.'); return; }
    profile = data || { role: 'pending', name: '' };
    if (!['admin', 'staff'].includes(profile.role)) {
      // Onaylanmamış hesap: hiçbir veriye erişemez (veritabanı kuralları da engeller)
      loginUI('Hesabınız henüz onaylanmadı. Yöneticinizden onay isteyin.');
      await sb.auth.signOut(); session = null; return;
    }
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
  const split = path => { const p = path.split('/'); return { col: p.slice(0, -1).join('/'), id: p[p.length - 1] }; };
  const newId = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
  const snapDoc = (id, row) => ({ id, exists: !!row, updatedAt: row ? row.updated_at : null, data: () => row ? row.data : undefined, metadata: { fromCache: false, hasPendingWrites: false } });
  const fail = e => { const err = new Error(e.message || 'Kayıt hatası'); err.code = e.code === '23505' ? 'exists' : (e.code || 'unavailable'); return err; };
  const PAGE = 1000;

  /* Canlı güncelleme: değişen satır tek tek yeniden okunur; bağlantı kopunca ve uygulama öne gelince her şey tazelenir */
  const colSubs = new Map(); // collection -> Set(listener)
  const docSubs = new Map(); // "col\u0000id" -> Set(listener)
  let channel = null, chanOk = false, lastFull = 0;
  function refreshAll() {
    lastFull = Date.now();
    colSubs.forEach(set => set.forEach(l => l.full()));
    docSubs.forEach(set => set.forEach(l => l.full()));
  }
  function ensureChannel() {
    if (channel) return;
    channel = sb.channel('docs-all').on('postgres_changes', { event: '*', schema: 'public', table: 'docs' }, payload => {
      const row = (payload.new && payload.new.collection) ? payload.new : payload.old || {};
      const col = row.collection, id = row.id;
      if (!col) { refreshAll(); return; }
      (colSubs.get(col) || new Set()).forEach(l => l.one(id, payload.eventType));
      (docSubs.get(col + '\u0000' + id) || new Set()).forEach(l => l.full());
    }).subscribe(status => {
      if (status === 'SUBSCRIBED') { if (!chanOk && lastFull) refreshAll(); chanOk = true; }
      else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') chanOk = false;
    });
  }
  const wake = () => { if (document.visibilityState === 'visible' && Date.now() - lastFull > 30000) refreshAll(); };
  document.addEventListener('visibilitychange', wake);
  window.addEventListener('online', () => { lastFull = 0; wake(); });
  window.addEventListener('pageshow', e => { if (e.persisted) wake(); });

  async function getRow(col, id) {
    const { data, error } = await sb.from('docs').select('data,updated_at').eq('collection', col).eq('id', id).maybeSingle();
    if (error) throw fail(error); return data;
  }
  async function getAll(col) {
    const rows = [];
    for (let from = 0; ; from += PAGE) {
      const { data, error } = await sb.from('docs').select('id,data,updated_at').eq('collection', col).order('id').range(from, from + PAGE - 1);
      if (error) throw fail(error);
      rows.push(...(data || [])); if (!data || data.length < PAGE) break;
    }
    return rows;
  }
  const colSnap = map => { const docs = [...map.entries()].map(([id, r]) => snapDoc(id, r)); return { docs, size: docs.length, empty: !docs.length, docChanges: () => [], metadata: { fromCache: false, hasPendingWrites: false } }; };

  const db = {
    doc(path) {
      const { col, id } = split(path);
      const ref = {
        id, path,
        async get() { return snapDoc(id, await getRow(col, id)); },
        async set(d) {
          const { data, error } = await sb.from('docs').upsert({ collection: col, id, data: d, updated_at: new Date().toISOString() }).select('updated_at');
          if (error) throw fail(error); return data && data[0] ? data[0].updated_at : null;
        },
        /* Yeni kayıt: aynı adla kayıt varsa üzerine YAZMAZ, code:'exists' hatası verir */
        async create(d) {
          const { data, error } = await sb.from('docs').insert({ collection: col, id, data: d, updated_at: new Date().toISOString() }).select('updated_at');
          if (error) throw fail(error); return data && data[0] ? data[0].updated_at : null;
        },
        /* Başkası bu arada değiştirmediyse yaz (iyimser kilit); değiştirdiyse code:'conflict' */
        async setIf(d, ts) {
          if (!ts) return ref.set(d);
          const { data, error } = await sb.from('docs').update({ data: d, updated_at: new Date().toISOString() }).eq('collection', col).eq('id', id).eq('updated_at', ts).select('updated_at');
          if (error) throw fail(error);
          if (!data || !data.length) { const e = new Error('Bu kayıt başka biri tarafından değiştirildi'); e.code = 'conflict'; throw e; }
          return data[0].updated_at;
        },
        /* Güncel kaydı okuyup fn ile değiştirir; araya başka kayıt girerse yeniden dener */
        async mutate(fn) {
          for (let k = 0; k < 6; k++) {
            const row = await getRow(col, id);
            const next = fn(row ? JSON.parse(JSON.stringify(row.data || {})) : null);
            if (next === undefined) return null;
            try { return row ? await ref.setIf(next, row.updated_at) : await ref.create(next); }
            catch (e) { if (e.code !== 'conflict' && e.code !== 'exists') throw e; await new Promise(r => setTimeout(r, 120 + Math.random() * 300)); }
          }
          const e = new Error('Kayıt çok sık değişiyor, tekrar deneyin'); e.code = 'conflict'; throw e;
        },
        async update(d) { return ref.mutate(cur => ({ ...(cur || {}), ...d })); },
        async delete() { const { error } = await sb.from('docs').delete().eq('collection', col).eq('id', id); if (error) throw fail(error); },
        onSnapshot(next, err) {
          ensureChannel(); const key = col + '\u0000' + id;
          const l = { full: async () => { try { next(await ref.get()); } catch (e) { err && err(e); } } };
          if (!docSubs.has(key)) docSubs.set(key, new Set()); docSubs.get(key).add(l); l.full(); lastFull = lastFull || Date.now();
          return () => docSubs.get(key).delete(l);
        }
      };
      return ref;
    },
    collection(col) {
      const q = {
        path: col,
        doc: id => db.doc(col + '/' + (id || newId())),
        async get() { const m = new Map(); (await getAll(col)).forEach(r => m.set(r.id, r)); return colSnap(m); },
        onSnapshot(next, err) {
          ensureChannel();
          let cache = null, t = null;
          const emit = () => { clearTimeout(t); t = setTimeout(() => next(colSnap(cache)), 60); };
          const l = {
            full: async () => { try { const m = new Map(); (await getAll(col)).forEach(r => m.set(r.id, r)); cache = m; next(colSnap(cache)); } catch (e) { err && err(e); } },
            one: async (id, ev) => {
              if (!cache) return l.full();
              try { if (ev === 'DELETE') cache.delete(id); else { const r = await getRow(col, id); if (r) cache.set(id, { id, ...r }); else cache.delete(id); } emit(); }
              catch (e) { err && err(e); }
            }
          };
          if (!colSubs.has(col)) colSubs.set(col, new Set()); colSubs.get(col).add(l); l.full(); lastFull = lastFull || Date.now();
          return () => colSubs.get(col).delete(l);
        },
        where() { return q; }, orderBy() { return q; }, limit() { return q; }
      };
      return q;
    },
    /* Sunucu fonksiyonu (ör. sıradaki teklif numarası) */
    async rpc(name, args) { const { data, error } = await sb.rpc(name, args || {}); if (error) throw fail(error); return data; }
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

  /* ---------- archive (gizli "teklifler" kovasına teklif PDF'i; gün sonu yedeği buradan alır) ---------- */
  const archive = {
    async savePdf(id, blob) {
      const { error } = await sb.storage.from('teklifler').upload(`${id}.pdf`, blob, { contentType: 'application/pdf', upsert: true });
      if (error) throw fail(error);
      return true;
    },
    async remove(id) { const { error } = await sb.storage.from('teklifler').remove([`${id}.pdf`]); if (error) throw fail(error); }
  };

  /* ---------- files (müşteri dosyaları: gizli "musteri-dosyalari" kovası, süreli imzalı bağlantıyla açılır) ---------- */
  const FB = 'musteri-dosyalari';
  const files = {
    async upload(blob, opts) {
      const type = (opts && opts.type) || blob.type || 'application/octet-stream';
      const nm = (blob.name || 'dosya').split('.'); const ext = nm.length > 1 ? nm.pop().toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 5) : '';
      const name = `${new Date().toISOString().slice(0, 7)}/${newId()}${ext ? '.' + ext : ''}`;
      const { error } = await sb.storage.from(FB).upload(name, blob, { contentType: type, upsert: false });
      if (error) throw fail(error);
      return { id: name, sizeBytes: blob.size, contentType: type };
    },
    async urls(ids) {
      if (!ids.length) return {};
      const { data, error } = await sb.storage.from(FB).createSignedUrls(ids, 3600);
      if (error) throw fail(error);
      const out = {}; (data || []).forEach(x => { if (x.signedUrl) out[x.path] = x.signedUrl; }); return out;
    },
    async remove(id) { const { error } = await sb.storage.from(FB).remove([id]); if (error) throw fail(error); }
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
    async role() { return profile?.role || null; },
    async isOwner() { return profile?.role === 'admin'; },
    async id() { return session?.user?.id || null; },
    async can() { return !!session; },
    async profiles(ids) {
      const { data } = await sb.from('profiles').select('id,name').in('id', ids);
      const out = {}; (data || []).forEach(p => { out[p.id] = { name: p.name || '' }; });
      if (session && ids.includes(session.user.id) && !out[session.user.id]?.name) out[session.user.id] = { name: profile?.name || session.user.email || '' };
      return out;
    },
    async signOut() { await sb.auth.signOut(); location.reload(); },
    async me() { return { id: session?.user?.id || null, name: profile?.name || '', role: profile?.role || null, email: session?.user?.email || null, isOwner: profile?.role === 'admin', canEdit: profile?.role === 'admin' }; }
  };

  window.claude = {
    async use(name) {
      if (!sb) return null;
      await authed;
      return { db, assets, downloads, user, archive, files }[name] || null;
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
