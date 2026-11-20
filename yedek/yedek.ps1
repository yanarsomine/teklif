# Yanar Şömine Teklif Programı — gün sonu yedeği
# Programdaki tüm kayıtları (teklifler, müşteriler, fiyatlar, ayarlar), teklif PDF'lerini ve müşteri dosyalarını bu klasördeki "Yedekler" klasörüne indirir.
# Görev Zamanlayıcı her gün çalıştırır; elle çalıştırmak için: yedek.ps1'e sağ tık > "PowerShell ile çalıştır".
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Dir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$URL    = 'https://kxwhxjwurzyhtdvcumap.supabase.co'
$KEY    = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt4d2h4and1cnp5aHRkdmN1bWFwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM3MTkyMTgsImV4cCI6MjEwOTI5NTIxOH0.-kMYzLUElYFE6TvcdjS76Fk8WKFM8Wjz6xDpNEtBCis'
$Hedef  = Join-Path $Dir 'Yedekler'
$VeriD  = Join-Path $Hedef 'Veri'
$PdfD   = Join-Path $Hedef 'PDF'
$MdD    = Join-Path $Hedef 'MusteriDosyalari'
$UrD    = Join-Path $Hedef 'UrunResimleri'
$Log    = Join-Path $Hedef 'yedek-gunlugu.txt'
$Bugun  = Get-Date -Format 'yyyy-MM-dd'
New-Item -ItemType Directory -Force -Path $VeriD, $PdfD, $MdD, $UrD | Out-Null

