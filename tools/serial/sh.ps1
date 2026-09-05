# sh2.ps1 -- login UART chac tay: xa buffer, cho dung prompt, thu nhieu password
param(
  [string]$Port = "COM3",
  [int]$Baud = 1500000,
  [string]$User = "root",
  [string[]]$Passes = @("cuhanh123","1234"),
  [string[]]$Cmds = @(),
  [int]$CmdWait = 20
)
$ErrorActionPreference = "Stop"
$sp = New-Object System.IO.Ports.SerialPort $Port,$Baud,([System.IO.Ports.Parity]::None),8,([System.IO.Ports.StopBits]::One)
$sp.Handshake=[System.IO.Ports.Handshake]::None
$sp.DtrEnable=$false; $sp.RtsEnable=$false
$sp.ReadTimeout=120; $sp.WriteTimeout=5000
try { $sp.Open() } catch { Write-Output "ERR_OPEN: $($_.Exception.Message)"; exit 1 }

$acc = New-Object System.Text.StringBuilder
$buf = New-Object byte[] 16384
function Pump([int]$ms){
  $end=(Get-Date).AddMilliseconds($ms)
  while((Get-Date) -lt $end){
    try{$n=$sp.Read($buf,0,$buf.Length); if($n -gt 0){[void]$acc.Append([Text.Encoding]::UTF8.GetString($buf,0,$n))}}catch{}
  }
}
function Txt(){ return ($acc.ToString() -replace "`e\[[0-9;?]*[a-zA-Z]","" -replace "`e\][0-9];?","" -replace "`r","") }
function Clr(){ [void]$acc.Clear() }
function WaitFor([string]$pat,[int]$secs){
  $end=(Get-Date).AddSeconds($secs)
  while((Get-Date) -lt $end){
    try{$n=$sp.Read($buf,0,$buf.Length); if($n -gt 0){[void]$acc.Append([Text.Encoding]::UTF8.GetString($buf,0,$n))}}catch{}
    if((Txt) -match $pat){return $true}
  }
  return $false
}

# 1. Xa sach. KHONG gui Ctrl-C truoc: neu roi trung luc U-Boot dem nguoc thi
#    no ngat autoboot va board mac o prompt '=>'.
$sp.Write("`n"); Pump 1500
$t0 = Txt
if($t0 -match "=>\s*$" -or $t0 -match "Fine3399\s*=>"){
  Write-Output "U_BOOT_PROMPT -> gui 'boot', doi he thong len"
  Clr; $sp.Write("boot`n")
  if(WaitFor "login:|[#\$]\s*$" 120){ Write-Output "DA_BOOT_LAI_DUOC" }
  else { Write-Output "BOOT_LAI_THAT_BAI"; $sp.Close(); exit 4 }
}
Clr; Pump 2500          # doi moi thu troi qua
Clr

$loggedIn=$false
foreach($p in $Passes){
  $sp.Write("`n"); Pump 1200
  $t = Txt
  if($t -match "(@@>|[#\$])\s*$" -and $t -notmatch "login:"){ Write-Output "DA_CO_SHELL"; $loggedIn=$true; break }
  if($t -notmatch "login:"){ Clr; $sp.Write("`n"); Pump 1500; $t=Txt }
  if($t -match "login:"){
    Clr; $sp.Write("$User`n")
    if(WaitFor "[Pp]assword:" 8){
      Clr; $sp.Write("$p`n"); Pump 4000
      $r = Txt
      if($r -match "incorrect|Login incorrect"){ Write-Output "SAI_PASS: $p"; Clr; continue }
      Write-Output "LOGIN_OK (pass=$p)"; $loggedIn=$true; Clr; break
    }
  }
}
if(-not $loggedIn){ Write-Output "KHONG_DANG_NHAP_DUOC"; Write-Output (Txt); $sp.Close(); exit 2 }

$sp.Write("export TERM=dumb PAGER=cat SYSTEMD_PAGER=cat LC_ALL=C`n"); Pump 900; Clr
$sp.Write("PS1='@@> '`n"); Pump 900; Clr

foreach($c in $Cmds){
  Clr
  $sp.Write("$c`n")
  # doi den khi prompt '@@>' xuat hien LAI (sau dong echo lenh), hoac het CmdWait
  $end=(Get-Date).AddSeconds($CmdWait)
  while((Get-Date) -lt $end){
    try{$n=$sp.Read($buf,0,$buf.Length); if($n -gt 0){[void]$acc.Append([Text.Encoding]::UTF8.GetString($buf,0,$n))}}catch{}
    $t=Txt
    # bo dong dau (echo lenh) roi tim prompt trong phan con lai
    $i=$t.IndexOf("`n")
    if($i -ge 0 -and $t.Substring($i) -match "@@>"){ break }
  }
  Write-Output "########## $c"
  Write-Output (Txt)
}
$sp.Close(); $sp.Dispose()
