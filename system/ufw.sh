#!/usr/bin/env bash
# ufw.sh — firewall (D-17). Se ejecuta en el despliegue y queda como referencia.
set -euo pipefail
source /opt/mcserver/config/mc.conf

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH con rate-limit (previene fuerza bruta)
ufw limit 22/tcp comment 'SSH'

# Minecraft Bedrock UDP (NetherNet): handshake HTTP/TCP + tráfico UDP en rango.
# UFW exige ':' en los rangos (19132:19232/udp), no guion.
ufw allow "$MC_PORT"/tcp comment 'BDS NetherNet handshake'
ufw allow "${MC_UDP_RANGE//-/:}"/udp comment 'BDS NetherNet gameplay UDP'

# Staging: smoke test de actualización (same modelo, puerto propio)
ufw allow "$MC_STAGING_PORT"/tcp comment 'staging BDS handshake'
ufw allow "$MC_STAGING_PORT:$((MC_STAGING_PORT+99))"/udp comment 'staging BDS gameplay'

# Panel por HTTPS: el panel escucha en 127.0.0.1 (MC_PANEL_BIND),
# Caddy hace de proxy y necesita 80 (Let's Encrypt) y 443.
ufw allow 80/tcp comment 'Caddy HTTP->HTTPS'
ufw allow 443/tcp comment 'Panel HTTPS'

ufw --force enable
ufw status verbose
