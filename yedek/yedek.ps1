# Yanar Şömine Teklif Programı — gün sonu yedeği
# Tüm teklifleri (veri + PDF) bu klasördeki "Yedekler" klasörüne indirir.
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
$Log    = Join-Path $Hedef 'yedek-gunlugu.txt'
$Bugun  = Get-Date -Format 'yyyy-MM-dd'
New-Item -ItemType Directory -Force -Path $VeriD, $PdfD | Out-Null

function Yaz($m) { Add-Content -Path $Log -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $m) -Encoding UTF8 }
function Utf8($resp) { [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) }
function Temiz($s) { ($s -replace '[\\/:*?"<>|]', '').Trim() }

try {
  # 1) Giriş (bilgiler kurulumda bu bilgisayara şifreli kaydedildi)
  $cred = Import-Clixml (Join-Path $Dir 'giris.xml')
  $body = @{ email = $cred.UserName; password = $cred.GetNetworkCredential().Password } | ConvertTo-Json
  $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "$URL/auth/v1/token?grant_type=password" `
        -Headers @{ apikey = $KEY } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  $tok = (Utf8 $r | ConvertFrom-Json).access_token
  $H = @{ apikey = $KEY; Authorization = "Bearer $tok" }

  # 2) Teklif verileri
  $r = Invoke-WebRequest -UseBasicParsing -Uri "$URL/rest/v1/docs?collection=eq.quotes&select=id,data,updated_at&order=id" -Headers $H
  $json = Utf8 $r
  [IO.File]::WriteAllText((Join-Path $VeriD "teklifler-$Bugun.json"), $json, (New-Object Text.UTF8Encoding $false))
  $rows = $json | ConvertFrom-Json

  # Excel listesi (CSV, ; ayraçlı)
  $liste = foreach ($x in $rows) {
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
      'Son güncelleme' = $x.updated_at
    }
  }
  $csv = ($liste | ConvertTo-Csv -NoTypeInformation -Delimiter ';') -join "`r`n"
  [IO.File]::WriteAllText((Join-Path $VeriD "teklif-listesi-$Bugun.csv"), $csv, (New-Object Text.UTF8Encoding $true))

  # 3) PDF'ler (yeni veya değişenler)
  $ad = @{}; foreach ($x in $rows) { $ad[$x.id] = $x.data.customer.name }
  $yeni = 0; $off = 0; $pdfHata = ''
  try {
  do {
    $q = @{ prefix = ''; limit = 1000; offset = $off; sortBy = @{ column = 'name'; order = 'asc' } } | ConvertTo-Json
    $r = Invoke-WebRequest -UseBasicParsing -Method Post -Uri "$URL/storage/v1/object/list/teklifler" -Headers $H `
          -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($q))
    $objs = @((Utf8 $r | ConvertFrom-Json) | ForEach-Object { $_ })
    foreach ($o in $objs) {
      if (-not $o.name -or -not $o.name.EndsWith('.pdf')) { continue }
      $id = $o.name.Substring(0, $o.name.Length - 4)
      $musteri = Temiz ([string]$ad[$id])
      $dosya = if ($musteri) { "$id - $musteri.pdf" } else { "$id.pdf" }
      $yol = Join-Path $PdfD $dosya
      $uzak = [datetime]::Parse($o.updated_at).ToLocalTime()
      if (-not (Test-Path -LiteralPath $yol) -or (Get-Item -LiteralPath $yol).LastWriteTime -lt $uzak.AddSeconds(-2)) {
        Invoke-WebRequest -UseBasicParsing -Uri "$URL/storage/v1/object/teklifler/$([uri]::EscapeDataString($o.name))" -Headers $H -OutFile $yol
        (Get-Item -LiteralPath $yol).LastWriteTime = $uzak
        $yeni++
      }
    }
    $off += 1000
  } while ($objs.Count -eq 1000)
  } catch { $pdfHata = ' (PDF indirilemedi: ' + $_.Exception.Message + ')' }

  Yaz (("Tamam: {0} teklif kaydı, {1} yeni/değişen PDF" -f @($rows).Count, $yeni) + $pdfHata)
} catch {
  Yaz ("HATA: " + $_.Exception.Message)
  exit 1
}
