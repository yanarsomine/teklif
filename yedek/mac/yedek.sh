#!/bin/bash
# Yanar Şömine Teklif Programı — gün sonu yedeği (macOS)
# Programdaki tüm kayıtları, teklif PDF'lerini ve müşteri dosyalarını ~/YanarYedek/Yedekler klasörüne indirir. launchd her gün 18:00'de ve oturum açılışında çalıştırır.
DIR="$HOME/YanarYedek"
URL='https://kxwhxjwurzyhtdvcumap.supabase.co'
KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt4d2h4and1cnp5aHRkdmN1bWFwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3MTkyMTgsImV4cCI6MjEwOTI5NTIxOH0.-kMYzLUElYFE6TvcdjS76Fk8WKFM8Wjz6xDpNEtBCis'
HEDEF="$DIR/Yedekler"; VERI="$HEDEF/Veri"; PDF="$HEDEF/PDF"; LOG="$HEDEF/yedek-gunlugu.txt"
JS="$DIR/yardimci.js"; TMP="$(mktemp -d)"; BUGUN="$(date +%Y-%m-%d)"
mkdir -p "$VERI" "$PDF"
yaz() { echo "$(date '+%Y-%m-%d %H:%M')  $1" >> "$LOG"; }
js() { osascript -l JavaScript "$JS" "$@"; }
mkdir "$DIR/.kilit" 2>/dev/null || { [ -n "$(find "$DIR/.kilit" -mmin +60 2>/dev/null)" ] && rmdir "$DIR/.kilit" && mkdir "$DIR/.kilit"; } || exit 0
bitir() { rm -rf "$TMP"; rmdir "$DIR/.kilit" 2>/dev/null; }
trap bitir EXIT
bildir() {  # Programın Panel ekranındaki "Gün sonu yedeği" kutusu bu kaydı okur
  [ -n "$AUTH" ] || return 0
  js bildir "$1" "$(scutil --get ComputerName 2>/dev/null || hostname)" "$2" "$3" "$4" "$5" "$6" "$7" > "$TMP/b.json" &&
  curl -sS -o /dev/null -X POST "$URL/rest/v1/docs" -H "apikey: $KEY" -H "$AUTH" -H 'Content-Type: application/json' \
    -H 'Prefer: resolution=merge-duplicates' --data-binary @"$TMP/b.json" 2>/dev/null || true
}
hata() { yaz "HATA: $1"; bildir backup-err "$1"; exit 1; }

EMAIL="$(cat "$DIR/eposta.txt" 2>/dev/null)"
PASS="$(security find-generic-password -s 'YanarSomineTeklif' -a "$EMAIL" -w 2>/dev/null)"
[ -n "$EMAIL" ] && [ -n "$PASS" ] || hata "Giriş bilgisi bulunamadı, Kurulum.command'ı yeniden çalıştırın."

# 1) Giriş (şifre komut satırında görünmesin diye ortam değişkeniyle aktarılır)
YS_PASS="$PASS" js giris "$EMAIL" > "$TMP/giris.json"
unset PASS
curl -sS -f -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $KEY" -H 'Content-Type: application/json' \
  --data-binary @"$TMP/giris.json" -o "$TMP/token.json" || hata "Giriş yapılamadı (e-posta/şifre ya da internet)."
rm -f "$TMP/giris.json"
TOKEN="$(js token "$TMP/token.json")"
[ -n "$TOKEN" ] || hata "Giriş yapılamadı."
AUTH="Authorization: Bearer $TOKEN"

# 2) Tüm kayıtlar (teklifler, müşteriler, fiyatlar, ayarlar…) — 1000'erli sayfalar, eksik inerse hata
OFF=0; K=0; TOPLAM=-1
while :; do
  curl -sS -f "$URL/rest/v1/docs?select=collection,id,data,updated_at&order=collection,id&limit=1000&offset=$OFF" \
    -H "apikey: $KEY" -H "$AUTH" -H 'Prefer: count=exact' -D "$TMP/h$K.txt" -o "$TMP/p$K.json" || hata "Kayıtlar indirilemedi."
  T="$(tr -d '\r' < "$TMP/h$K.txt" | sed -n 's/^[Cc]ontent-[Rr]ange: .*\/\([0-9][0-9]*\)$/\1/p' | tail -1)"; [ -n "$T" ] && TOPLAM="$T"
  N="$(js sayi "$TMP/p$K.json")"; K=$((K + 1))
  [ "$N" -eq 1000 ] || break
  OFF=$((OFF + 1000))
