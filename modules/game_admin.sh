#!/usr/bin/env bash
# =============================================================================
# game_admin.sh — D-34
# Módulo INDEPENDIENTE de gestión de OPs in-game desde el panel (solo root).
# "Kill switch": quitar/poner privilegios de un administrador que se descontrola.
#
# IMPORTANTE: Bedrock Dedicated Server **NO usa ops.json** (eso es de Java
# Edition y BDS lo ignora). La fuente de verdad es **permissions.json**, que se
# indexa por xuid. Por eso se trabaja así:
#   - Comandos de consola `op/deop <name>`: aplican EN VIVO y BDS actualiza
#     permissions.json por su cuenta.
#   - Edición directa de permissions.json (por xuid) como respaldo/garantía
#     (p. ej. si el jugador no está online en ese momento).
#   Uso:
#     game_admin.sh list                      → OPs actuales (name, level, xuid)
#     game_admin.sh op      <name> [xuid]     → da OP (nivel 4)
#     game_admin.sh deop    <name>            → quita OP (en vivo + permissions.json)
#     game_admin.sh survival <name>           → gamemode survival
#     game_admin.sh deop-all-except <name>    → quita OP a todos menos a uno
# =============================================================================
set -uo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

PERMS="$MC_HOME/permissions.json"          # fuente de verdad (BDS)
OPS_JSON="$MC_HOME/ops.json"               # legado de Java (solo se LEE como pista de xuids)
CONSOLA="$MC_HOME/modules/consola.sh"
OP_LEVEL="${OP_LEVEL:-4}"

fail() { echo "[FAIL] $*"; exit 1; }
ok()   { echo "[OK] $*"; exit 0; }

valid_name() { [[ "${1:-}" =~ ^[A-Za-z0-9_]{1,16}$ ]]; }

console() {  # envía a la consola si el módulo existe (best-effort)
  [[ -f "$CONSOLA" ]] || return 0
  bash "$CONSOLA" "$1" >/dev/null 2>&1 || true
}

chown_perms() {  # BDS corre como mcserver: devolver la propiedad tras escribir
  chown "${MC_USER:-mcserver}:${MC_GROUP:-mcserver}" "$PERMS" 2>/dev/null || true
}

# --- Mapa nombre <-> xuid -----------------------------------------------------
# Se arma con el journal (jugadores que entraron) + ops.json (registros viejos).
players_db() {
  {
    journalctl -u mc --no-pager -o cat --since '-180 days' 2>/dev/null \
      | grep -aoE 'Player connected: [A-Za-z0-9_]+, xuid: [0-9]+' \
      | sed -E 's/Player connected: ([A-Za-z0-9_]+), xuid: ([0-9]+)/\1\t\2/'
    python3 - "$OPS_JSON" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = []
for e in d:
    if e.get("name") and e.get("xuid"):
        print(f"{e['name']}\t{e['xuid']}")
PY
  } | awk -F'\t' 'NF>=2 && !seen[$1]++'
}

name_of_xuid() { players_db | awk -F'\t' -v x="$1" '$2==x{print $1; exit}'; }
xuid_of_name() { players_db | awk -F'\t' -v n="$1" '$1==n{print $2; exit}'; }

# --- permissions.json --------------------------------------------------------
perm_operators() {  # imprime un xuid por línea (solo operadores)
  python3 - "$PERMS" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = []
if not isinstance(d, list):
    d = []
for e in d:
    if e.get("permission") == "operator" and e.get("xuid"):
        print(e["xuid"])
PY
}

perm_set_operator() {  # $1 = xuid
  python3 - "$PERMS" "$1" <<'PY'
import json, os, sys
p, x = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(p))
except Exception:
    d = []
if not isinstance(d, list):
    d = []
d = [e for e in d if e.get("xuid") != x]
d.append({"permission": "operator", "xuid": x})
t = p + ".tmp"
json.dump(d, open(t, "w"), indent=2)
os.replace(t, p)
PY
}

perm_del_operator() {  # $1 = xuid
  python3 - "$PERMS" "$1" <<'PY'
import json, os, sys
p, x = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(p))
except Exception:
    d = []
if not isinstance(d, list):
    d = []
d = [e for e in d if not (e.get("xuid") == x and e.get("permission") == "operator")]
t = p + ".tmp"
json.dump(d, open(t, "w"), indent=2)
os.replace(t, p)
PY
}

ACT="${1:-}"; shift || true
case "$ACT" in
  list)
    for x in $(perm_operators); do
      n=$(name_of_xuid "$x")
      [[ -z "$n" ]] && n="(xuid $x)"
      printf '%s\t%s\t%s\n' "$n" "$OP_LEVEL" "$x"
    done
    ;;

  op)
    name="${1:-}"; xuid="${2:-}"
    valid_name "$name" || fail "nombre inválido"
    [[ -z "$xuid" || "$xuid" =~ ^[0-9]+$ ]] || fail "xuid inválido"
    [[ -z "$xuid" ]] && xuid=$(xuid_of_name "$name")
    console "op $name"                      # aplica en vivo (BDS escribe permissions.json)
    if [[ -n "$xuid" ]]; then               # respaldo por si no está online
      perm_set_operator "$xuid" && chown_perms
    fi
    ok "OP concedido a $name (nivel $OP_LEVEL${xuid:+, xuid $xuid})"
    ;;

  deop)
    name="${1:-}"
    valid_name "$name" || fail "nombre inválido"
    xuid=$(xuid_of_name "$name")
    console "deop $name"                    # efecto inmediato
    console "gamemode survival $name"       # por si estaba en creativo
    if [[ -n "$xuid" ]]; then
      perm_del_operator "$xuid" && chown_perms
    fi
    ok "OP revocado a $name (y puesto en supervivencia)"
    ;;

  survival)
    name="${1:-}"
    valid_name "$name" || fail "nombre inválido"
    console "gamemode survival $name"
    ok "Gamemode survival enviado a $name"
    ;;

  deop-all-except)
    name="${1:-}"
    valid_name "$name" || fail "nombre inválido"
    keep=$(xuid_of_name "$name")
    [[ -n "$keep" ]] || fail "no conozco el xuid de $name (¿entró alguna vez?)"
    n=0
    for x in $(perm_operators); do
      [[ "$x" == "$keep" ]] && continue
      nm=$(name_of_xuid "$x")
      [[ -n "$n" ]] && console "deop $n"
      perm_del_operator "$x" && n=$((n+1))
    done
    chown_perms
    ok "OP revocado a $n administrador(es); se conserva $name"
    ;;

  *) fail "uso: list|op|deop|survival|deop-all-except" ;;
esac
