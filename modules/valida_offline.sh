#!/usr/bin/env bash
# =============================================================================
# valida_offline.sh — D-25: validación interna de jugadores (log viejo vs nuevo)
# Uso:
#   valida_offline.sh --baseline         # (semana 1, online-mode=true)
#                                        #  barre TODO el journal y guarda los
#                                        #  (xuid, gamertag) originales.
#   valida_offline.sh --watch            # (semana 2+, online-mode=false) revisa
#                                        #  conexiones recientes: las que NO
#                                        #  están en la línea de base se marcan
#                                        #  como "nuevas" y avisan por Discord.
#   valida_offline.sh --check <num>      # debug: conexiones de las últimas N líneas
# Fuente de verdad: journal del servicio (como status.sh). No requiere más.
# =============================================================================
set -euo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

BASELINE="$MC_CONFIG_DIR/baseline.tsv"        # xuid<TAB>gamertag  (semana 1)
NUEVOS="$MC_LOG_DIR/ingresos.csv"             # fecha,gamertag,xuid,estado
SEEN="$MC_LOG_DIR/valida.seen.tsv"
mkdir -p "$MC_CONFIG_DIR" "$MC_LOG_DIR"

log() { echo "[$(date '+%F %T')] $*"; }

# Extrae pares (xuid gamertag) del journal: "Player connected: NAME, xuid: X"
# XUID real es numérico; clientes no-originales pueden mandar otra cadena.
pares_del_journal() {  # $1 = n líneas a mirar (-n N) o $1 vacío = desde arranque
  journalctl -u "$MC_SERVICE" --no-pager -o cat ${1:+-n "$1"} 2>/dev/null \
    | grep "Player connected" \
    | sed -E 's/.*Player connected: ([^,]+), xuid: ([^,\r\n]+).*/\2\t\1/' \
    | awk -F '\t' '!seen[$0]++'
}

cmd_baseline() {
  log "Barriendo journal completo para construir la línea de base... (semana 1, online-mode=true)"
  pares_del_journal > "$BASELINE"
  local n; n=$(wc -l < "$BASELINE")
  log "Línea de base con $n pares (xuid, gamertag). Guardada en $BASELINE"
}

cmd_watch() {
  [[ -s "$BASELINE" ]] || { log "ERROR: no hay $BASELINE (ejecuta --baseline al final de la semana 1)"; exit 1; }
  local line xuid gamertag razon estado
  pares_del_journal 5000 | while IFS=$'\t' read -r xuid gamertag; do
    # ¿ya visto antes? (baseline o previos)
    if grep -qF "$xuid" "$BASELINE"; then
      estado="original"
    elif grep -qF "$xuid" "$NUEVOS"; then
      estado="ya_registrado"
    else
      estado="NUEVO"
      log "⚠️ Conexión nuevo par (posible no-premium): gamertag=$gamertag xuid=$xuid"
      if [[ -n "$MC_STATUS_WEBHOOK" ]]; then
        curl -fsS --max-time 15 -H "Content-Type: application/json" \
             -d "{\"content\": \"⚠️ **Jugador nuevo** (no estaba en la línea de base de la semana 1): \`$gamertag\` (xuid $xuid). Verificar si tiene el código de acceso.\"}" \
             "$MC_STATUS_WEBHOOK" >/dev/null || log "WARN: webhook falló"
      fi
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$gamertag,$xuid,$estado" >> "$NUEVOS"
  done
  log "Revisión lista. Registro acumulado → $NUEVOS"
}

cmd_check() {
  echo "== Últimos pares conectados =="
  local i=0
  pares_del_journal "${1:-100}" | while IFS=$'\t' read -r xuid g; do
    local est="nuevo"
    grep -qF "$xuid" "$BASELINE" 2>/dev/null && est="original"
    printf '%s\t%s\t%s\n' "$xuid" "$g" "$est"
  done
}

case "${1:-}" in
  --baseline) cmd_baseline ;;
  --watch)    cmd_watch ;;
  --check)    cmd_check "${2:-100}" ;;
  *) echo "uso: valida_offline.sh --baseline | --watch | --check [n]"; exit 1 ;;
esac