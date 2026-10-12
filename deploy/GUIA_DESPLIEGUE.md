# GUIA_DESPLIEGUE — despliegue completo del servidor

Runbook paso a paso. Orden estricto; cada paso tiene su verificación.
Todo en el VPS (Ubuntu 22.04/24.04 LTS, root vía SSH). Nada se compra sin el admin.

| # | Paso | Bloquea |
|---|------|---------|
| 0 | Ticket ExampleHost respondió **UDP 19132 OK** | todo |
| 1 | Compra VPS + acceso | — |
| 2 | Hardening base | — |
| 3 | Subir este repo a `/opt/mcserver` | — |
| 4 | Descargar BDS oficial | — |
| 5 | Config (server.properties + mc.conf) | — |
| 6 | Servicios systemd + firewall | — |
| 7 | Primer arranque + allow-list | — |
| 8 | Discord webhooks | — |
| 9 | Backups | — |
| 10 | Panel PWA + HTTPS | — |
| 11 | Bloques (add-ons) | — |
| 12 | Mundo (D-04) | apertura |
| 13 | Checklist pre-apertura | apertura |

---

## 0. Prerrequisito (RESUELTO ✅)

P-08: ExampleHost confirmó por escrito **UDP 19132/19133 sin filtrar**, 20 TiB/mes
(baja a 5 Mbps al agotarse), renovación $8, reembolso 3 días y Ubuntu 22.04/24.04.
Queda el ticket 2 (DDoS + facturación, texto en `TICKETS.md`) y la aprobación del admin.

## 1. Compra VPS + prueba de 3 días

1. `https://example.com/vps/us/` → plan **USD 8/mes** (2 vCPU / 4 GiB / 60 GB NVMe).
2. SO: **Ubuntu 22.04 LTS** o 24.04 (único soportado por Mojang).
3. Guardar IP y credenciales root en el gestor de contraseñas del admin.
4. **Prueba de reembolso EL MISMO DÍA** (ToS §7.2, 3 días; no al límite):
   - VPS: `sudo bash deploy/pruebas_3_dias.sh 30`
   - PC del admin (Peru): `.\deploy\prueba_cliente.ps1 -Ip <IP>` ×2 (mediodía y noche)
   - Entrada real con un cliente Bedrock en los dos horarios.
   - **Si RAM > 3.2 GB, pérdida de paquetes o el mundo no carga → reembolso.**
5. Verificar desde la PC del admin: `ping -n 20 <IP>` y `nmap -sS -p 19132 <IP>` (BDS 1.26 = NetherNet → handshake HTTP/TCP en 19132; el juego va por UDP 19132-19232).

## 2. Hardening base

```bash
apt update && apt -y upgrade && apt -y install curl wget unzip jq ufw fail2ban git python3 python3-venv
useradd -m -s /bin/bash mcserver
useradd -m -s /bin/bash mcpanel
# SSH: clave pública, NO password (el admin copia su pubkey)
mkdir -p /root/.ssh && chmod 700 /root/.ssh
# /etc/ssh/sshd_config: PasswordAuthentication no · PermitRootLogin prohibit-password
systemctl restart ssh
```

## 3. Subir el repo

```bash
git clone <repo> /opt/mcserver   # o scp -r
chmod +x /opt/mcserver/modules/*.sh /opt/mcserver/system/*.sh
cp /opt/mcserver/deploy/server.properties /opt/mcserver/server.properties   # si no existe
mkdir -p /opt/mcserver/{logs,worlds,behavior_packs,resource_packs,blocks.d,staging} \
         /var/backups/mcserver
chown -R mcserver:mcserver /opt/mcserver
# staging lo usa el panel (mcpanel) sin sudo en su smoke test:
chown -R mcpanel:mcserver /opt/mcserver/staging
```

## 4. Descargar BDS oficial

```bash
cd /opt/mcserver
VER=$(modules/check_version.sh --print | sed 's/.*latest=//')
wget "https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-$VER.zip"  # o curl -fSL
unzip -o "bedrock-server-$VER.zip" -d /opt/mcserver
rm "bedrock-server-$VER.zip"
chmod +x bedrock_server
echo "$VER" > version.txt
# ¡IMPORTANTE! El zip trae su propio server.properties y PISA el nuestro al
# descomprimir. SIEMPRE re-copiar la plantilla tras unzip:
cp /opt/mcserver/deploy/server.properties /opt/mcserver/server.properties
```

