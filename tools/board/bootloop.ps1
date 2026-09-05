# bootloop.ps1 -- measure boot reliability of the USB system disk.
#
# Reboots the board N times and records, for each boot, whether UAS enumeration
# stalled. Run from the workstation; the board only ever receives SHORT
# commands, because long command lines get corrupted over the 1.5 Mbaud UART
# and silently produce wrong data. Everything is parsed on this side.
#
#   .\bootloop.ps1 -N 10 -Tag UAS
#
# Output, one line per boot:
#   UAS boot=3 abort=0 qd=30 mode=UAS attach=4.425744
#
# abort=0 with attach under ~6 s  -> clean boot
# abort=1 with attach around 36 s -> the known 30 s stall (docs/storage.md, §4)
#
# Flip transports between runs with:  ./storage-transport.sh uas|bot
param(
  [int]$N = 10,
  [string]$Tag = "UAS",
  [string]$Port = "COM3",
  [string]$Out = ".\bootcycles.txt",
  [string]$LogDir = ".\bootlogs"
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sh   = Join-Path $here "..\serial\sh.ps1"
$slog = Join-Path $here "..\serial\serlog.ps1"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Field([string]$blob, [string]$cmd) {
  $lines = $blob -split "`n"
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match [regex]::Escape("########## $cmd")) {
      for ($j = $i + 1; $j -lt [Math]::Min($i + 6, $lines.Count); $j++) {
        $t = $lines[$j].Trim()
        if ($t -and $t -notmatch '^<' -and $t -notmatch '^@@>' -and $t -notmatch [regex]::Escape($cmd)) { return $t }
      }
    }
  }
  return "?"
}

for ($i = 1; $i -le $N; $i++) {
  $got = $false
  for ($k = 1; $k -le 4; $k++) {
    $r = (& $sh -Port $Port -CmdWait 45 -Cmds @(
            'dmesg | grep -c uas_eh_abort',
            'cat /sys/block/sda/device/queue_depth',
            'dmesg | grep -m1 Attached')) -join "`n"
    if ($r -notmatch 'KHONG_DANG_NHAP_DUOC' -and $r -notmatch 'SAI_PASS') { $got = $true; break }
    Start-Sleep -Seconds 8
  }
  if (-not $got) {
    $line = "$Tag boot=$i  UNREACHABLE"
  } else {
    $ab = Field $r 'dmesg | grep -c uas_eh_abort'
    $qd = Field $r 'cat /sys/block/sda/device/queue_depth'
    $at = Field $r 'dmesg | grep -m1 Attached'
    $ts = ''
    if ($at -match '\[\s*([0-9]+\.[0-9]+)\]') { $ts = $Matches[1] }
    $mode = if ($qd -eq '1') { 'BOT' } elseif ($qd -eq '30') { 'UAS' } else { "qd=$qd" }
    $line = "$Tag boot=$i abort=$ab qd=$qd mode=$mode attach=$ts"
  }
  Write-Output $line
  Add-Content -Path $Out -Value $line -Encoding utf8

  if ($i -lt $N) {
    & $sh -Port $Port -CmdWait 20 -Cmds @('(sleep 5; reboot) &') | Out-Null
    & $slog -Port $Port -Secs 105 -Out (Join-Path $LogDir "$Tag`_cycle$i.log") | Out-Null
  }
}
Write-Output "########## done: $N cycles ($Tag)"
