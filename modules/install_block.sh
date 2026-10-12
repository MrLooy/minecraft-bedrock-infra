#!/usr/bin/env bash
# =============================================================================
# install_block.sh — D-08 / D-20
# Módulo INDEPENDIENTE: gestor de BLOQUES (add-ons) = el interruptor del sistema.
#   Uso:
#     install_block.sh add <carpeta_o_mcaddon> bp|rp   # PONER bloque
#     install_block.sh disable <pack_id>               # QUITAR (borra la línea)
#     install_block.sh enable  <pack_id>               # volver a poner
#     install_block.sh list                            # ver estado
#     install_block.sh remove  <pack_id>               # quitar + borrar carpeta
# El "interruptor" es world_behavior_packs.json / world_resource_packs.json.
# =============================================================================
set -euo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

log() { echo "[$(date '+%F %T')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

tipo_of() {  # $1 = ruta del manifest.json → "bp" (data) | "rp" (resources) | vacío
  python3 - "$1" <<'PY'
import json, sys
try:
    txt = open(sys.argv[1], encoding="utf-8").read().lstrip("\ufeff \t\r\n")
    d, _ = json.JSONDecoder().raw_decode(txt)   # tolera comentarios/trailing
    t = (d.get("modules") or [{}])[0].get("type", "")
except Exception:
    t = ""
print("bp" if t == "data" else ("rp" if t == "resources" else ""))
PY
}

manifest_of() {  # $1 = carpeta del pack → "uuid version" (uuid del HEADER: el que busca BDS)
  python3 - "$1/manifest.json" <<'PY'
import json, sys
txt = open(sys.argv[1], encoding="utf-8").read().lstrip("\ufeff \t\r\n")
d, _ = json.JSONDecoder().raw_decode(txt)   # tolera comentarios/trailing
u = d.get("header", {}).get("uuid") or d.get("modules", [{}])[0].get("uuid")
v = ".".join(str(x) for x in d.get("header", {}).get("version", [1, 0, 0]))
print(u, v)
PY
}

json_file_for() { [[ "$1" == "bp" ]] && echo "$MC_WORLD/world_behavior_packs.json" || echo "$MC_WORLD/world_resource_packs.json"; }
packs_dir_for() { [[ "$1" == "bp" ]] && echo "$MC_PACKS_BP" || echo "$MC_PACKS_RP"; }

nombre_of() {  # $1 = ruta del manifest.json → nombre del pack (para nombrar la carpeta)
  python3 - "$1" <<'PY'
import json, sys, re
try:
    txt = open(sys.argv[1], encoding="utf-8").read().lstrip("\ufeff \t\r\n")
    d, _ = json.JSONDecoder().raw_decode(txt)
    n = d.get("header", {}).get("name", "").strip()
except Exception:
    n = ""
n = re.sub(r'[\\/:*?"<>|]+', "-", n)
print(n)
PY
}

json_add() {  # $1=archivo $2=pack_id $3=versión(a.b.c)
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys, os
f, pid, ver = sys.argv[1], sys.argv[2], [int(x) for x in sys.argv[3].split(".")]
data = json.load(open(f, encoding="utf-8")) if os.path.exists(f) and os.path.getsize(f) else []
if not isinstance(data, list): data = data.get("policies", [])
for e in data:
    if e.get("pack_id") == pid:
        e["version"] = ver; print("actualizado"); break
else:
    data.append({"pack_id": pid, "version": ver}); print("añadido")
json.dump(data, open(f, "w", encoding="utf-8"), indent=2)
PY
}

json_del() {  # $1=archivo $2=pack_id
  python3 - "$1" "$2" <<'PY'
import json, sys, os
f, pid = sys.argv[1], sys.argv[2]
if not os.path.exists(f): print("no existía"); raise SystemExit(0)
data = json.load(open(f, encoding="utf-8"))
new = [e for e in data if e.get("pack_id") != pid]
if len(new) == len(data): print("no estaba")
else: print("quitado")
json.dump(new, open(f, "w", encoding="utf-8"), indent=2)
PY
}

cmd_add() {
  local src="$1" tipo="$2" dir dest uuid ver
  [[ "$tipo" == "bp" || "$tipo" == "rp" ]] || die "tipo debe ser bp o rp"
  [[ -e "$src" ]] || die "no existe $src"

  # Si es .mcaddon/.mcpack, se descomprime en un temp y se procesa cada pack.
  # El tipo (bp/rp) se toma del manifest de CADA pack: un .mcaddon suele traer
  # BP y RP juntos y pasarlos todos como "bp" los instalaría al revés.
  # Algunos addons traen .mcpack ANIDADOS (p. ej. B8) → extraer 2 niveles.
  if [[ -f "$src" && "$src" =~ \.(mcaddon|mcpack|zip)$ ]]; then
    local tmp lvl a n=0 manifestos
    tmp=$(mktemp -d)
    unzip -qo "$src" -d "$tmp"
    # anidados (p. ej. B8: .mcaddon que solo contiene dos .mcpack).
    # Solo se recurre si AÚN no hay manifest: evita extraer items.zip de
    # bridge dentro de B9 (generaría un pack fantasma).
    for lvl in 1 2 3; do
      [[ -n "$(find "$tmp" -name manifest.json -print -quit)" ]] && break
      local hubo=0
      while IFS= read -r -d '' a; do
        hubo=1
        unzip -qo "$a" -d "$tmp/_x$n" >/dev/null 2>&1 || true
        rm -f "$a"
        n=$((n+1))
      done < <(find "$tmp" -type f \( -name '*.mcaddon' -o -name '*.mcpack' -o -name '*.zip' \) -print0)
      [[ $hubo -eq 0 ]] && break
    done
    manifestos=$(find "$tmp" -name manifest.json | wc -l)
    if [[ $manifestos -eq 0 ]]; then
      rm -rf "$tmp"
      die "$src: ningún manifest.json encontrado (¿archivo vacío o formato no soportado?)"
    fi
    while IFS= read -r -d '' m; do
      t=$(tipo_of "$m")
      cmd_add "$(dirname "$m")" "${t:-$tipo}"
    done < <(find "$tmp" -name manifest.json -print0)
    rm -rf "$tmp"
    return 0
  fi

  [[ -f "$src/manifest.json" ]] || die "$src no parece un pack (falta manifest.json)"
  local t nombre; t=$(tipo_of "$src/manifest.json")
  if [[ -n "$t" ]]; then tipo="$t"; fi
  read -r uuid ver <<<"$(manifest_of "$src")"
  nombre=$(nombre_of "$src/manifest.json")
  [[ -z "$nombre" ]] && nombre=$(basename "$src")
  dest="$(packs_dir_for "$tipo")/$nombre"
  mkdir -p "$(packs_dir_for "$tipo")"
  rm -rf "$dest"
  cp -a "$src" "$dest"
  # BDS corre como mcserver: el pack tiene que ser legible para él.
  # (mktemp da 700 y cp -a lo hereda → BDS lo IGNORARÍA en silencio.)
  chown -R mcserver:mcserver "$dest"
  chmod -R u=rwX,go=rX "$dest"
  json_add "$(json_file_for "$tipo")" "$uuid" "$ver" >/dev/null
  log "BLOQUE PUESTO: $nombre [$tipo] uuid=$uuid v=$ver"
  log "Para quitar: install_block.sh disable $uuid"
}

cmd_list() {
  for tipo in bp rp; do
    local f; f=$(json_file_for "$tipo")
    echo "== $tipo =="
    if [[ -f "$f" ]]; then
      python3 - "$f" "$(packs_dir_for "$tipo")" <<'PY'
import json, sys, os
f, d = sys.argv[1], sys.argv[2]
for e in json.load(open(f, encoding="utf-8")):
    pid = e.get("pack_id"); ver = ".".join(map(str, e.get("version", [])))
    carpeta = ""
    if os.path.isdir(d):
            for name in os.listdir(d):
                m = os.path.join(d, name, "manifest.json")
                if os.path.exists(m):
                    try:
                        txt = open(m, encoding="utf-8").read().lstrip("\ufeff \t\r\n")
                        j, _ = json.JSONDecoder().raw_decode(txt)  # tolera comentarios
                        if j.get("modules", [{}])[0].get("uuid") == pid or j.get("header", {}).get("uuid") == pid:
                            carpeta = name; break
                    except Exception: pass
    estado = "✅" if carpeta else "⚠️ línea sin carpeta"
    print(f"  {estado} {pid} v{ver} {'(' + carpeta + ')' if carpeta else ''}")
PY
    else
      echo "  (sin archivo)"
    fi
  done
}

case "${1:-}" in
  add)     [[ $# -ge 3 ]] || die "uso: add <ruta> bp|rp"; cmd_add "$2" "$3" ;;
  disable) [[ $# -ge 2 ]] || die "uso: disable <pack_id>"; json_del "$(json_file_for bp)" "$2" >/dev/null && json_del "$(json_file_for rp)" "$2" >/dev/null; log "bloque $2 APAGADO (reinicia para aplicar)" ;;
  enable)  [[ $# -ge 2 ]] || die "uso: enable <pack_id>"
           local_dir=""
           for d in "$MC_PACKS_BP"/* "$MC_PACKS_RP"/*; do
             [[ -f "$d/manifest.json" ]] || continue
             read -r u v <<<"$(manifest_of "$d")"
              if [[ "$u" == "$2" ]]; then
                if [[ -d "$d" && "$d" == "$MC_PACKS_BP"* ]]; then
                  json_add "$(json_file_for bp)" "$u" "$v" >/dev/null
                fi
                if [[ -d "$d" && "$d" == "$MC_PACKS_RP"* ]]; then
                  json_add "$(json_file_for rp)" "$u" "$v" >/dev/null
                fi
                log "bloque $2 ENCENDIDO (reinicia para aplicar)"; exit 0
              fi
           done
           die "no encontré el pack $2" ;;
  list)    cmd_list ;;
  remove)  [[ $# -ge 2 ]] || die "uso: remove <pack_id>"
           json_del "$(json_file_for bp)" "$2" >/dev/null || true
           json_del "$(json_file_for rp)" "$2" >/dev/null || true
           for d in "$MC_PACKS_BP"/* "$MC_PACKS_RP"/*; do
             [[ -f "$d/manifest.json" ]] || continue
              read -r u _ <<<"$(manifest_of "$d")"
              if [[ "$u" == "$2" ]]; then rm -rf "$d"; log "borrada $(basename "$d")"; fi
           done ;;
  *)       die "uso: add|r disable|enable|list|remove" ;;
esac
