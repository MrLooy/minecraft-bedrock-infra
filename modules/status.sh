#!/usr/bin/env bash
# =============================================================================
# status.sh — D-16 / D-20
# Módulo INDEPENDIENTE: estado del server + contador de jugadores (cola Q1).
#   Uso:  status.sh           → JSON por stdout (estado + online)
#         status.sh --webhook → además publica en Discord SOLO si cambió el
#                                contador o pasó MC_STATUS_INTERVAL_S
#         status.sh --watch   → bucle (lo usa system/mc-status.timer? no: cron)
# Fuente de verdad: journal de systemd (conexiones desde el último arranque).
# No depende de ningún otro módulo salvo mc.conf.
# =============================================================================
set -euo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

STATE="$MC_LOG_DIR/status.state"
mkdir -p "$MC_LOG_DIR"

service_active() { systemctl is-active --quiet "$MC_SERVICE" 2>/dev/null; }

players_online() {
  # Reconstruye la sesión actual desde el último "Server started"
  local last line n_in n_out
  last=$(journalctl -u "$MC_SERVICE" --no-pager -o cat 2>/dev/null \
         | grep -n "Server started" | tail -1 | cut -d: -f1 || true)
  [[ -n "$last" ]] || { echo 0; return; }
  line=$(journalctl -u "$MC_SERVICE" --no-pager -o cat --since "-7 days" 2>/dev/null \
         | tail -n "+$last" || true)
  n_in=$(grep -c "Player connected" <<<"$line" || true)
  n_out=$(grep -c "Player disconnected" <<<"$line" || true)
  local n=$(( n_in - n_out ))
  if (( n < 0 )); then n=0; fi
  echo "$n"
}

uptime_s() {
  systemctl show "$MC_SERVICE" --property=ActiveEnterTimestamp --value 2>/dev/null \
    | xargs -I{} date -d "{}" +%s 2>/dev/null || echo 0
}

json() {
  local online active=0 version="desconocida" now started up_s=0
  now=$(date +%s)
  online=$(players_online)
  if service_active; then active=1; fi
  if [[ -f "$MC_VERSION_FILE" ]]; then version=$(cat "$MC_VERSION_FILE"); fi
  started=$(uptime_s)
  if [[ "$started" =~ ^[0-9]+$ ]]; then up_s=$(( now - started )); fi
  printf '{"active":%s,"online":%d,"max":%d,"version":"%s","uptime_s":%d,"ram_kb":%s}\n' \
    "$active" "$online" "$MC_MAX_PLAYERS" "$version" "$up_s" \
    "$(systemctl show "$MC_SERVICE" --property=MemoryCurrent --value 2>/dev/null | grep -E '^[0-9]+$' || echo 0)"
}

send_webhook() {  # $1 = json
  [[ -n "$MC_STATUS_WEBHOOK" ]] || return 0
  curl -fsS --max-time 15 -H "Content-Type: application/json" \
       -d "$1" "$MC_STATUS_WEBHOOK" >/dev/null || echo "WARN: webhook falló" >&2
}

main() {
  local j online prev last_ts now
  j=$(json)
  echo "$j"

  [[ "${1:-}" == "--webhook" ]] || exit 0
  online=$(python3 -c 'import json,sys;print(json.load(sys.stdin)["online"])' <<<"$j")
  prev=$(cut -d' ' -f1 "$STATE" 2>/dev/null || echo "-1")
  last_ts=$(cut -d' ' -f2 "$STATE" 2>/dev/null || echo "0")
  now=$(date +%s)

  # Publica si: cambió el contador, o toca el recordatorio periódico
  if [[ "$online" != "$prev" ]] || (( now - last_ts >= MC_STATUS_INTERVAL_S )); then
    local activo="🛑 caído"
    if python3 -c 'import json,sys;exit(0 if json.load(sys.stdin)["active"] else 1)' <<<"$j"; then
      activo="🟢 en línea"
    fi
    local payload
    payload=$(python3 -c 'import json,sys
activo, online, mx = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({"content": f"{activo} · jugadores: **{online}/{mx}** — intenta entrar cuando haya espacio."}))' \
      "$activo" "$online" "$MC_MAX_PLAYERS")
    send_webhook "$payload"
    echo "$online $now" > "$STATE"
  fi
}

main "${1:-}"
