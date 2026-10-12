# Minecraft Bedrock Infra — Modular Server Operations

Opinionated infrastructure for running a production **Minecraft Bedrock** server on a
small VPS, built around a single configuration file and independent, testable modules.

> This repository is a sanitized showcase: VPS IPs, DNS zones, player IDs and provider
> details have been replaced with placeholders.

## Problem

Running a public Bedrock server by hand is fragile: updates can break the world,
backups get forgotten, and there is no safe way to check status or restart remotely.
This project turns the whole lifecycle — install → update → backup → monitor →
administer — into scripted, reversible steps driven by one config file.

## What's inside

- **`config/mc.conf`** — single source of truth: paths, ports, game settings and secrets
  (secrets come from the environment; nothing hardcoded).
- **`modules/`** — independent bash modules: version check, staged updates, backups,
  status, block management, console and a verified restart.
- **`system/`** — systemd units, UFW rules, fail2ban config and a scoped sudoers policy.
- **`panel/`** — Flask PWA admin panel (login, roles, live control, logs) served over HTTPS.
- **`bot/`** — Telegram management bot: status, players, restart, allow-list, with an
  allow-listed in-game console.
- **`bloques/`** — Bedrock behavior/resource pack catalog, custom packs and world templates.
- **`deploy/`** — deployment guide, `server.properties` and provider test scripts.
- **`docs/ARCHITECTURE.md`** — multi-server "pod" architecture (reusable for Java/Bedrock).

## Tech stack

Bash · systemd · UFW · fail2ban · Python (Flask + gunicorn) · Telegram Bot API ·
Minecraft Bedrock Dedicated Server · rclone.

## Design principles

- **One config file**: every module does `source config/mc.conf`; none hardcode paths.
- **Staged rollout**: every update is prepared and smoke-tested on staging first, then
  promoted to production behind a human gate.
- **Least privilege**: the panel runs as an unprivileged user with a narrow sudoers
  allow-list of specific scripts.
- **No committed secrets**: credentials only via environment variables / `mc.conf`.

## Getting started

```bash
sudo mkdir -p /opt/mcserver && cp -r . /opt/mcserver && cd /opt/mcserver
cp config/mc.conf /opt/mcserver/config/    # edit paths, ports and secrets
bash system/ufw.sh
systemctl enable --now mc
modules/status.sh                          # JSON status
```

The full walkthrough is in `deploy/GUIA_DESPLIEGUE.md` (Spanish).

## Repository layout

```
config/mc.conf          Single source of configuration
modules/                Independent ops modules (update, backup, status, blocks, ...)
system/                 systemd units, UFW, fail2ban, sudoers policy
panel/                  Flask PWA admin panel (app.py, templates, static)
bot/telegram_bot.py     Telegram management bot
bloques/                Bedrock pack catalog + custom packs + templates
deploy/                 Deployment guide, server.properties, test scripts
docs/ARCHITECTURE.md    Multi-server pod architecture
```

## Security notes

- Panel binds to `127.0.0.1` behind a reverse proxy; CSRF tokens and PBKDF2-hashed
  passwords; no built-in default credentials.
- The Telegram bot and in-game console enforce command allow-lists; destructive actions
  stay behind the authenticated panel.
- UFW is default-deny and fail2ban guards SSH/panel.
- Automatic backups are pruned locally and copied off-site.

## Result

A repeatable, low-cost operations stack: a public Bedrock server with verified staged
updates, daily off-site backups and remote administration from a phone.

## Credits

Built by **Elías Canaquiri (MrLooy) (MrLooy)**.

## License

MIT — see [LICENSE](LICENSE).
