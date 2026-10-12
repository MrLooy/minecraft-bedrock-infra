# Arquitectura Multi-Servidor Minecraft (Java test → reutilizable para Bedrock)

> Diseño v0.1 — prueba con 2 servidores Java vanilla (con opción futura de mods) sobre Oracle ARM.
> Objetivo: la MISMA arquitectura sirve para N servidores Java y para Bedrock después del test.

---

## 1. Principio de diseño: PODS REPLICABLES

Cada servidor Minecraft es un "pod" independiente definido solo por variables de entorno.
Añadir/quitar un servidor = añadir/quitar un bloque de ~15 líneas en Docker Compose.

```
┌──────────────────────────────  ORACLE CLOUD ARM (4 vCPU / 24 GB) ──────────────────────────────┐
│                                                                                              │
│   red docker interna: mc-network (bridge)                                                    │
│                                                                                              │
│   ┌────────────────┐   ┌────────────────┐   ┌────────────────┐                                │
│   │  server-a      │   │  server-b      │   │  server-c (fut)│   ... pod N                  │
│   │  Java vanilla  │   │  Java vanilla  │   │  (Bedrock)     │                               │
│   │  puerto 25565  │   │  puerto 25566  │   │  UDP 19132     │                               │
│   │  volumen world-a│  │  volumen world-b│  │  volumen world-c│                              │
│   │  RCON 25575    │   │  RCON 25576    │   │  RCON 19134    │                               │
│   └───────┬────────┘   └───────┬────────┘   └───────┬────────┘                                │
│           │                    │                    │                                         │
│           └──────────┬─────────┴─────────┬──────────┘                                         │
│                      │                   │                                                    │
│              ┌───────┴──────────────┐   │                                                     │
│              │  playit (1 agente,   │   │                                                     │
│              │  N túneles, red host)│   │                                                     │
│              └───────┬──────────────┘   │                                                     │
│                      │                  │                                                     │
│              ┌───────┴──────────────┐   │                                                     │
│              │  backup (rclone cron)│   │                                                     │
│              │  monta world-* (ro)  │   │                                                     │
│              └─────────────────────┘   │                                                     │
└────────────────────────────────────────┴─────────────────────────────────────────────────────┘
```

---

## 2. Cómo funciona cada pieza

### Servidor Java (pod replicable)
- Imagen oficial de la comunidad: **`itzg/minecraft-server`** (versión Java; NO confundir con `itzg/minecraft-bedrock-server`).
- En cada arranque descarga el binario del servidor de la versión pedida y lo ejecuta.
- **Hoy = vanilla:** `TYPE=VANILLA`.
- **Mañana = con mods SIN cambiar arquitectura:** cambiar a `TYPE=FABRIC` o `TYPE=FORGE` + `MODRINTH_PROJECTS=modulo1,modulo2` (o `MODS_URL=`). El volumen del mundo se conserva. Por eso es "vanilla con opción a mods".

### Playit multi-túnel (CLAVE del diseño)
- Para 1 solo servidor usábamos `network_mode: service:bedrock` (compartir red).
- Para N servidores eso no sirve → **playit corre en la red del host** (`network_mode: host`). Así el agente ve todos los puertos locales (`25565`, `25566`, luego `19132/udp`) y puede crear **varios túneles simultáneos** en el dashboard:
  - Túnel 1: TCP → `25565` = server-a (Java)
  - Túnel 2: TCP → `25566` = server-b (Java)
  - Túnel 3 (futuro): UDP → `19132` = Bedrock
- 1 agente, N túneles, 1 dashboard. Los jugadores solo ven `xx.playit.gg:puerto`.
- Ventaja extra: los **puertos del host siguen cerrados**; toda la exposición la hace Playit.

### Backup reutilizable
- Contenedor `alpine` + **rclone** + **cron** (03:00).
- Monta todos los volúmenes de mundos **read-only** en `/worlds/<server>/`.
- Script: por cada carpeta hace `tar.gz` → `rclone copy` a `r2:mc-backups/<server>/`.
- Añadir un servidor nuevo = 1 línea en el script. La retención y subida a nube son idénticas para todos.

