# ubootrun.ps1 -- ngat autoboot cua U-Boot, chay lenh, roi boot
param(
  [string]$Port="COM3",[int]$Baud=1500000,
  [string[]]$Cmds=@(),
  [int]$HoldSecs=0,          # dung yen bao lau o prompt truoc khi boot
  [switch]$NoBoot
)
$p = New-Object System.IO.Ports.SerialPort $Port,$Baud,([System.IO.Ports.Parity]::None),8,([System.IO.Ports.StopBits]::One)
$p.Handshake=[System.IO.Ports.Handshake]::None; $p.DtrEnable=$false; $p.RtsEnable=$false; $p.ReadTimeout=100
$p.Open()
$nl=[char]10
$acc=New-Object System.Text.StringBuilder; $buf=New-Object byte[] 8192
function Pump([int]$ms){ $e=(Get-Date).AddMilliseconds($ms)
  while((Get-Date) -lt $e){ try{$n=$p.Read($buf,0,$buf.Length); if($n -gt 0){[void]$acc.Append([Text.Encoding]::UTF8.GetString($buf,0,$n))}}catch{} } }
function Txt(){ return ($acc.ToString() -replace "`e\[[0-9;?]*[a-zA-Z]","") }

Write-Output "Cho U-Boot... spam phim de ngat autoboot"
$deadline=(Get-Date).AddSeconds(90); $hit=$false
while((Get-Date) -lt $deadline){
  $p.Write(" ")            # space = ngat autoboot, khong phai ky tu lenh
  Pump 120
  if((Txt) -match "=>\s*$"){ $hit=$true; break }
}
if(-not $hit){ Write-Output "KHONG BAT DUOC U-BOOT PROMPT"; Write-Output ((Txt) | Select-Object -Last 1); $p.Close(); exit 1 }
Write-Output "==> DA VAO U-BOOT"
[void]$acc.Clear()
foreach($c in $Cmds){ Write-Output "   uboot> $c"; $p.Write("$c$nl"); Pump 900 }
Write-Output ((Txt) -replace "`r","")
if($HoldSecs -gt 0){ Write-Output "==> Dung yen $HoldSecs giay o prompt U-Boot"; Pump ($HoldSecs*1000) }
[void]$acc.Clear()
if(-not $NoBoot){ Write-Output "==> boot"; $p.Write("boot$nl"); Pump 3000 }
$p.Close(); $p.Dispose()
