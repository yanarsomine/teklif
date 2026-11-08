# Yanar Şömine Teklif Programı

Yanar Şömine'nin fiyat teklifi hazırlama programı. Statik site (GitHub Pages) + Supabase (giriş, veri, resim).
Ana dalda (`main`) yapılan her değişiklik GitHub Pages ile birkaç dakikada canlıya geçer.

## Dosyalar
- `index.html` — programın tamamı (arayüz, teklif hesapları, PDF üretimi). Tek dosya, kütüphane: html2canvas + jsPDF (CDN).
- `backend.js` — `window.claude.use('db'|'assets'|'downloads'|'user')` arayüzünü Supabase ile sağlar. Uygulama kodu bu arayüzle yazılmıştır; arayüzü değiştirme.
- `config.js` — Supabase URL ve anon anahtar (herkese açık olabilir; veriler RLS ile korunur).
- `data/products.json` — katalog (ürün kodu, ad, kategori, fiyat, para birimi, birim, açıklama, teknik özellikler, varyantlar, resim/çizim yolu). `made: true` = kendi üretimimiz (mermer şömine/barbekü, fiyat teklifte yazılır).
- `data/thumbs.json` — liste için küçük resimler (data URI), anahtar ürün kodu.
- `img/`, `img/m/` (mermer kataloğu), `drw/` (teknik çizimler), `logo.png`.
- `supabase/kurulum.sql` — veritabanı şeması ve güvenlik kuralları.
- `.github/workflows/kur.yml` — hafta içi 09:43 ve 15:43'te TCMB döviz satış kurunu `docs(counter/rate)` satırına yazar (secrets: SUPABASE_URL, SUPABASE_SERVICE_KEY).

## Veri (Supabase `docs` tablosu: collection, id, data jsonb)
- `quotes/<teklif no>` teklifler · `config/settings` ayarlar · `overrides/<kod>` fiyat/resim/gizleme ve metin değişiklikleri (name, cat, sub, unit, cur, short, defNote, feats, specs, varLabel, variants — "Düzenle" penceresi)
- `custom/<kod>` programdan eklenen ürünler · `counter/quotes` sıradaki numara · `counter/rate` {eur, usd, date}
- Roller `profiles.role`: `admin` (fiyat, ayar, ürün düzenler) / `staff` (teklif hazırlar).

## Güncelleme kuralları
- Katalog değişiklikleri `data/products.json` (+ gerekirse `data/thumbs.json`, `img/`) üzerinden yapılır; fiyatları kullanıcı programdan girer (overrides), json'daki fiyatları ezme.
- "Yerli Asansörlü Hazneler" kategorisi yanarsomine.com/yerli-asansorlu-hazneler'den alındı (Premium hariç); fiyatlar TRY KDV dahil, resimler `img/yerli/` (küçük resimler thumbs.json). Varyantlarda `specs` olabilir: seçilen ölçünün teknik değerleri genel özelliklerin önüne eklenir (`pspecs`). Özellik değerindeki `{miktar}` teklifteki miktar + birim ile değiştirilir (ör. barbekü tezgahı uzunluğu).
- Para birimleri: EUR, USD, TRY. KDV her kalemde ayrı (incl/excl).
- "Baca · Isı Odası" sekmesi: `Baca ve Isı Odası Uygulamaları` kategorisindeki işler (ısı odası, kat arası baca, boru çekimi, çatı üzeri baca, baca şapkası); fiyatları KDV hariç (`vatDefault: 'excl'`), `gallery` ek fotoğraflar.
- PDF sırası: firma + teşekkür sayfası → ürün sayfaları → montaj malzemeleri → fiyatlandırma.
- Değişiklikten sonra yerelde `python3 -m http.server` ile açıp kontrol et, sonra `main`'e gönder.
