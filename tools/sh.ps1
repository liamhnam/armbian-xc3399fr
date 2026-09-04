# sh.ps1 -- dang nhap UART va chay lenh trong MOT phien cong duy nhat
# Dung: sh.ps1 -User root -Pass 1234 -Cmds @("uname -a","free -h")
param(
  [string]$Port = "COM3",
  [int]$Baud = 1500000,
  [string]$User = "root",
  [string]$Pass = "1234",
  [string[]]$Cmds = @(),
  [int]$CmdWait = 8
)

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.DtrEnable = $false
$sp.RtsEnable = $false
$sp.ReadTimeout = 150
try { $sp.Open() } catch { Write-Output "ERR_OPEN: $($_.Exception.Message)"; exit 1 }

$script:acc = New-Object System.Text.StringBuilder
$buf = New-Object byte[] 8192

function Pump {
  param([int]$Ms)
  $end = (Get-Date).AddMilliseconds($Ms)
  while ((Get-Date) -lt $end) {
    try {
      $n = $sp.Read($buf, 0, $buf.Length)
      if ($n -gt 0) { [void]$script:acc.Append([System.Text.Encoding]::UTF8.GetString($buf,0,$n)) }
    } catch [TimeoutException] { }
  }
}

function WaitFor {
  param([string]$Pat, [int]$Secs)
  $end = (Get-Date).AddSeconds($Secs)
  while ((Get-Date) -lt $end) {
    try {
      $n = $sp.Read($buf, 0, $buf.Length)
      if ($n -gt 0) { [void]$script:acc.Append([System.Text.Encoding]::UTF8.GetString($buf,0,$n)) }
    } catch [TimeoutException] { }
    if ($script:acc.ToString() -match $Pat) { return $true }
  }
  return $false
}

function Snap { $s = $script:acc.ToString(); [void]$script:acc.Clear(); return $s }

# --- reset ve trang thai sach ---
$sp.Write("`n"); Pump 400
$sp.Write("`n"); Pump 800
[void]$script:acc.Clear()
$sp.Write("`n"); Pump 1200
$cur = $script:acc.ToString()

# --- dang nhap neu can ---
if ($cur -match "login:") {
  [void]$script:acc.Clear()
  $sp.Write("$User`n")
  if (WaitFor "[Pp]assword:" 6) {
    [void]$script:acc.Clear()
    $sp.Write("$Pass`n")
    Pump 3000
    $r = Snap
    if ($r -match "Login incorrect|incorrect") {
      Write-Output "LOGIN_FAIL: sai user/password"
      $sp.Close(); $sp.Dispose(); exit 2
    }
    Write-Output "LOGIN_OK"
  } else {
    Write-Output "LOGIN_ERR: khong thay prompt Password"
    $sp.Close(); $sp.Dispose(); exit 3
  }
} elseif ($cur -match "[#\$]\s*$") {
  Write-Output "DA_DANG_NHAP_SAN"
} else {
  Write-Output "TRANG_THAI_LA:"
  Write-Output ($cur -replace "`e\[[0-9;?]*[a-zA-Z]","")
}

# --- tat phan trang de lenh khong bi ket o 'less' ---
$sp.Write("export TERM=dumb PAGER=cat SYSTEMD_PAGER=cat GIT_PAGER=cat`n"); Pump 700
[void]$script:acc.Clear()

foreach ($c in $Cmds) {
  [void]$script:acc.Clear()
  $sp.Write("$c`n")
  # doc cho den khi im lang 1.5s hoac het CmdWait
  $end = (Get-Date).AddSeconds($CmdWait)
  $last = Get-Date
  while ((Get-Date) -lt $end) {
    try {
      $n = $sp.Read($buf, 0, $buf.Length)
      if ($n -gt 0) { [void]$script:acc.Append([System.Text.Encoding]::UTF8.GetString($buf,0,$n)); $last = Get-Date }
    } catch [TimeoutException] {
      if ($script:acc.Length -gt 0 -and ((Get-Date)-$last).TotalSeconds -gt 1.5) { break }
    }
  }
  $o = Snap -replace "`e\[[0-9;?]*[a-zA-Z]","" -replace "`r",""
  Write-Output "########## $c"
  Write-Output $o
}

$sp.Close(); $sp.Dispose()
