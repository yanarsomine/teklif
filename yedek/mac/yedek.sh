#!/bin/bash
# Yanar Şömine Teklif Programı — gün sonu yedeği (macOS)
# Tüm teklifleri (veri + PDF) ~/YanarYedek/Yedekler klasörüne indirir. launchd her gün 18:00'de ve oturum açılışında çalıştırır.
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
hata() { yaz "HATA: $1"; exit 1; }

EMAIL="$(cat "$DIR/eposta.txt" 2>/dev/null)"
PASS="$(security find-generic-password -s 'YanarSomineTeklif' -a "$EMAIL" -w 2>/dev/null)"
[ -n "$EMAIL" ] && [ -n "$PASS" ] || hata "Giriş bilgisi bulunamadı, Kurulum.command'ı yeniden çalıştırın."

# 1) Giriş
js giris "$EMAIL" "$PASS" > "$TMP/giris.json"
curl -sS -f -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $KEY" -H 'Content-Type: application/json' \
  --data-binary @"$TMP/giris.json" -o "$TMP/token.json" || hata "Giriş yapılamadı (e-posta/şifre ya da internet)."
TOKEN="$(js token "$TMP/token.json")"
[ -n "$TOKEN" ] || hata "Giriş yapılamadı."
AUTH="Authorization: Bearer $TOKEN"

# 2) Teklif verileri
curl -sS -f "$URL/rest/v1/docs?collection=eq.quotes&select=id,data,updated_at&order=id" -H "apikey: $KEY" -H "$AUTH" \
  -o "$VERI/teklifler-$BUGUN.json" || hata "Teklif verileri indirilemedi."
ADET="$(js csv "$VERI/teklifler-$BUGUN.json" "$VERI/teklif-listesi-$BUGUN.csv")"

# 3) PDF'ler (yeni veya değişenler)
YENI=0; PDFHATA=""; OFF=0
while :; do
  printf '{"prefix":"","limit":1000,"offset":%d,"sortBy":{"column":"name","order":"asc"}}' "$OFF" > "$TMP/q.json"
  if ! curl -sS -f -X POST "$URL/storage/v1/object/list/teklifler" -H "apikey: $KEY" -H "$AUTH" -H 'Content-Type: application/json' \
       --data-binary @"$TMP/q.json" -o "$TMP/liste.json"; then PDFHATA=" (PDF listesi alınamadı)"; break; fi
  N="$(js sayi "$TMP/liste.json")"
  while IFS='|' read -r AD TS EPOCH YEREL; do
    [ -n "$AD" ] || continue
    HED="$PDF/$YEREL"
    if [ ! -f "$HED" ] || [ "$(stat -f %m "$HED")" -lt $((EPOCH - 2)) ]; then
      ENC="$(printf '%s' "$AD" | sed 's/ /%20/g')"
      if curl -sS -f "$URL/storage/v1/object/teklifler/$ENC" -H "apikey: $KEY" -H "$AUTH" -o "$TMP/p.pdf"; then
        mv "$TMP/p.pdf" "$HED"; touch -t "$TS" "$HED"; YENI=$((YENI + 1))
      else PDFHATA=" (bazı PDF'ler indirilemedi)"; fi
    fi
  done <<< "$(js pdfler "$TMP/liste.json" "$VERI/teklifler-$BUGUN.json")"
  [ "$N" -eq 1000 ] || break
  OFF=$((OFF + 1000))
done

yaz "Tamam: $ADET teklif kaydı, $YENI yeni/değişen PDF$PDFHATA"
