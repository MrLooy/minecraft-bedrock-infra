#!/usr/bin/env bash
# =============================================================================
# check_version.sh — D-11 / D-20
# Módulo INDEPENDIENTE: detecta si Mojang publicó una versión nueva de BDS.
#   Uso:  check_version.sh            → solo alerta (webhook)
#         check_version.sh --stage    → alerta + prepara staging (invoca update.sh)
#         check_version.sh --print    → imprime última/instalada (sin webhook)
# No depende de ningún otro módulo salvo mc.conf (y de update.sh solo con --stage).
# =============================================================================
set -euo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

log() { echo "[$(date '+%F %T')] $*"; }

installed_version() {
  if [[ -f "$MC_VERSION_FILE" ]]; then cat "$MC_VERSION_FILE"; else echo "desconocida"; fi
}

# Descubre la última versión estable en la página oficial de descarga.
# Solo bin-linux/ (estable); excluye bin-linux-preview/ (BDS preview).
latest_version() {
  local html ver
  html=$(curl -fsSL --max-time 30 -A "mc-check/1.0" "$MC_BDS_PAGE" 2>/dev/null || true)
  ver=$(grep -oE 'bedrockdedicatedserver/bin-linux/bedrock-server-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.zip' <<<"$html" \
        | sed 's/.*bedrock-server-//; s/\.zip//' | sort -uV | tail -n1 || true)
  if [[ -z "$ver" ]]; then
    # Fallback: wiki de la comunidad (misma exclusión de preview)
    html=$(curl -fsSL --max-time 30 -A "mc-check/1.0" \
           "https://minecraft.wiki/w/Bedrock_Dedicated_Server" 2>/dev/null || true)
    ver=$(grep -oE 'bedrockdedicatedserver/bin-linux/bedrock-server-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.zip' <<<"$html" \
          | sed 's/.*bedrock-server-//; s/\.zip//' | sort -uV | tail -n1 || true)
  fi
  echo "${ver:-}"
}

webhook() {  # $1 = mensaje
  [[ -n "$MC_UPDATE_WEBHOOK" ]] || return 0
  curl -fsS --max-time 15 -H "Content-Type: application/json" \
       -d "{\"content\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")}" \
       "$MC_UPDATE_WEBHOOK" >/dev/null || log "WARN: webhook falló"
}

main() {
  local latest installed
  latest=$(latest_version)
  installed=$(installed_version)

  if [[ "${1:-}" == "--print" ]]; then
    echo "instalada=$installed latest=${latest:-?}"
    exit 0
  fi

  if [[ -z "$latest" ]]; then
    log "WARN: no se pudo determinar la última versión (¿bloqueo de Cloudflare?)"
    exit 0   # no es un error fatal: el cron se repetirá
  fi

  if [[ "$latest" == "$installed" ]]; then
    log "OK: BDS $installed es la última."
    exit 0
  fi

  log "NUEVA versión: $latest (instalada: $installed)"
  webhook "🆕 Nueva BDS disponible: **$latest** (instalada: $installed). Pasos: staging con \`check_version.sh --stage\`, gate del admin, luego \`update.sh --prod --yes\`."

  if [[ "${1:-}" == "--stage" ]]; then
    local updater="$MC_HOME/modules/update.sh"
    if [[ -x "$updater" ]]; then
      log "Lanzando staging..."
      "$updater" --stage || log "ERROR en staging (ver $MC_LOG_DIR)"
    else
      log "ERROR: no encuentro $updater"
      exit 1
    fi
  fi
}

main "${1:-}"
