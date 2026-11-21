# Yanar Şömine Teklif Programı — gün sonu yedeği kurulumu
# Bir kez çalıştırılır: giriş bilgilerini şifreli kaydeder, her gün 18:00 görevini oluşturur ve ilk yedeği alır.
$ErrorActionPreference = 'Stop'
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path

trap { Write-Host ''; Write-Host ('HATA: ' + $_.Exception.Message) -ForegroundColor Red; Read-Host 'Kapatmak için Enter'; exit 1 }
$URL = 'https://kxwhxjwurzyhtdvcumap.supabase.co'
$KEY = (Select-String -Path (Join-Path $Dir 'yedek.ps1') -Pattern "^\`$KEY\s*=\s*'([^']+)'").Matches[0].Groups[1].Value
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host ''
Write-Host 'Yanar Şömine teklif yedeği kuruluyor...' -ForegroundColor Cyan
Write-Host 'Teklif programına giriş yaptığınız e-posta ve şifreyi BU PENCEREYE yazın.'
Write-Host 'Şifre yazarken ekranda görünmez; bu bilgisayarda yalnız bu Windows kullanıcısının açabileceği şekilde şifreli saklanır.'
Write-Host ''
while ($true) {
  $email = (Read-Host 'E-posta').Trim()
  $sifre = Read-Host 'Şifre' -AsSecureString
  if (-not $email -or $sifre.Length -eq 0) { Write-Host 'E-posta ve şifre gerekli.' -ForegroundColor Yellow; continue }
  $cred = New-Object System.Management.Automation.PSCredential($email, $sifre)
  # Bilgiler doğru mu? Kaydetmeden önce programa giriş denenir
  try {
    $body = @{ email = $email; password = $cred.GetNetworkCredential().Password } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$URL/auth/v1/token?grant_type=password" -Headers @{ apikey = $KEY } `
      -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
    Remove-Variable body
    Write-Host 'Giriş doğrulandı.' -ForegroundColor Green
    break
  } catch {
    Write-Host 'Giriş yapılamadı: e-posta veya şifre hatalı (ya da internet yok). Tekrar deneyin.' -ForegroundColor Yellow
  }
}
$cred | Export-Clixml -Path (Join-Path $Dir 'giris.xml')

$saat = '18:00'
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $Dir 'yedek.ps1'))
$trg = New-ScheduledTaskTrigger -Daily -At $saat
$set = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'Yanar Somine Teklif Yedegi' -Action $act -Trigger $trg -Settings $set `
  -Description 'Teklif programındaki tüm teklifleri (veri + PDF) her gün yedekler.' -Force | Out-Null
Write-Host "Görev oluşturuldu: her gün $saat (bilgisayar kapalıysa açıldığında)." -ForegroundColor Green

Write-Host 'İlk yedek alınıyor...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'yedek.ps1')
$log = Join-Path $Dir 'Yedekler\yedek-gunlugu.txt'
if (Test-Path $log) { Write-Host (Get-Content $log -Tail 1 -Encoding UTF8) }
Start-Process explorer.exe (Join-Path $Dir 'Yedekler')
Write-Host ''
Read-Host 'Bitti. Kapatmak için Enter'
