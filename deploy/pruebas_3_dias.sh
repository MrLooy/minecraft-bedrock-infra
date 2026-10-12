#!/usr/bin/env bash
# =============================================================================
# pruebas_3_dias.sh — D-24: prueba de reembolso (ToS §7.2, 3 días)
# Ejecutar EN EL VPS el MISMO DÍA de la compra, con el server en producción.
#   Uso:  sudo bash pruebas_3_dias.sh [DUracionMin]   (def: 30 min)
# Criterios de fallo:
#   - RSS de bedrock_server > 3.2 GiB (D-12)  → plan B / reembolso
#   - el proceso se murió o reinició (crash)
#   - el puerto TCP 19132 dejó de escuchar (handshake NetherNet, BDS 1.26+)
# La PRUEBA DE RED (ping/jitter/pérdida desde Peru) va en
# deploy/prueba_cliente.ps1, que corre en la PC del admin.
# =============================================================================
set -euo pipefail

source /opt/mcserver/config/mc.conf
MIN="${1:-30}"
LOG="$MC_LOG_DIR/prueba3dias-$(date +%Y%m%d-%H%M).log"
mkdir -p "$MC_LOG_DIR"
exec >"$LOG" 2>&1

echo "== Prueba 3 días — VPS == $(date)"
echo "Servicio: $MC_SERVICE · duración: ${MIN} min → ver ${LOG}"
echo

fail=0
START=$(date +%s)
END=$((START + MIN * 60))

# muestreo cada 60 s
echo "hora | RAM_BDS(kb) | RSS_BDS(kb) | free(kb) | load | escuchaTCP19132"
while (( $(date +%s) < END )); do
  ram=$(systemctl show "$MC_SERVICE" --property=MemoryCurrent --value 2>/dev/null || echo 0)

  pid=$(pgrep -f "/opt/mcserver/bedrock_server" | head -1 || true)
  rss=0
  if [[ -n "$pid" ]]; then
    rss=$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null || echo 0)
  fi

  freekb=$(awk '/^MemFree|^MemAvailable/{print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
  load=$(cut -d' ' -f1 /proc/loadavg)
  escucha="no"
  ss -tln 2>/dev/null | grep -q ":${MC_PORT:-19132} " && escucha="sí"

  echo "$(date '+%H:%M:%S') | $ram | $rss | $freekb | $load | $escucha"

  # criterios
  rss_mb=$(( rss / 1024 ))
  if (( rss_mb > 3200 )); then
    echo "FALLO: RSS $rss_mb MB > 3200 MB → pedir reembolso (D-12)"; fail=1
  fi
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
    echo "FALLO: el proceso BDS no existe → crash/reinicio"; fail=1
  fi
  if [[ "$escucha" == "no" ]]; then
    echo "FALLO: puerto $MC_PORT TCP no escucha (handshake NetherNet)"; fail=1
  fi

  sleep 60
done

echo
echo "== RESUMEN =="
if (( fail )); then
  echo "RESULTADO: FALLO → ejecutar reembolso antes del día 3 (contacto: support@example.com)."
  exit 1
fi
echo "RESULTADO: OK (RAM, proceso y puerto estables)."
echo "Falta confirmar la red desde Peru con deploy/prueba_cliente.ps1."