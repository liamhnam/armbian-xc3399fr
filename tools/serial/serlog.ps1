# serlog.ps1 -- ghi lien tuc UART ra file, de bat tron boot log
param(
  [int]$Secs = 600,
  [int]$Baud = 1500000,
  [string]$Port = "COM3",
  [string]$Out = "boot.log"
)
$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.DtrEnable = $false
$sp.RtsEnable = $false
$sp.ReadTimeout = 300
try { $sp.Open() } catch { Write-Output "ERR_OPEN: $($_.Exception.Message)"; exit 1 }

$fs = [System.IO.File]::Open($Out, 'Create', 'Write', 'Read')
$buf = New-Object byte[] 16384
$deadline = (Get-Date).AddSeconds($Secs)
$total = 0
while ((Get-Date) -lt $deadline) {
  try {
    $n = $sp.Read($buf, 0, $buf.Length)
    if ($n -gt 0) { $fs.Write($buf, 0, $n); $fs.Flush(); $total += $n }
  } catch [TimeoutException] { }
}
$fs.Close(); $sp.Close(); $sp.Dispose()
Write-Output "DONE: da ghi $total byte vao $Out"
