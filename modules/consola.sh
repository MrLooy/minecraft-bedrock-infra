#!/usr/bin/env bash
# =============================================================================
# consola.sh — comandos in-game SIN RCON (D-17). BDS no tiene RCON; la consola
# es stdin del servicio, alimentado por un FIFO de systemd (mc.socket).
#   Uso:  consola.sh 'gamerule pvp true'
#         consola.sh 'kick Player'        consola.sh 'say Bienvenidos'
# Deja auditoría en logs/consola.log. Solo el admin vía panel (mods NO, D-17).
# =============================================================================
set -euo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

[[ $# -ge 1 ]] || { echo "uso: consola.sh '<comando>'" >&2; exit 1; }
[[ -p "$MC_FIFO" ]] || { echo "ERROR: no existe el FIFO $MC_FIFO (¿mc.socket activo?)" >&2; exit 1; }

mkdir -p "$MC_LOG_DIR"
echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" >> "$MC_LOG_DIR/consola.log"
printf '%s\n' "$*" > "$MC_FIFO"
echo "Enviado a la consola: $*"