## 5. Config

1. `config/mc.conf` → revisar `MC_UPDATE_WEBHOOK` / `MC_STATUS_WEBHOOK` (paso 8),
   `MC_PANEL_SECRET` (`openssl rand -hex 32`), `MC_PANEL_ADMIN_PASS`.
2. `server.properties` → `server-name` / `motd` (P-04, cuando el admin decida).
3. `online-mode=true` de momento (**fase C**, D-14).

## 6. Servicios + firewall

```bash
cd /opt/mcserver
cp system/mc.service /etc/systemd/system/
cp system/mc.socket /etc/systemd/system/
cp system/mc-backup.* system/mc-checkver.* system/mc-status.* /etc/systemd/system/
cp system/mc-panel.service /etc/systemd/system/
mkdir -p /etc/sudoers.d && cp system/sudoers-panel /etc/sudoers.d/mc-panel
chmod 440 /etc/sudoers.d/mc-panel
cp system/fail2ban-jail.local /etc/fail2ban/jail.d/
cp system/fail2ban-filter-panel.conf /etc/fail2ban/filter.d/mc-panel.conf
systemctl daemon-reload
systemctl enable --now mc.socket mc
systemctl enable --now mc-backup.timer mc-checkver.timer mc-status.timer
systemctl enable --now fail2ban
bash system/ufw.sh
```

Verificar: `ss -tlpn | grep 19132` (TCP escuchando, handshake NetherNet) y `journalctl -u mc -f`.

## 7. Primer arranque

1. `journalctl -u mc -f` → debe decir `Server started` sin `[ERROR]`.
2. PVP: `echo "gamerule pvp false" > /proc/$(pgrep -f bedrock_server)/fd/0`
   no es fiable → **usar la consola del panel** o Steam-independent: crear
   `worlds/world/functions` **o** confiar en el bloque `bp_rules` (paso 11).
3. Allow-list (20 nicks, D-02): `scripts/allowlist.json` → en Bedrock se edita
   con `allowlist.json` en la raíz o con `/allowlist add <gamertag>` por consola.
   **Usar gamertags reales de Xbox**, no nombres inventados.
4. Probar desde el celular del admin: Xbox Live `online-mode=true`.
5. **Consola in-game** (reemplazo del RCON): `modules/consola.sh 'say Hola'`
   escribe en el FIFO `mc.socket` y audita en `logs/consola.log`. Probar kick/gamerule.
6. **Al terminar la semana 1 (fase C, D-25):** `modules/valida_offline.sh --baseline`
   guarda los pares (xuid, gamertag) originales del log viejo. Solo entonces se
   activa `online-mode=false`; `valida_offline.sh --watch` marcará a los nuevos
   cada 5 min (junto a `status.sh` en `mc-status.timer`).

## 8. Discord (3 webhooks)

Crear en Discord → Integraciones → Webhooks (uno por uso):

| Webhook | Variable `mc.conf` | Uso |
|---------|--------------------|-----|
| avisos-update | `MC_UPDATE_WEBHOOK` | nueva versión BDS, staging verde/rojo |
| contador | `MC_STATUS_WEBHOOK` | cola Q1 (cada 5 min o al cambiar) |
| panel-alerts | (futuro) | caídas |

Tras editar `mc.conf`: `systemctl restart mc-status.timer` (releer env: los
timers usan Environment= fijo → reiniciar los timers o pasar MC_CONF explícito).

## 9. Backups

- Local: `modules/backup.sh` corre a las 04:00 (`mc-backup.timer`).
- **Fuera del VPS (D-07 obligatorio):** instalar `rclone` y configurar en
  `mc.conf`: `MC_OFFSITE_CMD="rclone copy --config /root/.rclone.conf \"$MC_BACKUP_FILE\" gdrive:mc-backups"`
  (Drive 15 GB gratis ≈ 3 semanas de copias; o el Dropbox 2 GB del admin).
