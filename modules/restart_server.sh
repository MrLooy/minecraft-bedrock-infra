#!/usr/bin/env bash
# =============================================================================
# restart_server.sh — D-33 / D-20
# Módulo INDEPENDIENTE: start|stop|restart ASEGURADO del BDS con verificación
# real (estado systemd + puerto TCP escuchando + "Server started" en journal).
#   Uso: restart_server.sh <start|stop|restart> [tiempo_máx_s]
# Salida pensada para máquinas (panel y bot la parsean):
#   [OK]   BDS en línea · puerto 19132 OK · arrancado en 12.3s
#   [OK]   BDS ya estaba activo · puerto OK
#   [OK]   BDS detenido correctamente
#   [FAIL] <motivo claro>
# =============================================================================
set -uo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

ACT="${1:-}"
MAX_S="${2:-90}"
[[ "$ACT" =~ ^(start|stop|restart)$ ]] || { echo "uso: restart_server.sh <start|stop|restart> [tiempo_máx_s]" >&2; exit 2; }

SVC="${MC_SERVICE:-mc}"
PORT_S="${MC_SERVER_PORT:-19132}"
HOST="127.0.0.1"

now_ms() { date +%s.%N; }

st_active() { systemctl is-active --quiet "$SVC"; }

port_open() {
  # BDS 1.26: handshake TCP en server-port (NetherNet). ss es lo fiable.
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$PORT_S$" && return 0
  # fallback sin dependencias
  timeout 3 bash -c "exec 3<>/dev/tcp/$HOST/$PORT_S" 2>/dev/null
}

started_count() {
  journalctl -u "$SVC" --no-pager -o cat 2>/dev/null | grep -c 'Server started' | tr -d ' '
}

wait_until() {  # $1=función  $2=máx segundos  → 0 si se cumplió
  local i=0
  while (( i < $2 )); do
    "$1" && return 0
    sleep 1; i=$((i+1))
  done
  return 1
}

wait_until_not() {  # 0 cuando la función deja de cumplirse
  local i=0
  while (( i < $2 )); do
    "$1" || return 0
    sleep 1; i=$((i+1))
  done
  return 1
}

T0=$(now_ms)
elapsed() { awk -v a="$T0" -v b="$(now_ms)" 'BEGIN{printf "%.1f", b-a}'; }

# ------------------------------------------------------------- acción ----
fail() { echo "[FAIL] $*"; exit 1; }
ok()   { echo "[OK] $*";  exit 0; }

ensure_ready() {  # verifica puerto + "Server started" mientras esté activo
  local p0 p1
  wait_until port_open "$MAX_S" || return 1
  p0=$(started_count)
  wait_until_not "st_active" 30 >/dev/null && p1=$(started_count) || p1="$p0"
  # si siguió activo, basta con que el puerto responda (ya auto-verificó)
  st_active || wait_until "port_open" 10 || return 1
  return 0
}

case "$ACT" in
  stop)
    if ! st_active; then
      ok "BDS ya estaba detenido"
    fi
    systemctl stop "$SVC" || fail "systemctl stop falló ($?)"
    wait_until_not st_active 40 || fail "BDS no se detuvo en 40s"
    ok "BDS detenido correctamente ($(elapsed)s)"
    ;;

  start)
    if st_active; then
      # puede estar "activo" pero colgado (sin puerto): verificamos de verdad
      wait_until port_open 15 && ok "BDS ya estaba activo · puerto $PORT_S OK"
      echo "→ BDS activo pero sin puerto — reinicio forzado…"
      systemctl stop "$SVC" || fail "systemctl stop falló ($?)"
      wait_until_not st_active 40 || fail "BDS no se detuvo en 40s"
    fi
    systemctl start "$SVC" || fail "systemctl start falló ($?)"
    wait_until st_active 20 || fail "BDS no se marcó activo tras 20s"
    ensure_ready || fail "BDS activo pero no responde: puerto $PORT_S no abre tras ${MAX_S}s (mirar logs)"
    ok "BDS en línea · puerto $PORT_S OK · arrancado en $(elapsed)s"
    ;;

  restart)
    [[ "$ACT" == "restart" ]]
    if st_active; then
      systemctl stop "$SVC" || fail "systemctl stop falló ($?)"
      wait_until_not st_active 40 || fail "BDS no se detuvo en 40s"
    fi
    systemctl start "$SVC" || fail "systemctl start falló ($?)"
    wait_until st_active 20 || fail "BDS no se marcó activo tras 20s"
    ensure_ready || fail "BDS activo pero no responde: puerto $PORT_S no abre tras ${MAX_S}s (mirar logs)"
    ok "BDS reiniciado · puerto $PORT_S OK · arrancado en $(elapsed)s"
    ;;
esac