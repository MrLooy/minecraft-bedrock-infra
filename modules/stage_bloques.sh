#!/usr/bin/env bash
# =============================================================================
# stage_bloques.sh — D-11 / D-08 (regla 2 de bloques/BLOCKS.md)
# Módulo INDEPENDIENTE: prueba en STAGING los bloques descargados en
# $MC_BLOCKS_DIR/<nombre>/ antes de tocar producción (gate del admin).
#   Uso:
#     stage_bloques.sh start    # construye staging (prod + bloques) y arranca
#     stage_bloques.sh status   # Pack Stack, errores y veredicto
#     stage_bloques.sh stop     # parar staging
# No toca producción: todo vive en $MC_STAGING_DIR y usa $MC_STAGING_PORT.
# =============================================================================
set -euo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

log() { echo "[$(date '+%F %T')] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

STAGING_BIN="$MC_STAGING_DIR/bin"
STAGED="$MC_STAGING_DIR/staged"
LOG="$MC_STAGING_DIR/logs/server.log"
PIDF="$MC_STAGING_DIR/pid"

# campo: name | uuid | version | tipo (bp|rp)
manifest_json() {
  python3 - "$1/manifest.json" "$2" <<'PY'
import json, sys
try:
    txt = open(sys.argv[1], encoding="utf-8", errors="replace").read().lstrip("\ufeff \t\r\n")
    d, _ = json.JSONDecoder().raw_decode(txt)   # tolera comentarios/trailing
    campo = sys.argv[2]
    if campo == "name":
        print(d.get("header", {}).get("name", ""))
    elif campo == "uuid":
        print(d.get("header", {}).get("uuid") or (d.get("modules") or [{}])[0].get("uuid", ""))
    elif campo == "version":
        v = d.get("header", {}).get("version", [1, 0, 0])
        # algunos packs declaran "version" / "min_engine_version" como STRING
        # ("2.9.1") en vez de array [2,9,1]: normalizamos.
        if isinstance(v, str):
            v = [int(x) for x in v.split(".") if x.isdigit()] or [1, 0, 0]
        print(".".join(str(x) for x in v))
    else:
        t = (d.get("modules") or [{}])[0].get("type", "")
        print("bp" if t == "data" else ("rp" if t == "resources" else ""))
except Exception:
    print("")
PY
}

json_upsert() {  # $1=archivo $2=pack_id $3=versión(a.b.c)
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys, os
f, pid, ver = sys.argv[1], sys.argv[2], [int(x) for x in sys.argv[3].split(".")]
data = json.load(open(f, encoding="utf-8")) if os.path.exists(f) and os.path.getsize(f) else []
if not isinstance(data, list): data = data.get("policies", [])
for e in data:
    if e.get("pack_id") == pid:
        e["version"] = ver; break
else:
    data.append({"pack_id": pid, "version": ver})
json.dump(data, open(f, "w", encoding="utf-8"), indent=2)
PY
}

# Copia a $STAGED/<bloque>/{bp,rp}/<pack>/ todo lo de blocks.d:
# carpetas ya extraídas (bp/, rp/) + .mcaddon/.mcpack/.zip (se extraen aquí,
# incluidos los .mcpack anidados dentro de un .mcaddon).
prepara_staged() {
  python3 - "$MC_BLOCKS_DIR" "$STAGED" <<'PY'
import glob, json, os, shutil, sys, tempfile, zipfile
blocks, staged = sys.argv[1], sys.argv[2]
n = 0

def loadj(p):
    txt = open(p, encoding="utf-8", errors="replace").read().lstrip("\ufeff \t\r\n")
    return json.JSONDecoder().raw_decode(txt)[0]   # tolera comentarios/trailing

def extraer_zip(arch, td, prof=0):
    if prof > 3:
        return
    try:
        with zipfile.ZipFile(arch) as z:
            z.extractall(td)
    except Exception as e:
        print(f"WARN: no pude extraer {arch}: {e}")
        return
    # Si el archivo ya ES un pack (manifest.json en la raíz), lo de aquí adentro
    # son datos del pack (p. ej. items.zip de bridge): no se recursa.
    if os.path.isfile(os.path.join(td, "manifest.json")):
        return
    for ext in ("*.mcaddon", "*.mcpack", "*.zip"):
        for inner in sorted(glob.glob(os.path.join(td, "**", ext), recursive=True)):
            if not os.path.isfile(inner):
                continue
            nb = os.path.basename(inner)
            while os.path.splitext(nb)[1] in (".mcaddon", ".mcpack", ".zip"):
                nb = os.path.splitext(nb)[0]
            dest = os.path.join(os.path.dirname(inner), nb)
            if os.path.abspath(dest) == os.path.abspath(inner):
                continue
            os.makedirs(dest, exist_ok=True)
            extraer_zip(inner, dest, prof + 1)

def normaliza_manifest(p):
    # BDS exige arrays [a,b,c] en "version"/"min_engine_version". Algunos packs
    # las declaran como string ("2.9.1"): las normalizamos al stagear.
    try:
        d = loadj(p)
    except Exception:
        return
    cambios = 0
    def fix(o):
        nonlocal cambios
        if isinstance(o, dict):
            for k, v in o.items():
                if k in ("version", "min_engine_version") and isinstance(v, str):
                    arr = [int(x) for x in v.split(".") if x.isdigit()] or [1, 0, 0]
                    o[k] = arr
                    cambios += 1
                else:
                    fix(v)
        elif isinstance(o, list):
            for v in o:
                fix(v)
    fix(d)
    if cambios:
        print(f"  normalizado version string en {p} ({cambios})")
        json.dump(d, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)

def volcar(td, nombre, nb_fallback):
    global n
    for root, dirs, files in os.walk(td):
        if "manifest.json" not in files:
            continue
        try:
            d = loadj(os.path.join(root, "manifest.json"))
        except Exception as e:
            print(f"WARN: manifest ilegible en {root}: {e}")
            continue
        t = (d.get("modules") or [{}])[0].get("type", "")
        sub = "rp" if t == "resources" else "bp"
        nb = nb_fallback if os.path.abspath(root) == os.path.abspath(td) else os.path.basename(root)
        dest = os.path.join(staged, nombre, sub, nb)
        if os.path.abspath(dest) == os.path.abspath(root):
            continue
        shutil.copytree(root, dest, dirs_exist_ok=True)
        normaliza_manifest(os.path.join(dest, "manifest.json"))
        n += 1

shutil.rmtree(staged, ignore_errors=True)
for bloque in sorted(glob.glob(os.path.join(blocks, "*"))):
    if not os.path.isdir(bloque):
        continue
    nombre = os.path.basename(bloque)
    for sub in ("bp", "rp"):
        for p in sorted(glob.glob(os.path.join(bloque, sub, "*"))):
            if os.path.isfile(os.path.join(p, "manifest.json")):
                volcar(p, nombre, os.path.basename(p))
    archivos = []
    for ext in ("*.mcaddon", "*.mcpack", "*.zip"):
        archivos += glob.glob(os.path.join(bloque, ext))
    for arch in sorted(archivos):
        base = os.path.basename(arch)
        while os.path.splitext(base)[1] in (".mcaddon", ".mcpack", ".zip"):
            base = os.path.splitext(base)[0]
        with tempfile.TemporaryDirectory() as td:
            extraer_zip(arch, td)
            volcar(td, nombre, base)
print(f"bloques staged: {n}")
PY
}

staged_packs() {  # imprime "tipo<TAB>dir" por cada pack staged
  local d
  for d in "$STAGED"/*/*/*/; do
    [[ -f "$d/manifest.json" ]] || continue
    case "$d" in
      */bp/*) printf 'bp\t%s\n' "${d%/}" ;;
      *)      printf 'rp\t%s\n' "${d%/}" ;;
    esac
  done
}

ver_verdict() {  # 0 = verde
  local ok=1 pid tipo dir nombre basename_dir
  pid=$(cat "$PIDF" 2>/dev/null || true)
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    log "ROJO: el proceso de staging murió"; ok=0
  fi
  if [[ ! -f "$LOG" ]] || ! grep -qi "Server started" "$LOG"; then
    log "ROJO: no aparece 'Server started' en el log"; ok=0
  fi
  # Errores benignos conocidos (warns no-fatales de addons, documentados en
  # DECISIONES.md): FeatureRegistry de ExtraBiomes referenciando features
  # vanilla que BDS ya no registra (biomas y servidor funcionan igual).
  local benignos=(
    "\[FeatureRegistry\] world | No definition found for feature"
  )
  local filtro=""
  local b
  for b in "${benignos[@]}"; do
    filtro="${filtro}${filtro:+|}$b"
  done
  local errs
  errs=$(grep -iE " ERROR\]|\[ERROR\]|Script.*failed|Failed to load" "$LOG" 2>/dev/null \
         | grep -viE "$filtro" || true)
  if [[ -n "$errs" ]]; then
    log "ROJO: errores en el log:"
    echo "$errs" | tail -n 15
    ok=0
  fi
  if ! ss -tln 2>/dev/null | grep -q ":$MC_STAGING_PORT"; then
    log "ROJO: puerto $MC_STAGING_PORT (TCP) no escucha"; ok=0
  fi
  while IFS=$'\t' read -r tipo dir; do
    [[ -n "${dir:-}" ]] || continue
    # El Pack Stack solo lista behavior packs; los RP se validan sin errores de carga
    [[ "$tipo" == "bp" ]] || continue
    nombre=$(manifest_json "$dir" name)
    basename_dir=$(basename "$dir")
    if ! grep -qF -e "$nombre" -e "$basename_dir" "$LOG" 2>/dev/null; then
      log "ROJO: el bloque '$nombre' no aparece en el log (Pack Stack)"; ok=0
    fi
  done < <(staged_packs)
  [[ $ok -eq 1 ]]
}

do_stop() {
  local pid
  pid=$(cat "$PIDF" 2>/dev/null || true)
  if [[ -n "$pid" ]]; then
    pkill -P "$pid" 2>/dev/null || true
    kill -- "-$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    sleep 2
  fi
  rm -f "$PIDF"
  log "staging parado"
}

do_start() {
  if [[ -f "$PIDF" ]]; then do_stop; fi
  # El mundo de staging SE CONSERVA entre arranques (level.dat guarda experimentos,
  # y re-generarlo obligaría a reinyectarlos). El resto del binario se reconstruye.
  local worlds_keep="$MC_STAGING_DIR/.worlds_keep"
  rm -rf "$worlds_keep"
  if [[ -d "$STAGING_BIN/worlds" ]]; then
    mv "$STAGING_BIN/worlds" "$worlds_keep"
  fi
  rm -rf "$STAGING_BIN"
  mkdir -p "$STAGING_BIN" "$MC_STAGING_DIR/logs"
  if [[ -d "$worlds_keep" ]]; then
    mv "$worlds_keep" "$STAGING_BIN/worlds"
  fi

  # Mismo BDS que producción (sin descargar nada)
  cp -f "$MC_HOME/bedrock_server" "$STAGING_BIN/"
  find "$MC_HOME" -maxdepth 1 -name '*.so*' -exec cp -f {} "$STAGING_BIN/" \;
  chmod +x "$STAGING_BIN/bedrock_server"
  cp -a "$MC_HOME/data" "$STAGING_BIN/" 2>/dev/null || true   # bootstrap.json del profiler
  cp -a "$MC_HOME/config" "$STAGING_BIN/" 2>/dev/null || true  # default/permissions.json (allowed_modules)
  cp -f "$MC_ALLOWLIST" "$STAGING_BIN/" 2>/dev/null || true
  cp -f "$MC_HOME/permissions.json" "$STAGING_BIN/" 2>/dev/null || true

  # server.properties de staging: copia del real con otro puerto.
  # online-mode NO se toca: con allowlist, online-mode=false aborta el arranque.
  cp -f "$MC_SERVER_PROPS" "$STAGING_BIN/server.properties"
  sed -i -E "s/^server-port=.*/server-port=$MC_STAGING_PORT/" "$STAGING_BIN/server.properties"
  sed -i -E "s/^server-portv6=.*/server-portv6=$((MC_STAGING_PORT+1))/" "$STAGING_BIN/server.properties"
  sed -i -E "s/^server-udp-ports=.*/server-udp-ports=$MC_STAGING_PORT-$((MC_STAGING_PORT+99))/" "$STAGING_BIN/server.properties"
  sed -i -E "s/^transport=.*/transport=nethernet/" "$STAGING_BIN/server.properties"

  # Mismos packs que producción
  if [[ -d "$MC_PACKS_BP" ]]; then cp -a "$MC_PACKS_BP" "$STAGING_BIN/behavior_packs"; fi
  if [[ -d "$MC_PACKS_RP" ]]; then cp -a "$MC_PACKS_RP" "$STAGING_BIN/resource_packs"; fi

  # Mundo conservado + JSONS de producción (los bloques staged se añaden encima)
  mkdir -p "$STAGING_BIN/worlds/$MC_LEVEL_NAME"
  local j
  for j in world_behavior_packs.json world_resource_packs.json; do
    if [[ -f "$MC_WORLD/$j" ]]; then
      cp -f "$MC_WORLD/$j" "$STAGING_BIN/worlds/$MC_LEVEL_NAME/"
    fi
  done

  # Bloques de blocks.d → staged → copiados y encendidos SOLO en staging
  local prep n=0 tipo dir uuid ver nombre packdest json
  prep=$(prepara_staged)
  log "$prep"
  while IFS=$'\t' read -r tipo dir; do
    [[ -n "${dir:-}" ]] || continue
    uuid=$(manifest_json "$dir" uuid)
    ver=$(manifest_json "$dir" version)
    nombre=$(manifest_json "$dir" name)
    if [[ -z "$uuid" || -z "$ver" ]]; then log "WARN: manifest ilegible: $dir"; continue; fi
    if [[ "$tipo" == "bp" ]]; then
      packdest="$STAGING_BIN/behavior_packs/$(basename "$dir")"
      json="$STAGING_BIN/worlds/$MC_LEVEL_NAME/world_behavior_packs.json"
    else
      packdest="$STAGING_BIN/resource_packs/$(basename "$dir")"
      json="$STAGING_BIN/worlds/$MC_LEVEL_NAME/world_resource_packs.json"
    fi
    rm -rf "$packdest"
    cp -a "$dir" "$packdest"
    json_upsert "$json" "$uuid" "$ver"
    log "staged: $nombre [$tipo] uuid=$uuid v=$ver"
    n=$((n+1))
  done < <(staged_packs)
  if [[ $n -eq 0 ]]; then log "AVISO: sin bloques en $MC_BLOCKS_DIR/*/{bp,rp} ni .mcaddon/.mcpack"; fi

  log "Arrancando BDS $(cat "$MC_VERSION_FILE" 2>/dev/null || echo '?') en staging (puerto $MC_STAGING_PORT)..."
  (
    cd "$STAGING_BIN"
    LD_LIBRARY_PATH="$STAGING_BIN" setsid ./bedrock_server > "$LOG" 2>&1 &
    echo $! > "$PIDF"
  )
  sleep 25

  if ver_verdict; then
    log "STAGING VERDE — $n bloque(s) staged cargados. Gate del admin pendiente antes de producción."
    log "Cliente: IP del VPS, puerto $MC_STAGING_PORT"
    do_status_packs
  else
    log "STAGING ROJO — ver 'stage_bloques.sh status'"
    exit 1
  fi
}

do_status_packs() {
  local tipo dir nombre
  echo "== bloques staged =="
  while IFS=$'\t' read -r tipo dir; do
    [[ -n "${dir:-}" ]] || continue
    nombre=$(manifest_json "$dir" name)
    echo "  [$tipo] $nombre  ($(basename "$dir"))"
  done < <(staged_packs)
}

do_status() {
  echo "== Pack Stack / errores en $LOG =="
  if [[ -f "$LOG" ]]; then
    grep -E "Pack Stack|Server started| ERROR\]|\[ERROR\]|Script.*failed|Failed to load" "$LOG" | tail -n 60 || true
  else
    echo "  (sin log: staging nunca arrancó)"
  fi
  local benignos nben
  benignos=$(grep -icE "\[FeatureRegistry\] world \| No definition found for feature" "$LOG" 2>/dev/null || true)
  if [[ "$benignos" -gt 0 ]]; then
    echo "  -> $benignos warning(s) FeatureRegistry benignos (ver DECISIONES.md)"
  fi
  do_status_packs
  if ver_verdict; then
    echo "VEREDICTO: VERDE"
  else
    echo "VEREDICTO: ROJO"
    return 1
  fi
}

case "${1:-}" in
  start)  do_start ;;
  stop)   do_stop ;;
  status) do_status ;;
  *)      die "uso: stage_bloques.sh start|stop|status" ;;
esac