- Probar: `modules/backup.sh && modules/backup.sh --list`.

## 10. Panel PWA (D-17)

```bash
cd /opt/mcserver/panel
python3 -m venv venv && ./venv/bin/pip install -r requirements.txt
chown -R mcpanel:mcpanel /opt/mcserver/panel /opt/mcserver/logs
systemctl enable --now mc-panel
```

- Bootstrap: primer arranque crea usuario `admin` con `MC_PANEL_ADMIN_PASS`.
  **Cambiar la contraseña tras el primer login.**
- Acceso: solo `127.0.0.1:8443` (default). Para HTTPS público (obligatorio D-17)
  con el dominio **example.com**:

```bash
# 1) DNS (panel de tu registrador .lat): A record →  panel.example.com = <IP VPS>
# 2) Caddy como proxy inverso con Let's Encrypt automático:
apt install -y caddy
# /etc/caddy/Caddyfile:
# panel.example.com { reverse_proxy 127.0.0.1:8443 }
caddy reload --config /etc/caddy/Caddyfile
```

- Sin dominio alternativo: certificado autosignado con Caddy igual funciona.
- fail2ban ya protege el login (`panel-auth.log`).

## 11. Bloques (D-08)

```bash
# propios (incluidos)
modules/install_block.sh add /opt/mcserver/bloques/bp_rules bp
modules/install_block.sh add /opt/mcserver/bloques/bp_status bp
# de terceros: descargar a blocks.d/ y:
# modules/install_block.sh add /opt/mcserver/blocks.d/AdvancedGravestone bp
modules/install_block.sh list
systemctl restart mc
```

Orden recomendado (B6 antes de generar mundo): **estructuras → mobs (B8) →
armas (B9) → tumbas/mochilas/ores → land claim (probar RAM en staging)**.

## 12. Mundo (D-04 / D-23)

1. Generar/convertir el mundo ±7500 con **Chunker**.
2. **Pre-renderizar el mundo por completo** antes de abrir (sin zonas sin cargar).
3. Definir las **zonas seguras sin PvP (D-22)** sobre ese mundo ya renderizado.
4. Tras pre-generar: snapshot con `modules/backup.sh`.

## 13. Checklist pre-apertura

- [ ] `ss -tlpn | grep 19132` escucha (TCP, NetherNet); entra un cliente desde 4G/claro
- [ ] `mc.service` activo tras reboot (`reboot` de prueba)
- [ ] 20 en allow-list con gamertags reales, `max-players=15`
- [ ] **PVP encendido (D-22)** y zonas seguras sin PvP probadas dentro de la zona (B7 o `bp_zonas`)
- [ ] Backup 04:00 OK + copia offsite visible en Drive/Dropbox
- [ ] Panel por HTTPS con 2FA-ish (contraseña fuerte) y fail2ban activo
- [ ] Webhooks llegan a Discord
- [ ] `mc-checkver.timer` probado (`systemctl start mc-checkver.service`)
- [ ] RAM estable: `systemctl show mc -p MemoryCurrent` < 3.2 GB (D-13)
- [ ] Nombre/MOTD finales (P-04)

---

## Operación diaria

| Tarea | Cómo |
|-------|------|
| Ver estado | panel o `modules/status.sh` |
| Reiniciar | panel (mod+) o `systemctl restart mc` |
| Comando in-game | `modules/consola.sh 'gamerule pvp true'` (auditado) |
| Nueva versión | cron alerta → `check_version.sh --stage` → gate en panel |
| Añadir bloque | `install_block.sh add <ruta> bp\|rp` + restart |
| Validar jugador nuevo (fase C) | automático cada 5 min; manual: `valida_offline.sh --check` |
| Backup manual | `modules/backup.sh` |
| Q1 contador | Discord cada 5 min (`mc-status.timer`) |

## Emergencias

- **Se queda sin RAM:** `MemoryMax` frena a 3.5 GB; si revienta → plan B 8 GB
  (Contabo NY / OVH US) y re-despliegue = solo `mc.conf` (D-20).
- **Versión roja en staging:** no tocar producción; avisar en Discord.
- **Mundo corrupto:** `backup.sh --restore <archivo>` (servidor para solo).
