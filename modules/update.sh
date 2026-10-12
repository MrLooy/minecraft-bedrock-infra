#!/usr/bin/env bash
# =============================================================================
# update.sh — D-11 / D-20
# Módulo INDEPENDIENTE: prepara/aplica actualizaciones de BDS.
#   Uso:
#     update.sh --stage              # descarga versión nueva y hace smoke test
#                                     # en staging (mundo fresco + mismos packs)
#     update.sh --stage --with-world # igual, pero copia el mundo real (lento)
#     update.sh --prod --yes         # GATE: aplicar en producción (--yes = el admin
#                                     # o el botón del panel)
# Solo depende de config/mc.conf.
# =============================================================================
set -euo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

log()  { echo "[$(date '+%F %T')] $*"; }
die()  { log "ERROR: $*" >&2; exit 1; }

webhook() {
  [[ -n "$MC_UPDATE_WEBHOOK" ]] || return 0
  curl -fsS --max-time 15 -H "Content-Type: application/json" \
       -d "{\"content\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")}" \
       "$MC_UPDATE_WEBHOOK" >/dev/null || log "WARN: webhook falló"
}

latest_version() {
  local html ver
  html=$(curl -fsSL --max-time 30 -A "mc-update/1.0" "$MC_BDS_PAGE" 2>/dev/null || true)
  ver=$(grep -oE 'bedrockdedicatedserver/bin-linux/bedrock-server-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.zip' <<<"$html" \
        | sed 's/.*bedrock-server-//; s/\.zip//' | sort -uV | tail -n1 || true)
  if [[ -z "$ver" ]]; then
    html=$(curl -fsSL --max-time 30 -A "mc-update/1.0" \
           "https://minecraft.wiki/w/Bedrock_Dedicated_Server" 2>/dev/null || true)
    ver=$(grep -oE 'bedrockdedicatedserver/bin-linux/bedrock-server-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.zip' <<<"$html" \
          | sed 's/.*bedrock-server-//; s/\.zip//' | sort -uV | tail -n1 || true)
  fi
  echo "$ver"
}

installed_version() {
  if [[ -f "$MC_VERSION_FILE" ]]; then cat "$MC_VERSION_FILE"; else echo ""; fi
}

