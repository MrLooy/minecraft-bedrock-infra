# prueba_cliente.ps1 — Mide latencia/jitter/pérdida desde la PC del admin (Peru)
# Uso (PowerShell, como administrador o no):
#   .\prueba_cliente.ps1 -Ip 203.0.113.20 -Count 30
# Correr DOS veces el mismo día: una al mediodía y una de noche (horarios clave).
# Criterio: si pérdida > 0% de forma repetida → red inválida → reembolso.
param(
  [string]$Ip = "203.0.113.20",   # IP del VPS
  [int]$Count = 30                    # nº de pings por pasada
)

$ErrorActionPreference = "Stop"
$out = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "..\logs"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$ts  = Get-Date -Format "yyyyMMdd-HHmm"
$csv = "$out\ping-$Ip-$ts.csv"

Write-Host "Ping a $Ip -> $csv (n=$Count, ~$([math]::Ceiling($Count/10)) s)" -ForegroundColor Cyan

$ok = 0; $lost = 0; $rtts = @()
for ($i = 1; $i -le $Count; $i++) {
  $r = Test-Connection -ComputerName $Ip -Count 1 -ErrorAction SilentlyContinue
  $now = Get-Date
  if ($r -and $r.ResponseTime -ge 0) {
    $ok++
    $rtts += $r.ResponseTime
    "{0:HH:mm:ss},{1},{2}" -f $now, $r.Address, $r.ResponseTime | Add-Content $csv
  } else {
    $lost++
    "{0:HH:mm:ss},{1},TIMEOUT" -f $now, $Ip | Add-Content $csv
  }
  Start-Sleep -Milliseconds 150
}

$loss = [math]::Round(100 * $lost / $Count, 1)
$avg  = [math]::Round(($rtts | Measure-Object -Average).Average, 1)
$minp = [math]::Round(($rtts | Measure-Object -Minimum).Minimum, 1)
$maxp = [math]::Round(($rtts | Measure-Object -Maximum).Maximum, 1)
$jitter = 0
if ($rtts.Count -gt 2) {
  $d = @(); for ($k = 1; $k -lt $rtts.Count; $k++) { $d += [math]::Abs($rtts[$k] - $rtts[$k-1]) }
  $jitter = [math]::Round(($d | Measure-Object -Average).Average, 1)
}

Write-Host "`n=== Resultado ===" -ForegroundColor Cyan
"envíos=$Count  ok=$ok  perdidos=$lost"
"pérdida=$loss%   (0% = perfecto)"
"rtt  min/avg/max = $minp / $avg / $maxp ms"
"jitter promedio = $jitter ms"
if ($loss -gt 0) { Write-Host "⚠️  ¡Pérdida detectada! Con 15 jugadores esto cortará el juego." -ForegroundColor Yellow }
elseif ($avg -gt 120) { Write-Host "⚠️  Latencia alta ($avg ms) para jugar." -ForegroundColor Yellow }
else { Write-Host "✅ Red aceptable para 15 jugadores." -ForegroundColor Green }