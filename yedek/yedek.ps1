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
$UrD    = Join-Path $Hedef 'UrunResimleri'
$Log    = Join-Path $Hedef 'yedek-gunlugu.txt'
$Bugun  = Get-Date -Format 'yyyy-MM-dd'
New-Item -ItemType Directory -Force -Path $VeriD, $UrD | Out-Null

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
function Temiz($s) { (($s -replace '[\\/:*?"<>|]', '') -replace '\s+', ' ').Trim() }
function Para($t, $pb) { $c = if ($pb -eq 'EUR') { '€' } elseif ($pb -eq 'USD') { '$' } else { 'TL' }; return ([double]$t).ToString('N2', [Globalization.CultureInfo]'tr-TR') + ' ' + $c }
$DURUM = @{ yeni = 'Yeni talep'; plan = 'Keşif planlandı'; kesif = 'Keşif yapıldı'; teklif = 'Teklif verildi'; satis = 'Satış oldu'; vazgecti = 'Vazgeçti' }
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

  # Müşteri ve işler listesi (Excel): her iş bir satır — keşif, son teklif, anlaşılan satış tutarı, iskonto
  $mlist = @(); $qAll = @($rows | Where-Object { -not $_.data.silindi }); $fAll = @($tum | Where-Object { $_.collection -like 'musteriler/*/dosyalar' -and -not $_.data.silindi })
  foreach ($c in @($tum | Where-Object { $_.collection -eq 'musteriler' -and -not $_.data.silindi })) {
    $d = $c.data; $isler = @(@($d.isler) | Where-Object { $_ -and -not $_.silindi }); if (-not $isler.Count) { $isler = @($null) }
    foreach ($j in $isler) {
      $o = if ($j) { $j.sonTeklif } else { $d.sonTeklif }; $sv = if ($j -and [string]$j.durum -eq 'satis') { $j.satis } else { $null }
      $opb = if ($o) { if ($o.pb -eq 'TL' -or -not $o.pb) { 'TRY' } else { [string]$o.pb } } else { '' }
      $isk = ''; $iskp = ''
      if ($o -and $sv -and $o.tutar -and $opb -eq [string]$sv.pb) { $df = [double]$o.tutar - [double]$sv.tutar; if ([Math]::Abs($df) -gt 0.004) { $isk = Para $df $sv.pb; $iskp = '%' + ([Math]::Round($df / [double]$o.tutar * 100, 1)).ToString([Globalization.CultureInfo]'tr-TR') } }
      $jq = if ($j) { @($qAll | Where-Object { $_.data.jobId -eq $j.id }) } else { @($qAll | Where-Object { $_.data.customerId -eq $c.id }) }
      $jf = @($fAll | Where-Object { ($_.collection -split '/')[1] -eq $c.id -and ((-not $j) -or (-not $_.data.isId) -or $_.data.isId -eq $j.id) })
      $mlist += [pscustomobject]@{
        'Müşteri' = $d.ad; 'Telefon' = $d.telefon; 'E-posta' = $d.eposta
        'İl' = $(if ($j -and $j.il) { $j.il } else { $d.il }); 'İlçe' = $(if ($j -and $j.ilce) { $j.ilce } else { $d.ilce }); 'Adres' = $(if ($j -and $j.adres) { $j.adres } else { $d.adres })
        'İş' = $(if ($j) { $j.baslik } else { '' }); 'Durum' = $(if ($j) { if ($DURUM[[string]$j.durum]) { $DURUM[[string]$j.durum] } else { $j.durum } } else { '' })
        'Ürün / kapsam' = $(if ($j) { $j.urun } else { '' })
        'Keşif tarihi' = $(if ($j) { $j.kesifTarihi } else { '' }); 'Keşif notu' = $(if ($j) { $j.kesifNotu } else { '' })
        'Son teklif no' = $(if ($o -and $o.no) { $o.no } elseif ($jq.Count) { ($jq | Sort-Object { [string]$_.updated_at } -Descending | Select-Object -First 1).data.no } else { '' }); 'Teklif tarihi' = $(if ($o -and $o.tarih) { ([string]$o.tarih).Substring(0, [Math]::Min(10, ([string]$o.tarih).Length)) } else { '' })
        'Teklif tutarı' = $(if ($o -and $null -ne $o.tutar) { Para $o.tutar $opb } else { '' })
        'Anlaşılan satış tutarı' = $(if ($sv) { Para $sv.tutar $sv.pb } else { '' }); 'İskonto' = $isk; 'İskonto %' = $iskp
        'Satış tarihi' = $(if ($j -and $j.satisTarihi) { ([string]$j.satisTarihi).Substring(0, 10) } else { '' })
        'Programdaki teklifler' = (($jq | ForEach-Object { $_.data.no }) -join ', ')
        'Dosyalar' = $(if ($jf.Count) { (@('kesif','teklif','foto','diger') | ForEach-Object { $t = $_; $n = @($jf | Where-Object { ([string]$_.data.tur) -eq $t -or ($t -eq 'diger' -and @('kesif','teklif','foto') -notcontains [string]$_.data.tur) }).Count; if ($n) { "$n $(@{kesif='keşif';teklif='teklif';foto='fotoğraf';diger='diğer'}[$t])" } }) -join ', ' } else { '' })
        'İş notları' = $(if ($j) { $j.notlar } else { $d.notlar })
      }
    }
  }
  $mcsv = ($mlist | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join "`r`n"
  [IO.File]::WriteAllText((Join-Path $VeriD "musteri-ve-isler-$Bugun.csv"), $mcsv, (New-Object Text.UTF8Encoding $true))
  New-Item -ItemType Directory -Force -Path (Join-Path $Hedef 'Müşteriler') | Out-Null
  [IO.File]::WriteAllText((Join-Path (Join-Path $Hedef 'Müşteriler') 'Müşteri ve iş listesi.csv'), $mcsv, (New-Object Text.UTF8Encoding $true))

  # 3) Müşteri klasörleri: Yedekler\Müşteriler\<Müşteri adı>\ Teklifler · Resimler · Belgeler · Keşif + Müşteri bilgileri.txt
  #    (yalnız yeni/değişen dosyalar iner; çöp kutusundakiler alınmaz)
  $MusD = Join-Path $Hedef 'Müşteriler'
  $yeni = 0; $yeniDosya = 0; $eksik = 0; $pdfHata = ''
  $custs = @($tum | Where-Object { $_.collection -eq 'musteriler' -and -not $_.data.silindi })
  $say = @{}; foreach ($c in $custs) { $k = (Temiz ([string]$c.data.ad)).ToLower(); $say[$k] = 1 + [int]$say[$k] }
  $kl = @{}
  foreach ($c in $custs) {
    $n = Temiz ([string]$c.data.ad); $tek = $n -and $say[$n.ToLower()] -eq 1; if (-not $n) { $n = 'İsimsiz müşteri' }
    if (-not $tek) { $n = "$n - $(if ($c.data.kod) { Temiz ([string]$c.data.kod) } else { $c.id.Substring(0, [Math]::Min(6, $c.id.Length)) })" }
    $kl[$c.id] = $n
    $cd = Join-Path $MusD $n; New-Item -ItemType Directory -Force -Path $cd | Out-Null
    $d = $c.data
    $bilgi = @("Müşteri: $($d.ad)", "Telefon: $($d.telefon)", "E-posta: $($d.eposta)", "Adres: $((@($d.adres, $d.ilce, $d.il) | Where-Object { $_ }) -join ', ')", '', 'İşler:')
    foreach ($j in @($d.isler)) { if ($j -and -not $j.silindi) {
      $sat = ''; $tek = ''
      if ($j.sonTeklif) { $tek = '  son teklif: ' + $(if ($j.sonTeklif.no) { $j.sonTeklif.no + ' ' } else { '' }) + $(if ($null -ne $j.sonTeklif.tutar) { '(' + (Para $j.sonTeklif.tutar $j.sonTeklif.pb) + ')' } else { '' }) }
      if ([string]$j.durum -eq 'satis' -and $j.satis) {
        $sat = '  SATIŞ: ' + (Para $j.satis.tutar $j.satis.pb)
        $opb = if ($j.sonTeklif) { if ($j.sonTeklif.pb -eq 'TL' -or -not $j.sonTeklif.pb) { 'TRY' } else { [string]$j.sonTeklif.pb } } else { '' }
        if ($j.sonTeklif -and $j.sonTeklif.tutar -and $opb -eq [string]$j.satis.pb) { $df = [double]$j.sonTeklif.tutar - [double]$j.satis.tutar; if ($df -gt 0.004) { $sat += ' (iskonto ' + (Para $df $j.satis.pb) + ', %' + ([Math]::Round($df / [double]$j.sonTeklif.tutar * 100, 1)).ToString([Globalization.CultureInfo]'tr-TR') + ')' } }
        if ($j.satisTarihi) { $sat += '  satış tarihi: ' + ([string]$j.satisTarihi).Substring(0, 10) }
      }
      $bilgi += "- $($j.baslik)  [$(if ($DURUM[[string]$j.durum]) { $DURUM[[string]$j.durum] } else { $j.durum })]$(if ($j.kesifTarihi) { '  keşif: ' + $j.kesifTarihi })$tek$sat"
    } }
    if ($d.notlar) { $bilgi += ''; $bilgi += "Notlar: $($d.notlar)" }
    $bilgi += ''; $bilgi += "Yedek tarihi: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
    [IO.File]::WriteAllText((Join-Path $cd 'Müşteri bilgileri.txt'), ($bilgi -join "`r`n"), (New-Object Text.UTF8Encoding $true))
  }
  $kullanilan = @{}
  function Yer($klasor, $ad, $anahtar) {
    # Aynı klasörde aynı adlı iki dosya olursa ikincisine kısa ek koyar
    $y = Join-Path $klasor $ad
    if ($kullanilan.ContainsKey($y.ToLower()) -and $kullanilan[$y.ToLower()] -ne $anahtar) {
      $y = Join-Path $klasor ("{0} ({1}){2}" -f [IO.Path]::GetFileNameWithoutExtension($ad), $anahtar.Substring(0, [Math]::Min(5, $anahtar.Length)), [IO.Path]::GetExtension($ad))
    }
    $kullanilan[$y.ToLower()] = $anahtar; return $y
  }
  function Getir($kova, $uzak, $yerel, $zaman) {
    # Yerelde yoksa (ya da sunucudaki daha yeniyse) indirir; indirdiyse $true, sunucuda yoksa $null
    $uz = if ($zaman -is [datetime]) { $zaman } elseif ($zaman) { [datetime]::Parse([string]$zaman, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime() } else { $null }
    if (Test-Path -LiteralPath $yerel) { if (-not $uz -or (Get-Item -LiteralPath $yerel).LastWriteTime -ge $uz.AddSeconds(-2)) { return $false } }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $yerel) | Out-Null
    $enc = ($uzak -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $tmp = "$yerel.indiriliyor"
    try { Invoke-WebRequest -UseBasicParsing -Uri "$URL/storage/v1/object/$kova/$enc" -Headers $script:H -OutFile $tmp }
    catch { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }; return $null }
    Move-Item -LiteralPath $tmp -Destination $yerel -Force
    if ($uz) { (Get-Item -LiteralPath $yerel).LastWriteTime = $uz }
    return $true
  }
  # Teklif PDF'leri (programın kaydettiği hâliyle)
  foreach ($q in ($rows | Where-Object { -not $_.data.silindi })) {
    $cid = $q.data.customerId
    $kl2 = if ($cid -and $kl[$cid]) { $kl[$cid] } else { '_Müşteri dosyası olmayan teklifler\' + $(if (Temiz ([string]$q.data.customer.name)) { Temiz ([string]$q.data.customer.name) } else { 'İsimsiz' }) }
    $dosya = Temiz ([string]$q.data.no); if (-not $dosya) { $dosya = $q.id }
    $r2 = Getir 'teklifler' "$($q.id).pdf" (Yer (Join-Path (Join-Path $MusD $kl2) 'Teklifler') "$dosya.pdf" $q.id) $q.updated_at
    if ($r2 -eq $true) { $yeni++ } elseif ($null -eq $r2) { $eksik++ }
  }
  # Müşteriye eklenen resimler ve belgeler (asıl dosya adlarıyla)
  foreach ($f in ($tum | Where-Object { $_.collection -like 'musteriler/*/dosyalar' -and -not $_.data.silindi -and $_.data.assetId })) {
    $cid = ($f.collection -split '/')[1]; if (-not $kl[$cid]) { continue }
    $alt = switch ([string]$f.data.tur) { 'foto' { 'Resimler' } 'teklif' { 'Teklifler' } 'kesif' { 'Keşif' } default { 'Belgeler' } }
    $ad = Temiz ([string]$f.data.ad); if (-not $ad) { $ad = Split-Path -Leaf $f.data.assetId }
    if (-not [IO.Path]::GetExtension($ad)) { $ad += [IO.Path]::GetExtension([string]$f.data.assetId) }
    $r2 = Getir 'musteri-dosyalari' ([string]$f.data.assetId) (Yer (Join-Path (Join-Path $MusD $kl[$cid]) $alt) $ad $f.id) $null
    if ($r2 -eq $true) { $yeniDosya++ } elseif ($null -eq $r2) { $eksik++ }
  }
  if ($eksik) { $pdfHata += " ($eksik dosya arşivde yok; eksik teklif PDF'i, teklif programda açılınca arşive eklenir)" }
  try {
    foreach ($o in (Liste 'uploads' '')) {
      $hed = Join-Path $UrD ($o.yol -replace '/', '\')
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $hed) | Out-Null
      if (Indir 'uploads' $o $hed) { $yeniDosya++ }
    }
  } catch { $pdfHata += ' (ürün resimleri indirilemedi: ' + $_.Exception.Message + ')' }

  Yaz (("Tamam: {0} kayıt ({1} teklif, {2} müşteri), {3} yeni/değişen teklif PDF'i, {4} yeni dosya" -f $sayi, @($rows).Count, $musteri, $yeni, $yeniDosya) + $pdfHata)
  Bildir 'backup' @{ teklif = @($rows).Count; musteri = $musteri; pdf = $yeni; dosya = $yeniDosya; kayit = $sayi; not = $pdfHata.Trim() }
} catch {
  Yaz ("HATA: " + $_.Exception.Message)
  Bildir 'backup-err' @{ hata = [string]$_.Exception.Message }
  exit 1
}
