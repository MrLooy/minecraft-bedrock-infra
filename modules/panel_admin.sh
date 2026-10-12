#!/usr/bin/env bash
# =============================================================================
# panel_admin.sh — D-43
# Módulo INDEPENDIENTE que expone al panel (vía sudo acotado) las mismas
# operaciones que un panel tipo Aternos: allowlist, opciones del server
# (server.properties), copias de seguridad y listado de mundos.
#   Uso:
#     panel_admin.sh allowlist list
#     panel_admin.sh allowlist add  <name>
#     panel_admin.sh allowlist remove <name>
#     panel_admin.sh props get
#     panel_admin.sh props set <KEY> <VALUE>
#     panel_admin.sh backup list
#     panel_admin.sh backup create
#     panel_admin.sh worlds
# Salida: líneas "[OK] ..." o "[FAIL] ..." para que el panel las parsee.
# Corre como root (sudoers lo acota a este script); edita archivos de mcserver
# y devuelve la propiedad a mcserver/mcserver tras escribir.
# =============================================================================
set -uo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

PROPS="${MC_SERVER_PROPERTIES:-${MC_HOME:-/opt/mcserver}/server.properties}"
ALLOW="${MC_ALLOWLIST:-${MC_HOME:-/opt/mcserver}/allowlist.json}"
OWNER="${MC_USER:-mcserver}:${MC_GROUP:-mcserver}"

ok()   { echo "[OK] $*";  exit 0; }
fail() { echo "[FAIL] $*"; exit 1; }

valid_name() { [[ "${1:-}" =~ ^[A-Za-z0-9_]{1,16}$ ]]; }

chown_back() { chown "$OWNER" "$1" 2>/dev/null || true; }

# Claves de server.properties que el panel puede tocar (subconjunto SEGURO).
PROP_KEYS=(motd server-name gamemode difficulty force-gamemode max-players
           view-distance tick-distance player-idle-timeout allow-list
           default-player-permission-level allow-cheats texturepack-required)
prop_key_ok() { local k; for k in "${PROP_KEYS[@]}"; do [[ "$k" == "$1" ]] && return 0; done; return 1; }

# ------------------------------------------------------------------ allowlist -
allow_list() {
  python3 - "$ALLOW" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    data = []
for e in data:
    print(f"{e.get('name','?')}\t{e.get('xuid','')}")
PY
}

allow_write() {  # $1=add|remove  $2=name
  python3 - "$ALLOW" "$1" "$2" <<'PY'
import json, os, sys
path, action, name = sys.argv[1:4]
try:
    data = json.load(open(path))
except Exception:
    data = []
data = [e for e in data if e.get("name") != name]
if action == "add":
    data.append({"ignoresPlayerLimit": False, "name": name})
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)
PY
}

# -------------------------------------------------------------------- props ---
props_get() { cat "$PROPS"; }

props_set() {  # $1=KEY  $2=VALUE  (python hace el reemplazo/append)
  python3 - "$PROPS" "$1" "$2" <<'PY'
import os, sys
path, key, val = sys.argv[1:4]
lines = open(path).read().splitlines(keepends=True)
found = False
for i, l in enumerate(lines):
    if l.split("=", 1)[0] == key and not l.lstrip().startswith("#"):
        lines[i] = f"{key}={val}\n"; found = True; break
if not found:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.append(f"{key}={val}\n")
tmp = path + ".tmp"
with open(tmp, "w") as f:
    f.writelines(lines)
os.replace(tmp, path)
PY
}

# ------------------------------------------------------------------ backups ---
backup_list() {
  local f
  for f in "$MC_BACKUP_DIR"/mcserver-*.tar.gz; do
    [[ -e "$f" ]] || continue
    printf '%s\t%s\t%s\n' "$(basename "$f")" "$(stat -c %s "$f")" \
      "$(stat -c %y "$f" | cut -d. -f1)"
  done | sort -k3
}

backup_create() {
  local out
  if out="$(bash "$MC_HOME/modules/backup.sh" 2>&1)"; then
    ok "copia creada: $(echo "$out" | tail -1)"
  else
    echo "$out"; fail "backup falló"
  fi
}

# ------------------------------------------------------------------- worlds ---
worlds() {
  local d
  for d in "$MC_WORLD_DIR"/*/; do
    [[ -d "$d" ]] || continue
    printf '%s\t%s\n' "$(basename "$d")" "$(du -sm "$d" 2>/dev/null | cut -f1)"
  done
}

# ---------------------------------------------------------------------- main -
ACT="${1:-}"; shift || true
case "$ACT" in
  allowlist)
    case "${1:-}" in
      list)   allow_list ;;
      add)    valid_name "${2:-}" || fail "gamertag inválido"
              allow_write add "${2:-}"; chown_back "$ALLOW"
              ok "allowlist += ${2}" ;;
      remove) valid_name "${2:-}" || fail "gamertag inválido"
              allow_write remove "${2:-}"; chown_back "$ALLOW"
              ok "allowlist -= ${2}" ;;
      *) fail "uso: allowlist <list|add|remove>" ;;
    esac ;;

  props)
    case "${1:-}" in
      get) props_get ;;
      set)
        KEY="${2:-}"; VAL="${3:-}"
        prop_key_ok "$KEY" || fail "clave no editable: $KEY"
        [[ -z "$VAL" ]] && fail "valor vacío"
        [[ "$VAL" == *$'\n'* ]] && fail "valor inválido"
        props_set "$KEY" "$VAL"; chown_back "$PROPS"
        ok "$KEY=$VAL (requiere reinicio del server)" ;;
      *) fail "uso: props <get|set KEY VALUE>" ;;
    esac ;;

  backup)
    case "${1:-}" in
      list)   backup_list ;;
      create) backup_create ;;
      *) fail "uso: backup <list|create>" ;;
    esac ;;

  worlds) worlds ;;

  *) echo "uso: panel_admin.sh <allowlist|props|backup|worlds> ..." >&2; exit 2 ;;
esac
