# ser.ps1 -- doc/ghi UART cho board XC3399FR
# Dung: ser.ps1 [-Cmd "<lenh>"] [-Secs N] [-Baud N] [-Port COMx] [-NoNewline] [-Raw]
param(
  [string]$Cmd = $null,
  [int]$Secs = 4,
  [int]$Baud = 1500000,
  [string]$Port = "COM3",
  [switch]$NoNewline,
  [switch]$Raw
)

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
$sp.Handshake  = [System.IO.Ports.Handshake]::None
$sp.DtrEnable  = $false     # tranh reset board ngoai y muon
$sp.RtsEnable  = $false
$sp.ReadTimeout  = 200
$sp.WriteTimeout = 2000

try { $sp.Open() } catch { Write-Output "ERR_OPEN: $($_.Exception.Message)"; exit 1 }

Start-Sleep -Milliseconds 150
$sp.DiscardInBuffer()

if ($null -ne $Cmd) {
  if ($NoNewline) { $sp.Write($Cmd) } else { $sp.Write("$Cmd`n") }
}

$sb  = New-Object System.Text.StringBuilder
$buf = New-Object byte[] 8192
$deadline = (Get-Date).AddSeconds($Secs)
$lastData = Get-Date

while ((Get-Date) -lt $deadline) {
  try {
    $n = $sp.Read($buf, 0, $buf.Length)
    if ($n -gt 0) {
      [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $n))
      $lastData = Get-Date
    }
  } catch [TimeoutException] {
    # im lang > 1.2s sau khi da co du lieu -> ket thuc som
    if ($sb.Length -gt 0 -and ((Get-Date) - $lastData).TotalSeconds -gt 1.2) { break }
  }
}

$sp.Close()
$sp.Dispose()

$out = $sb.ToString()
if ($out.Length -eq 0) { Write-Output "<KHONG CO DU LIEU: $Secs giay im lang o $Baud baud>"; exit 0 }

if ($Raw) {
  Write-Output $out
} else {
  # loc ANSI escape + CR de doc cho de
  $clean = $out -replace "`e\[[0-9;?]*[a-zA-Z]", "" -replace "`r", ""
  Write-Output $clean
}
