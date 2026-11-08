#!/bin/bash
# Yanar Şömine Teklif Programı — gün sonu yedeği kurulumu (macOS)
# Bir kez çalıştırılır: dosyaları ~/YanarYedek klasörüne kopyalar, giriş bilgisini Anahtar Zinciri'ne kaydeder,
# her gün 18:00 (ve oturum açılışında) çalışacak görevi kurar ve ilk yedeği alır.
SRC="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/YanarYedek"
PLIST="$HOME/Library/LaunchAgents/com.yanarsomine.teklifyedek.plist"
echo ""
echo "Yanar Şömine teklif yedeği kuruluyor..."
mkdir -p "$DIR" "$HOME/Library/LaunchAgents"
cp "$SRC/yedek.sh" "$SRC/yardimci.js" "$SRC/Simdi-Yedekle.command" "$SRC/BENIOKU.txt" "$DIR/" 2>/dev/null
chmod +x "$DIR/yedek.sh" "$DIR/Simdi-Yedekle.command"

echo ""
echo "Teklif programına giriş yaptığınız bilgileri girin."
echo "Şifre yazarken ekranda görünmez; Mac'in Anahtar Zinciri'nde güvenle saklanır."
read -r -p "E-posta: " EMAIL
read -r -s -p "Şifre: " PASS; echo ""
[ -n "$EMAIL" ] && [ -n "$PASS" ] || { echo "E-posta ve şifre gerekli."; read -r -p "Kapatmak için Enter"; exit 1; }
printf '%s' "$EMAIL" > "$DIR/eposta.txt"
security delete-generic-password -s 'YanarSomineTeklif' >/dev/null 2>&1
security add-generic-password -s 'YanarSomineTeklif' -a "$EMAIL" -w "$PASS" -U >/dev/null || { echo "Anahtar Zinciri'ne kaydedilemedi."; exit 1; }
unset PASS

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.yanarsomine.teklifyedek</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$DIR/yedek.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>18</integer><key>Minute</key><integer>0</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>$DIR/Yedekler/hata-ayrintisi.txt</string>
</dict></plist>
EOF
mkdir -p "$DIR/Yedekler"
launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || launchctl unload "$PLIST" >/dev/null 2>&1
launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST"
echo "Görev kuruldu: her gün 18:00 (Mac uykudaysa uyanınca, kapalıysa oturum açılınca)."

echo "İlk yedek alınıyor..."
sleep 2
/bin/bash "$DIR/yedek.sh"
for i in $(seq 1 120); do [ -d "$DIR/.kilit" ] || break; sleep 1; done
tail -n 1 "$DIR/Yedekler/yedek-gunlugu.txt" 2>/dev/null
open "$DIR/Yedekler"
echo ""
read -r -p "Bitti. Kapatmak için Enter"
