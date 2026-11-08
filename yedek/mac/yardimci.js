// Yanar Şömine teklif yedeği — macOS yardımcı (JavaScript for Automation, osascript ile çalışır)
ObjC.import('Foundation');
function oku(p) { return $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null).js; }
function yaz(p, s, bom) { $((bom ? '﻿' : '') + s).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null); }
function tarih(s) { return new Date(String(s).replace(/(\.\d{3})\d+/, '$1')); }
function iki(n) { return (n < 10 ? '0' : '') + n; }
function temiz(s) { return String(s || '').replace(/[\\\/:*?"<>|]/g, '').trim(); }
function run(a) {
  const mod = a[0];
  if (mod === 'giris') return JSON.stringify({ email: a[1], password: a[2] });
  if (mod === 'token') return JSON.parse(oku(a[1])).access_token || '';
  if (mod === 'csv') {
    const rows = JSON.parse(oku(a[1]));
    const q = v => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"';
    const out = [['Teklif No', 'Tarih', 'Müşteri', 'Yetkili', 'Telefon', 'E-posta', 'Proje', 'Kalem sayısı', 'Toplam', 'Son güncelleme'].map(q).join(';')];
    rows.forEach(x => {
      const d = x.data || {}, c = d.customer || {};
      const top = Object.keys(d.totals || {}).map(k => k + ' ' + Number(d.totals[k]).toFixed(2).replace('.', ',')).join(' + ');
      out.push([d.no, d.date, c.name, c.contact, c.phone, c.email, c.project, (d.items || []).length, top, x.updated_at].map(q).join(';'));
    });
    yaz(a[2], out.join('\r\n'), true);
    return String(rows.length);
  }
  if (mod === 'pdfler') {   // liste.json teklifler.json -> "ad|touch|yerelad" satırları
    const list = JSON.parse(oku(a[1])), rows = JSON.parse(oku(a[2])), ad = {};
    rows.forEach(x => { ad[x.id] = (x.data && x.data.customer && x.data.customer.name) || ''; });
    return list.filter(o => o.name && /\.pdf$/.test(o.name)).map(o => {
      const id = o.name.slice(0, -4), m = temiz(ad[id]), t = tarih(o.updated_at || o.created_at);
      const ts = t.getFullYear() + iki(t.getMonth() + 1) + iki(t.getDate()) + iki(t.getHours()) + iki(t.getMinutes()) + '.' + iki(t.getSeconds());
      return [o.name, ts, Math.floor(t.getTime() / 1000), m ? id + ' - ' + m + '.pdf' : id + '.pdf'].join('|');
    }).join('\n');
  }
  if (mod === 'sayi') return String(JSON.parse(oku(a[1])).length);
  return '';
}