---

## 3. Docker Compose (plantilla pod)

```yaml
services:
  server-a:
    image: itzg/minecraft-server:latest
    container_name: mc-java-a
    restart: unless-stopped
    environment:
      EULA: "TRUE"
      TYPE: "VANILLA"                # futuro: FABRIC o FORGE + MODRINTH_PROJECTS
      VERSION: "LATEST"
      SERVER_NAME: "Grupo Test A"
      MEMORY: "4G"
      SERVER_PORT: "25565"
      RCON_PORT: "25575"
      RCON_PASSWORD: "${RCON_A_PASSWORD}"
      MAX_PLAYERS: "10"
      VIEW_DISTANCE: "12"
      MOTD: "Vanilla test - grupo A"
    volumes:
      - world-a:/data
    networks: [mc-network]
    deploy:
      resources:
        limits: { cpus: "1.5", memory: 6G }
        reservations: { cpus: "0.5", memory: 4G }
    healthcheck:
      test: ["CMD-SHELL", "mcstatus localhost:$SERVER_PORT ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  server-b:      # mismo patrón, puerto 25566, RCON 25576, volumen world-b, cpus 1.5
    ...

  playit:
    image: playitgg/playit-cli:latest
    container_name: mc-playit
    restart: unless-stopped
    network_mode: "host"            # clave: ve TODOS los puertos → N túneles
    environment:
      PLAYIT_AUTH_KEY: "${PLAYIT_AUTH_KEY}"
      PLAYIT_SECRET_KEY: "${PLAYIT_SECRET_KEY}"

  backup:
    image: alpine:latest
    profiles: [backup]
    volumes:
      - world-a:/worlds/server-a:ro
      - world-b:/worlds/server-b:ro
      - ./scripts/backup-multi.sh:/backup.sh:ro
    networks: [mc-network]
    # cron 03:00 + rclone + R2 (mismo patrón que el stack Bedrock)

volumes:
  world-a: {}
  world-b: {}

networks:
  mc-network: { driver: bridge }
```

> NOTA: los contenedores Java NO se abren al host; solo `healthcheck` interno. El tráfico de jugadores va por playit (host network). La red `mc-network` queda para el backup y futuros servicios internos.

---

## 4. Migración a Bedrock (después del test)

La arquitectura NO cambia. Solo:

| Elemento | Java ahora | Bedrock después |
|----------|-----------|-----------------|
| Imagen | `itzg/minecraft-server` | `itzg/minecraft-bedrock-server` |
| Puertos | 25565/25566 (TCP) | 19132 (UDP) |
| Playit túnel | TCP | UDP |
| Volumen | world-a/world-b | world-bedrock |
| Backup | `r2:mc-backups/java/A` | `r2:mc-backups/bedrock` |

Playit multi-túnel, backup, rclone, red interna y policies de recursos se **reutilizan tal cual**.

---

## 5. Respuesta a tu duda: ¿dos servidores a la vez?

Sí. Cada uno es un contenedor independiente:
- Puerto TCP distinto (25565 / 25566) → mismo host, sin conflicto.
- Mundo separado (volume world-a / world-b).
- Jugadores grupos A y B no se ven entre sí.
- Límites propios de CPU/RAM con `deploy.limits` → si uno satura, el otro sigue.

**Capacidad estimada en Oracle A1 (4 vCPU/24 GB):**
- 2–3 servidores vanilla pequeños (1.5 CPU / 4-6 GB RAM cada uno) funcionan cómodos.
- Ambos con playit (host) + backup compartido.
- Java edition en ARM es algo más lenta que x86 → para grupos < 10 jugadores está perfecto.

---

## 6. Pendiente para levantar la prueba

- [ ] Crear instancia Oracle ARM (pasos ya documentados)
- [ ] `net.ipv4.ip_forward` / firewall: **solo SSH**, resto lo maneja playit
- [ ] Definir versión de Java (1.21.x) y si el futuro con mods será Fabric o Forge
- [ ] Dominios: 2 túneles TCP en dashboard Playit
- [ ] Test: conectar con un cliente Java a ambos `xx.playit.gg:puerto`