function Yaz($m) { Add-Content -Path $Log -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $m) -Encoding UTF8 }
function Utf8($resp) { [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) }
function Bildir($id, $veri) {
  # Programın Panel ekranındaki "Gün sonu yedeği" kutusu bu kaydı okur
  if (-not $script:H) { return }
  try {
    $veri.bilgisayar = $env:COMPUTERNAME; $veri.sistem = 'Windows'; $veri.zaman = (Get-Date).ToUniversalTime().ToString('o')
    $b = @{ collection = 'counter'; id = $id; data = $veri; updated_at = $veri.zaman } | ConvertTo-Json -Depth 5
    $h = $script:H.Clone(); $h['Prefer'] = 'resolution=merge-duplicates'
    Invoke-WebRequest -UseBasicParsing -Method Post -Uri "$URL/rest/v1/docs" -Headers $h -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) | Out-Null
  } catch { }
}
function Temiz($s) { ($s -replace '[\\/:*?"<>|]', '').Trim() }
function Liste($kova, $onek) {
  # Kovadaki tüm dosyalar (alt klasörler dahil), 1000'erli sayfalar
  $out = @(); $off = 0
  do {
    $q = @{ prefix = $onek; limit = 1000; offset = $off; sortBy = @{ column = 'name'; order = 'asc' } } | ConvertTo-Json
    $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "$URL/storage/v1/object/list/$kova" -Headers $script:H `
          -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($q))
    $objs = @((Utf8 $r | ConvertFrom-Json) | ForEach-Object { $_ })
    foreach ($o in $objs) {
      if (-not $o.name) { continue }
      $yol = if ($onek) { "$onek/$($o.name)" } else { $o.name }
      if ($null -eq $o.id) { $out += Liste $kova $yol }
      else { $o | Add-Member -NotePropertyName yol -NotePropertyValue $yol -Force; $out += $o }
    }
    $off += 1000
  } while ($objs.Count -eq 1000)
  return $out
}
function Indir($kova, $o, $yol) {
  # Dosya yoksa ya da sunucudaki daha yeniyse indirir; indirdiyse $true
  $uzak = [datetime]::Parse($(if ($o.updated_at) { $o.updated_at } else { $o.created_at })).ToLocalTime()
  if ((Test-Path -LiteralPath $yol) -and (Get-Item -LiteralPath $yol).LastWriteTime -ge $uzak.AddSeconds(-2)) { return $false }
  $enc = ($o.yol -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
  Invoke-WebRequest -UseBasicParsing -Uri "$URL/storage/v1/object/$kova/$enc" -Headers $script:H -OutFile $yol
  (Get-Item -LiteralPath $yol).LastWriteTime = $uzak
  return $true
}

try {
  # 1) Giriş (bilgiler kurulumda bu bilgisayara şifreli kaydedildi)
  $cred = Import-Clixml (Join-Path $Dir 'giris.xml')
  $body = @{ email = $cred.UserName; password = $cred.GetNetworkCredential().Password } | ConvertTo-Json
  $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "$URL/auth/v1/token?grant_type=password" `
        -Headers @{ apikey = $KEY } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  $tok = (Utf8 $r | ConvertFrom-Json).access_token
  $script:H = @{ apikey = $KEY; Authorization = "Bearer $tok" }; $H = $script:H

  # 2) Tüm kayıtlar (teklifler, müşteriler, fiyatlar, ayarlar…) — 1000'erli sayfalar, eksik inerse hata
  $parcalar = New-Object System.Collections.Generic.List[string]; $off = 0; $toplam = -1; $sayi = 0
  do {
    $hc = $script:H.Clone(); $hc['Prefer'] = 'count=exact'
    $r = Invoke-WebRequest -UseBasicParsing -Uri "$URL/rest/v1/docs?select=collection,id,data,updated_at&order=collection,id&limit=1000&offset=$off" -Headers $hc
    $txt = Utf8 $r
    $part = @(($txt | ConvertFrom-Json) | ForEach-Object { $_ })
    $cr = [string]$r.Headers['Content-Range']; if ($cr -match '/(\d+)$') { $toplam = [int]$Matches[1] }
    $ic = $txt.Trim(); if ($ic.Length -gt 2) { $parcalar.Add($ic.Substring(1, $ic.Length - 2)) }
    $sayi += $part.Count; $off += 1000
  } while ($part.Count -eq 1000)
  if ($toplam -ge 0 -and $sayi -ne $toplam) { throw "Kayıtlar eksik indi ($sayi / $toplam)" }
  $tumJson = '[' + ($parcalar -join ',') + ']'
  [IO.File]::WriteAllText((Join-Path $VeriD "tum-veri-$Bugun.json"), $tumJson, (New-Object Text.UTF8Encoding $false))
  $tum = @(($tumJson | ConvertFrom-Json) | ForEach-Object { $_ })
  $rows = @($tum | Where-Object { $_.collection -eq 'quotes' })
  $musteri = @($tum | Where-Object { $_.collection -eq 'musteriler' -and -not $_.data.silindi }).Count

  # Excel listesi (CSV, ; ayraçlı; çöp kutusundakiler hariç)
  $liste = foreach ($x in ($rows | Where-Object { -not $_.data.silindi })) {
    $d = $x.data
    $top = ''
    if ($d.totals) { $top = ($d.totals.PSObject.Properties | ForEach-Object { '{0} {1:N2}' -f $_.Name, [double]$_.Value }) -join ' + ' }
    [pscustomobject]@{
      'Teklif No'      = $d.no
      'Tarih'          = $d.date
      'Müşteri'        = $d.customer.name
      'Yetkili'        = $d.customer.contact
      'Telefon'        = $d.customer.phone
      'E-posta'        = $d.customer.email
      'Proje'          = $d.customer.project
      'Kalem sayısı'   = @($d.items).Count
      'Toplam'         = $top
      'Hazırlayan'     = $d.olusturan
      'Son güncelleme' = $x.updated_at
    }
  }
  $csv = ($liste | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join "`r`n"
  [IO.File]::WriteAllText((Join-Path $VeriD "teklif-listesi-$Bugun.csv"), $csv, (New-Object Text.UTF8Encoding $true))

  # 3) Dosyalar: teklif PDF'leri ve müşteri dosyaları (keşif çizimleri, fotoğraflar…) — yalnız yeni/değişenler
  $ad = @{}; foreach ($x in $rows) { $ad[$x.id] = $x.data.customer.name }
  $yeni = 0; $yeniDosya = 0; $pdfHata = ''
  try {
    foreach ($o in (Liste 'teklifler' '')) {
      if (-not $o.yol.EndsWith('.pdf')) { continue }
      $id = $o.yol.Substring(0, $o.yol.Length - 4)
      $m = Temiz ([string]$ad[$id])
      $dosya = if ($m) { "$id - $m.pdf" } else { "$id.pdf" }
      if (Indir 'teklifler' $o (Join-Path $PdfD $dosya)) { $yeni++ }
    }
  } catch { $pdfHata += ' (PDF indirilemedi: ' + $_.Exception.Message + ')' }
  try {
    foreach ($o in (Liste 'musteri-dosyalari' '')) {
      $hed = Join-Path $MdD ($o.yol -replace '/', '\')
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hed) | Out-Null
      if (Indir 'musteri-dosyalari' $o $hed) { $yeniDosya++ }
    }
  } catch { $pdfHata += ' (müşteri dosyaları indirilemedi: ' + $_.Exception.Message + ')' }
  try {
    foreach ($o in (Liste 'uploads' '')) {
      $hed = Join-Path $UrD ($o.yol -replace '/', '\')
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hed) | Out-Null
      if (Indir 'uploads' $o $hed) { $yeniDosya++ }
    }
  } catch { $pdfHata += ' (ürün resimleri indirilemedi: ' + $_.Exception.Message + ')' }

  Yaz (("Tamam: {0} kayıt ({1} teklif, {2} müşteri), {3} yeni/değişen PDF, {4} yeni müşteri dosyası" -f $sayi, @($rows).Count, $musteri, $yeni, $yeniDosya) + $pdfHata)
  Bildir 'backup' @{ teklif = @($rows).Count; musteri = $musteri; pdf = $yeni; dosya = $yeniDosya; kayit = $sayi; not = $pdfHata.Trim() }
} catch {
  Yaz ("HATA: " + $_.Exception.Message)
  Bildir 'backup-err' @{ hata = [string]$_.Exception.Message }
  exit 1
}
