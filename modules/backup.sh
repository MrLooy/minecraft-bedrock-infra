#!/usr/bin/env bash
# =============================================================================
# backup.sh — D-07 / D-20
# Módulo INDEPENDIENTE: copia comprimida del mundo + configs + bloques.
#   Uso:  backup.sh              → crea copia con timestamp
#         backup.sh --list       → lista copias
#         backup.sh --restore <archivo>   → restaura (servidor parado)
# Programado por system/mc-backup.timer. Copia fuera del VPS si MC_OFFSITE_CMD.
# =============================================================================
set -euo pipefail

CONF="${MC_CONF:-/opt/mcserver/config/mc.conf}"
[[ -f "$CONF" ]] || { echo "FATAL: no existe $CONF" >&2; exit 78; }
# shellcheck source=/dev/null
source "$CONF"

log() { echo "[$(date '+%F %T')] $*"; }

do_backup() {
  mkdir -p "$MC_BACKUP_DIR"
  local ts name out
  ts=$(date +%Y%m%d-%H%M%S)
  name="mcserver-$ts.tar.gz"
  out="$MC_BACKUP_DIR/$name"

  log "Backup → $out"
  # Servidor viva: BDS guarda el mundo de forma incremental, pero para
  # consistencia paramos <5 s si está activo.
  local stopped=0
  if systemctl is-active --quiet "$MC_SERVICE" 2>/dev/null; then
    systemctl stop "$MC_SERVICE"; stopped=1
  fi

  local items=(worlds server.properties allowlist.json permissions.json
               behavior_packs resource_packs config version.txt)
  tar czf "$out.tmp" -C "$MC_HOME" "${items[@]}" 2>/dev/null || true
  mv -f "$out.tmp" "$out"

  if [[ $stopped -eq 1 ]]; then systemctl start "$MC_SERVICE"; fi

  # Poda de copias antiguas
  local n
  n=$(find "$MC_BACKUP_DIR" -name 'mcserver-*.tar.gz' | wc -l)
  if (( n > MC_BACKUP_KEEP )); then
    find "$MC_BACKUP_DIR" -name 'mcserver-*.tar.gz' | sort | head -n $((n - MC_BACKUP_KEEP)) \
      | xargs -r rm -f
    log "Podadas $((n - MC_BACKUP_KEEP)) copias antiguas (keep=$MC_BACKUP_KEEP)"
  fi

  # Copia fuera del VPS (D-07): rclone, scp, rsync... lo que sea MC_OFFSITE_CMD
  if [[ -n "$MC_OFFSITE_CMD" ]]; then
    if MC_BACKUP_FILE="$out" bash -c "$MC_OFFSITE_CMD"; then
      log "Offsite OK"
    else
      log "WARN: copia offsite falló"
    fi
  fi

  log "OK: $(du -h "$out" | cut -f1) en $out"
}

do_restore() {
  local f="${1:-}"
  [[ -n "$f" && -f "$f" ]] || { log "ERROR: no existe el archivo $f"; exit 1; }
  read -r -p "¿Restaurar $f? Esto SOBRESCRIBE el mundo actual. [escribe RESTAURAR] " r
  [[ "$r" == "RESTAURAR" ]] || { log "Cancelado."; exit 1; }
  systemctl stop "$MC_SERVICE"
  mkdir -p "$MC_BACKUP_DIR"
  tar czf "$MC_BACKUP_DIR/autorestore-$(date +%s).tar.gz" -C "$MC_HOME" worlds 2>/dev/null || true
  tar xzf "$f" -C "$MC_HOME"
  systemctl start "$MC_SERVICE"
  log "Restaurado desde $f"
}

case "${1:-}" in
  "" )         do_backup ;;
  --list)      find "$MC_BACKUP_DIR" -name 'mcserver-*.tar.gz' -printf '%T+ %p\n' | sort ;;
  --restore)   do_restore "${2:-}" ;;
  *) echo "uso: backup.sh [--list | --restore <archivo>]"; exit 1 ;;
esac