# ---------------------------------------------------------------- STAGING ----
do_stage() {
  local with_world="${1:-}" latest zip url staging_bin
  latest=$(latest_version)
  [[ -n "$latest" ]] || die "no pude determinar la última versión"
  local installed; installed=$(installed_version)
  if [[ "$latest" == "$installed" ]]; then
    log "Ya estás en la última ($installed). Nada que hacer."
    exit 0
  fi

  staging_bin="$MC_STAGING_DIR/bin"
  # staging lo posee el usuario del panel (mcpanel): limpiar solo su contenido
  mkdir -p "$MC_STAGING_DIR"
  rm -rf "$MC_STAGING_DIR"/* 2>/dev/null || true
  mkdir -p "$staging_bin" "$MC_STAGING_DIR/logs"
  zip="$MC_STAGING_DIR/bedrock-server-$latest.zip"
  url="$MC_BDS_URL_BASE/bedrock-server-$latest.zip"

  log "Descargando $url"
  curl -fL --max-time 300 -o "$zip" "$url" || die "descarga fallida"
  unzip -qo "$zip" -d "$staging_bin" || die "unzip fallido"
  rm -f "$zip"

  # server.properties de staging: copia del real con otro puerto
  cp -f "$MC_SERVER_PROPS" "$staging_bin/server.properties"
  sed -i -E "s/^server-port=.*/server-port=$MC_STAGING_PORT/" "$staging_bin/server.properties"
  sed -i -E "s/^server-portv6=.*/server-portv6=$((MC_STAGING_PORT+1))/" "$staging_bin/server.properties"
  sed -i -E "s/^server-udp-ports=.*/server-udp-ports=$MC_STAGING_PORT-$((MC_STAGING_PORT+99))/" "$staging_bin/server.properties"
  sed -i -E "s/^transport=.*/transport=nethernet/" "$staging_bin/server.properties"
  # online-mode NO se toca: con allowlist, online-mode=false aborta el arranque (BDS lo rechaza)

  # Mismos packs que producción (aquí se validan)
  if [[ -d "$MC_PACKS_BP" ]]; then cp -a "$MC_PACKS_BP" "$staging_bin/behavior_packs"; fi
  if [[ -d "$MC_PACKS_RP" ]]; then cp -a "$MC_PACKS_RP" "$staging_bin/resource_packs"; fi
  mkdir -p "$staging_bin/worlds/$MC_LEVEL_NAME"
  if [[ -f "$MC_WORLD/world_behavior_packs.json" ]]; then
    cp -f "$MC_WORLD/world_behavior_packs.json" "$staging_bin/worlds/$MC_LEVEL_NAME/"
  fi
  if [[ -f "$MC_WORLD/world_resource_packs.json" ]]; then
    cp -f "$MC_WORLD/world_resource_packs.json" "$staging_bin/worlds/$MC_LEVEL_NAME/"
  fi
  if [[ -f "$MC_ALLOWLIST" ]]; then cp -f "$MC_ALLOWLIST" "$staging_bin/"; fi

  if [[ "$with_world" == "--with-world" ]]; then
    log "Copiando mundo real (puede tardar)..."
    mkdir -p "$staging_bin/worlds"
    cp -a --reflink=auto "$MC_WORLD_DIR/." "$staging_bin/worlds/"
  else
    mkdir -p "$staging_bin/worlds"
    echo "staging" > "$staging_bin/worlds/.placeholder"
  fi

  log "Arrancando BDS $latest en staging (puerto $MC_STAGING_PORT)..."
  (
    cd "$staging_bin"
    LD_LIBRARY_PATH="$staging_bin" setsid ./bedrock_server \
      > "$MC_STAGING_DIR/logs/server.log" 2>&1 &
    echo $! > "$MC_STAGING_DIR/pid"
  )
  sleep 25

  local ok=1 detalle=""
  local pid; pid=$(cat "$MC_STAGING_DIR/pid" 2>/dev/null || echo "")
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    ok=0; detalle="proceso murió"
  elif ! grep -qi "Server started" "$MC_STAGING_DIR/logs/server.log"; then
    ok=0; detalle="no aparece 'Server started'"
  elif grep -qiE "\[ERROR\]|Script.*failed|Failed to load" "$MC_STAGING_DIR/logs/server.log"; then
    ok=0; detalle="errores en log"
  elif ! ss -tln 2>/dev/null | grep -q ":$MC_STAGING_PORT"; then
    ok=0; detalle="puerto $MC_STAGING_PORT (TCP handshake) no escucha"
  fi

  [[ -n "$pid" ]] && pkill -P "$pid" 2>/dev/null || true
  [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  sleep 3

  if [[ $ok -eq 1 ]]; then
    echo "$latest" > "$MC_STAGING_DIR/ready_version"
    log "STAGING OK — BDS $latest lista para producción."
    webhook "✅ Staging **verde**: BDS $latest supera el smoke test. Gate del admin pendiente (`update.sh --prod --yes`)."
  else
    log "STAGING ROJO: $detalle"
    webhook "❌ Staging **rojo** (BDS $latest): $detalle. No aplicar."
    exit 1
  fi
}

# ------------------------------------------------------------- PRODUCCIÓN ----
do_prod() {
  [[ "${1:-}" == "--yes" ]] || die "falta el gate: --yes (solo el admin o el panel autenticado)"
  local ready="$MC_STAGING_DIR/ready_version"
  [[ -f "$ready" ]] || die "no hay staging listo (ejecuta update.sh --stage primero)"
  local new; new=$(cat "$ready")
  local installed; installed=$(installed_version)
  [[ "$new" != "$installed" ]] || { log "Ya estás en $installed."; exit 0; }

  local ts; ts=$(date +%Y%m%d-%H%M%S)
  log "Aplicando BDS $new (instalada: $installed)"

  # 1) Snapshot previo (mundo + configs) — obligatorio: la migración es irreversible
  mkdir -p "$MC_BACKUP_DIR"
  local snap="$MC_BACKUP_DIR/preupdate-$ts.tar.gz"
  tar czf "$snap" -C "$MC_HOME" \
      worlds server.properties allowlist.json permissions.json 2>/dev/null \
    || log "WARN: alguno de los archivos no existía aún"
  log "Snapshot previo: $snap"

  # 2) Parar servidor
  systemctl stop "$MC_SERVICE"

  # 3) Reemplazar binario y libs (NO tocamos configs ni mundo)
  local staging_bin="$MC_STAGING_DIR/bin"
  mkdir -p "$MC_HOME/bin.prev"
  mv -f "$MC_HOME/bedrock_server" "$MC_HOME/bin.prev/" 2>/dev/null || true
  cp -f "$staging_bin/bedrock_server" "$MC_HOME/"
  find "$staging_bin" -maxdepth 1 -name '*.so*' -exec cp -f {} "$MC_HOME/" \;
  chmod +x "$MC_HOME/bedrock_server"

  echo "$new" > "$MC_VERSION_FILE"

  # 4) Arrancar y comprobar
  systemctl start "$MC_SERVICE"
  local i ok=0
  for i in $(seq 1 24); do
    sleep 5
    if journalctl -u "$MC_SERVICE" --since "-2 min" -q 2>/dev/null | grep -qi "Server started"; then
      ok=1; break
    fi
  done

  if [[ $ok -eq 1 ]]; then
    log "PRODUCCIÓN OK — BDS $new corriendo."
    webhook "🚀 Producción actualizada a **BDS $new**. ⚠️ Revalidar bloques y avisar a los jugadores de actualizar la app."
  else
    log "PRODUCCIÓN FALLÓ — rollback del binario"
    cp -f "$MC_HOME/bin.prev/bedrock_server" "$MC_HOME/"
    systemctl start "$MC_SERVICE" || true
    webhook "🚨 Fallo al aplicar BDS $new. Binario restaurado al anterior ($installed). Mundo intacto: restaurar snapshot $snap si el arranque falla."
    exit 1
  fi
}

case "${1:-}" in
  --stage) do_stage "${2:-}" ;;
  --prod)   do_prod "${2:-}" ;;
  *) die "uso: update.sh --stage [--with-world] | update.sh --prod --yes" ;;
esac
