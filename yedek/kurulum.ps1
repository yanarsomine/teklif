# Yanar Şömine Teklif Programı — gün sonu yedeği kurulumu
# Bir kez çalıştırılır: giriş bilgilerini şifreli kaydeder, her gün 18:00 görevini oluşturur ve ilk yedeği alır.
$ErrorActionPreference = 'Stop'
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ''
Write-Host 'Yanar Şömine teklif yedeği kuruluyor...' -ForegroundColor Cyan
Write-Host 'Açılan pencereye teklif programına giriş yaptığınız e-posta ve şifreyi yazın.'
Write-Host 'Şifre bu bilgisayarda, yalnızca bu Windows kullanıcısının açabileceği şekilde şifreli saklanır.'
$cred = Get-Credential -Message 'Teklif programı giriş bilgileri (e-posta ve şifre)'
if (-not $cred) { Write-Host 'İptal edildi.'; exit 1 }
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
