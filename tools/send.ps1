# send.ps1 -- day file base64 qua UART vao board, trong MOT phien cong
param(
  [string]$Port = "COM3",
  [int]$Baud = 1500000,
  [string]$User = "root",
  [string]$Pass = "cuhanh123",
  [string]$B64File,
  [string]$Remote = "/tmp/dtb.b64",
  [int]$Chunk = 1024
)

$data = [System.IO.File]::ReadAllText($B64File).Trim()
Write-Output "B64 len = $($data.Length)"

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.DtrEnable = $false
$sp.RtsEnable = $false
$sp.ReadTimeout = 150
$sp.WriteTimeout = 5000
try { $sp.Open() } catch { Write-Output "ERR_OPEN: $($_.Exception.Message)"; exit 1 }

$acc = New-Object System.Text.StringBuilder
$buf = New-Object byte[] 8192

function Pump([int]$ms) {
  $end = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $end) {
    try { $n = $sp.Read($buf,0,$buf.Length); if ($n -gt 0) { [void]$acc.Append([System.Text.Encoding]::UTF8.GetString($buf,0,$n)) } }
    catch [TimeoutException] { }
  }
}
function Snap { $s = $acc.ToString(); [void]$acc.Clear(); return ($s -replace "`e\[[0-9;?]*[a-zA-Z]","" -replace "`r","") }

# --- dang nhap ---
$sp.Write("`n"); Pump 800; [void]$acc.Clear()
$sp.Write("`n"); Pump 1200
$cur = $acc.ToString()
if ($cur -match "login:") {
  [void]$acc.Clear(); $sp.Write("$User`n"); Pump 1500
  [void]$acc.Clear(); $sp.Write("$Pass`n"); Pump 3000
  $r = Snap
  if ($r -match "incorrect") { Write-Output "LOGIN_FAIL"; $sp.Close(); exit 2 }
  Write-Output "LOGIN_OK"
} else { Write-Output "SHELL_SAN_SANG" }

# --- tat echo cho nhanh, tat pager ---
$sp.Write("stty -echo; export TERM=dumb PAGER=cat`n"); Pump 800; [void]$acc.Clear()
$sp.Write(": > $Remote`n"); Pump 500; [void]$acc.Clear()

# --- gui tung khuc ---
$total = [math]::Ceiling($data.Length / $Chunk)
for ($i = 0; $i -lt $total; $i++) {
  $part = $data.Substring($i * $Chunk, [math]::Min($Chunk, $data.Length - $i * $Chunk))
  $sp.Write("printf '%s' '$part' >> $Remote`n")
  Pump 90
  [void]$acc.Clear()
  if (($i % 5) -eq 0) { Write-Output "  ... khuc $($i+1)/$total" }
}

# --- kiem tra ---
$sp.Write("stty echo`n"); Pump 400; [void]$acc.Clear()
$sp.Write("wc -c < $Remote`n"); Pump 1500
Write-Output ("REMOTE_B64_BYTES: " + (Snap).Trim())

$sp.Close(); $sp.Dispose()
