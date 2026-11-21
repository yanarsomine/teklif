// Yanar Şömine teklif yedeği — macOS yardımcı (JavaScript for Automation, osascript ile çalışır)
ObjC.import('Foundation');
function oku(p) { return $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null).js; }
function yaz(p, s, bom) { $((bom ? '﻿' : '') + s).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null); }
function tarih(s) { return new Date(String(s).replace(/(\.\d{3})\d+/, '$1')); }
function iki(n) { return (n < 10 ? '0' : '') + n; }
function temiz(s) { return String(s || '').replace(/[\\\/:*?"<>|]/g, '').replace(/\s+/g, ' ').trim(); }
const DURUM = { yeni: 'Yeni talep', plan: 'Keşif planlandı', kesif: 'Keşif yapıldı', teklif: 'Teklif verildi', satis: 'Satış oldu', vazgecti: 'Vazgeçti' };
function klasor(p) { $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(p, true, $(), null); }
function damga(t) { return t.getFullYear() + iki(t.getMonth() + 1) + iki(t.getDate()) + iki(t.getHours()) + iki(t.getMinutes()) + '.' + iki(t.getSeconds()); }
function run(a) {
  const mod = a[0];
  if (mod === 'giris') { const pw = $.NSProcessInfo.processInfo.environment.objectForKey('YS_PASS'); return JSON.stringify({ email: a[1], password: pw ? pw.js : '' }); }
  if (mod === 'token') return JSON.parse(oku(a[1])).access_token || '';
  if (mod === 'csv') {
    const rows = JSON.parse(oku(a[1]));
    const q = v => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"';
    const out = [['Teklif No', 'Tarih', 'Müşteri', 'Yetkili', 'Telefon', 'E-posta', 'Proje', 'Kalem sayısı', 'Toplam', 'Hazırlayan', 'Son güncelleme'].map(q).join(';')];
    rows.filter(x => !(x.data && x.data.silindi)).forEach(x => {
      const d = x.data || {}, c = d.customer || {};
      const top = Object.keys(d.totals || {}).map(k => k + ' ' + Number(d.totals[k]).toFixed(2).replace('.', ',')).join(' + ');
      out.push([d.no, d.date, c.name, c.contact, c.phone, c.email, c.project, (d.items || []).length, top, d.olusturan, x.updated_at].map(q).join(';'));
    });
    yaz(a[2], out.join('\r\n'), true);
    return String(rows.length);
  }
  if (mod === 'birlestir') {   // hedef teklifler.json parça1.json parça2.json …
    let all = []; a.slice(3).forEach(p => { all = all.concat(JSON.parse(oku(p))); });
    yaz(a[1], JSON.stringify(all)); yaz(a[2], JSON.stringify(all.filter(x => x.collection === 'quotes')));
    return String(all.length);
  }
  if (mod === 'plan') {   // tum-veri.json Müşteriler-klasörü -> "kova|uzak|yerel|epoch|touch" satırları; Müşteri bilgileri.txt dosyalarını yazar
    const all = JSON.parse(oku(a[1])), MUS = a[2], out = [];
    const custs = all.filter(x => x.collection === 'musteriler' && !(x.data && x.data.silindi));
    const say = {}; custs.forEach(c => { const k = temiz(c.data.ad).toLocaleLowerCase('tr'); say[k] = (say[k] || 0) + 1; });
    const kl = {};
    custs.forEach(c => {
      const d = c.data; let n = temiz(d.ad); const tek = n && say[n.toLocaleLowerCase('tr')] === 1; n = n || 'İsimsiz müşteri';
      if (!tek) n += ' - ' + (temiz(d.kod) || c.id.slice(0, 6));
      kl[c.id] = n; const cd = MUS + '/' + n; klasor(cd);
      const b = ['Müşteri: ' + (d.ad || ''), 'Telefon: ' + (d.telefon || ''), 'E-posta: ' + (d.eposta || ''),
        'Adres: ' + [d.adres, d.ilce, d.il].filter(Boolean).join(', '), '', 'İşler:'];
      (Array.isArray(d.isler) ? d.isler : []).filter(j => j && !j.silindi).forEach(j => b.push('- ' + (j.baslik || 'İş') + '  [' + (DURUM[j.durum] || j.durum || '') + ']' +
        (j.kesifTarihi ? '  keşif: ' + j.kesifTarihi : '') + (j.sonTeklif && j.sonTeklif.no ? '  son teklif: ' + j.sonTeklif.no : '')));
      if (d.notlar) b.push('', 'Notlar: ' + d.notlar);
      const z = new Date(); b.push('', 'Yedek tarihi: ' + iki(z.getDate()) + '.' + iki(z.getMonth() + 1) + '.' + z.getFullYear() + ' ' + iki(z.getHours()) + ':' + iki(z.getMinutes()));
      yaz(cd + '/Müşteri bilgileri.txt', b.join('\n'), true);
    });
    const used = {};
    const yer = (dir, ad, key) => {
      let y = dir + '/' + ad; const l = y.toLocaleLowerCase('tr');
      if (used[l] && used[l] !== key) { const m = ad.match(/^(.*?)(\.[^.]*)?$/); y = dir + '/' + m[1] + ' (' + key.slice(0, 5) + ')' + (m[2] || ''); }
      used[y.toLocaleLowerCase('tr')] = key; return y;
    };
    all.filter(x => x.collection === 'quotes' && !(x.data && x.data.silindi)).forEach(q => {
      const d = q.data || {}, cid = d.customerId;
      const k = cid && kl[cid] ? kl[cid] : '_Müşteri dosyası olmayan teklifler/' + (temiz(d.customer && d.customer.name) || 'İsimsiz');
      const t = tarih(q.updated_at);
      out.push(['teklifler', q.id + '.pdf', yer(MUS + '/' + k + '/Teklifler', (temiz(d.no) || q.id) + '.pdf', q.id), Math.floor(t.getTime() / 1000), damga(t)].join('|'));
    });
    all.filter(x => /^musteriler\/[^/]+\/dosyalar$/.test(x.collection) && x.data && !x.data.silindi && x.data.assetId).forEach(f => {
      const cid = f.collection.split('/')[1]; if (!kl[cid]) return;
      const alt = { foto: 'Resimler', teklif: 'Teklifler', kesif: 'Keşif' }[f.data.tur] || 'Belgeler';
      let ad = temiz(f.data.ad) || String(f.data.assetId).split('/').pop();
      if (!/\.[^.\/]+$/.test(ad)) { const e = String(f.data.assetId).match(/\.[^.\/]+$/); if (e) ad += e[0]; }
      out.push(['musteri-dosyalari', f.data.assetId, yer(MUS + '/' + kl[cid] + '/' + alt, ad, f.id), 0, ''].join('|'));
    });
    return out.join('\n');
  }
  if (mod === 'listeistek') return JSON.stringify({ prefix: a[1] || '', limit: 1000, offset: +a[2] || 0, sortBy: { column: 'name', order: 'asc' } });
  if (mod === 'nesneler') {   // liste.json önek -> "D|yol" (klasör) ya da "F|yol|epoch|touch"
    const list = JSON.parse(oku(a[1])), on = a[2] || '';
    return list.filter(o => o.name).map(o => {
      const yol = on ? on + '/' + o.name : o.name;
      if (o.id == null) return 'D|' + yol;
      const t = tarih(o.updated_at || o.created_at);
      const ts = t.getFullYear() + iki(t.getMonth() + 1) + iki(t.getDate()) + iki(t.getHours()) + iki(t.getMinutes()) + '.' + iki(t.getSeconds());
      return ['F', yol, Math.floor(t.getTime() / 1000), ts].join('|');
    }).join('\n');
  }
  if (mod === 'urlyol') return String(a[1]).split('/').map(encodeURIComponent).join('/');
  if (mod === 'pdfad') {   // uzak-ad teklifler.json -> yerel dosya adı
    const id = String(a[1]).replace(/\.pdf$/, ''), rows = JSON.parse(oku(a[2]));
    const r = rows.find(x => x.id === id), m = temiz(r && r.data && r.data.customer && r.data.customer.name);
    return m ? id + ' - ' + m + '.pdf' : id + '.pdf';
  }
  if (mod === 'musteri') return String(JSON.parse(oku(a[1])).filter(x => x.collection === 'musteriler' && !(x.data && x.data.silindi)).length);
  if (mod === 'bildir') {   // id bilgisayar ...
    const z = new Date().toISOString();
    const d = a[1] === 'backup' ? { teklif: +a[3] || 0, musteri: +a[4] || 0, pdf: +a[5] || 0, not: String(a[6] || '').trim(), dosya: +a[7] || 0, kayit: +a[8] || 0 } : { hata: String(a[3] || '') };
    d.bilgisayar = a[2]; d.sistem = 'Mac'; d.zaman = z;
    return JSON.stringify({ collection: 'counter', id: a[1], data: d, updated_at: z });
  }
  if (mod === 'sayi') return String(JSON.parse(oku(a[1])).length);
  return '';
}