done
SAYI="$(js birlestir "$VERI/tum-veri-$BUGUN.json" "$TMP/teklifler.json" "$TMP"/p*.json)" || hata "Kayıtlar birleştirilemedi."
[ "$TOPLAM" -lt 0 ] || [ "$SAYI" -eq "$TOPLAM" ] || hata "Kayıtlar eksik indi ($SAYI / $TOPLAM)."
ADET="$(js csv "$TMP/teklifler.json" "$VERI/teklif-listesi-$BUGUN.csv")"
MUSTERI="$(js musteri "$VERI/tum-veri-$BUGUN.json")"

# 3) Dosyalar: teklif PDF'leri ve müşteri dosyaları — yalnız yeni/değişenler
indir() {  # kova uzak-yol hedef epoch touch-zamanı
  if [ ! -f "$3" ] || [ "$(stat -f %m "$3")" -lt $(($4 - 2)) ]; then
    ENC="$(js urlyol "$2")"
    if curl -sS -f "$URL/storage/v1/object/$1/$ENC" -H "apikey: $KEY" -H "$AUTH" -o "$TMP/indir.tmp"; then
      mkdir -p "$(dirname "$3")"; mv "$TMP/indir.tmp" "$3"; touch -t "$5" "$3"; return 0
    fi
    PDFHATA=" (bazı dosyalar indirilemedi)"
  fi
  return 1
}
listele() {  # kova onek -> "yol|epoch|touch" satırları (alt klasörler dahil)
  local OFF=0 N F
  while :; do
    js listeistek "$2" "$OFF" > "$TMP/q.json"
    curl -sS -f -X POST "$URL/storage/v1/object/list/$1" -H "apikey: $KEY" -H "$AUTH" -H 'Content-Type: application/json' \
      --data-binary @"$TMP/q.json" -o "$TMP/l.json" || { PDFHATA=" (dosya listesi alınamadı)"; return; }
    N="$(js sayi "$TMP/l.json")"
    F="$(mktemp "$TMP/n.XXXXXX")"
    js nesneler "$TMP/l.json" "$2" > "$F"
    while IFS='|' read -r TUR YOL EP TS; do
      [ -n "$YOL" ] || continue
      if [ "$TUR" = "D" ]; then listele "$1" "$YOL" < /dev/null; else echo "$YOL|$EP|$TS"; fi
    done < "$F"
    [ "$N" -eq 1000 ] || break
    OFF=$((OFF + 1000))
  done
}
YENI=0; YENIDOSYA=0; PDFHATA=""
listele teklifler "" > "$TMP/pdfler.txt"
while IFS='|' read -r YOL EP TS; do
  case "$YOL" in *.pdf) ;; *) continue ;; esac
  YEREL="$(js pdfad "$YOL" "$TMP/teklifler.json" < /dev/null)"
  indir teklifler "$YOL" "$PDF/$YEREL" "$EP" "$TS" < /dev/null && YENI=$((YENI + 1))
done < "$TMP/pdfler.txt"
listele musteri-dosyalari "" > "$TMP/dosyalar.txt"
while IFS='|' read -r YOL EP TS; do
  [ -n "$YOL" ] || continue
  indir musteri-dosyalari "$YOL" "$HEDEF/MusteriDosyalari/$YOL" "$EP" "$TS" < /dev/null && YENIDOSYA=$((YENIDOSYA + 1))
done < "$TMP/dosyalar.txt"
listele uploads "" > "$TMP/resimler.txt"
while IFS='|' read -r YOL EP TS; do
  [ -n "$YOL" ] || continue
  indir uploads "$YOL" "$HEDEF/UrunResimleri/$YOL" "$EP" "$TS" < /dev/null && YENIDOSYA=$((YENIDOSYA + 1))
done < "$TMP/resimler.txt"

yaz "Tamam: $SAYI kayıt ($ADET teklif, $MUSTERI müşteri), $YENI yeni/değişen PDF, $YENIDOSYA yeni müşteri dosyası$PDFHATA"
bildir backup "$ADET" "$MUSTERI" "$YENI" "$PDFHATA" "$YENIDOSYA" "$SAYI"
