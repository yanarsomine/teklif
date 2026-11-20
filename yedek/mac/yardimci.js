// Yanar Şömine teklif yedeği — macOS yardımcı (JavaScript for Automation, osascript ile çalışır)
ObjC.import('Foundation');
function oku(p) { return $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null).js; }
function yaz(p, s, bom) { $((bom ? '﻿' : '') + s).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null); }
function tarih(s) { return new Date(String(s).replace(/(\.\d{3})\d+/, '$1')); }
function iki(n) { return (n < 10 ? '0' : '') + n; }
function temiz(s) { return String(s || '').replace(/[\\\/:*?"<>|]/g, '').trim(); }
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
