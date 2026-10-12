#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# telegram_bot.py — Bot de gestión del servidor Minecraft para admins (D-28).
# Solo biblioteca estándar (urllib, long-polling). Lo levanta systemd con el
# entorno de mc.conf ya exportado:
#   ExecStart=/bin/bash -c 'source /opt/mcserver/config/mc.conf && exec python3 ...'
#
# Seguridad:
#  - Solo responden los Telegram IDs de MC_BOT_ADMINS (sin contraseñas).
#  - Consola con LISTA BLANCA (D-28c): list, say, tell, kick, gamerule, allowlist.
#    Nunca stop/op/deop por consola; reinicio solo con /restart (systemctl).
#  - Cada acción queda auditada en logs/bot.log y logs/consola.log.
# =============================================================================
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

HOME = os.environ.get("MC_HOME", "/opt/mcserver")
LOG_DIR = os.environ.get("MC_LOG_DIR", f"{HOME}/logs")
FIFO_CMD = os.environ.get("MC_BOT_FIFO_CMD", f"{HOME}/modules/consola.sh")
SERVICE = os.environ.get("MC_SERVICE", "mc")
VERSION_FILE = os.environ.get("MC_VERSION_FILE", f"{HOME}/version.txt")
MAX_PLAYERS = os.environ.get("MC_MAX_PLAYERS", "15")

BOT_LOG = os.path.join(LOG_DIR, "bot.log")

# Lista blanca de la consola (D-28c). Todo lo demás se rechaza.
ALLOWED_CMD = ("list", "say", "tell", "kick", "gamerule", "allowlist")

TG_BASE = "https://api.telegram.org"


def log(*a):
    line = time.strftime("%Y-%m-%d %H:%M:%S") + " | " + " ".join(str(x) for x in a)
    print(line, flush=True)
    try:
        with open(BOT_LOG, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def run(*argv, timeout=15):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.stdout + p.stderr
    except Exception as e:  # noqa: BLE001
        return f"ERROR: {e}"


def sudo_systemctl(*rest):
    return run("/usr/bin/sudo", "/usr/bin/systemctl", *rest).strip()


def service_active():
    return sudo_systemctl("is-active", SERVICE) == "active"


def journal(recent="since -7 days", extra=()):
    return run("/usr/bin/sudo", "/usr/bin/journalctl", "-u", SERVICE,
               "--no-pager", "--output", "cat", "--since", recent, *list(extra))


def version():
    try:
        with open(VERSION_FILE, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return "?"


def memory():
    try:
        path = f"/sys/fs/cgroup/system.slice/{SERVICE}.service/memory.current"
        with open(path) as fh:
            return int(fh.read().strip()) // 1024  # KiB
    except OSError:
        pass
    pid = run("/usr/bin/pgrep", "-f", "bedrock_server").strip().splitlines()
    for p in pid:
        try:
            rss = run("/usr/bin/ps", "-o", "rss=", "-p", p).strip()
            if rss:
                return int(rss)
        except (ValueError, OSError):
            continue
    return 0


def parse_players(seg):
    seen, order = {}, []
    for l in seg:
        m = re.search(r"Player (connected|disconnected): ([^,]+)", l)
        if m:
            name = m.group(2).strip()
            if name not in seen:
                order.append(name)
            seen[name] = m.group(1) == "connected"
    return [n for n in order if seen[n]]


def session():
    """(online, names) desde el último 'Server started'."""
    txt = journal()
    try:
        start = txt.rindex("Server started")
    except ValueError:
        return 0, []
    seg = txt[start:].splitlines()
    names = parse_players(seg)
    return len(names), names


def status_text():
    act = service_active()
    online, names = session()
    if act:
        st = "🟢 **En línea**"
    else:
        st = "🛑 **Caído**"
    up = ""
    stt = sudo_systemctl("status", SERVICE)
    m = re.search(r"Active: \S+ \(running\) since ([^;]+)", stt)
    if m:
        up = m.group(1).strip()
    txt = [
        st,
        f"Versión: `{version()}`",
        f"Jugadores: **{online}/{MAX_PLAYERS}**"
        + (f" — {', '.join(names)}" if names else ""),
        f"RAM: {memory() // 1024} MB",
        f"Uptime: {up}",
    ]
    return "\n".join(txt)


def game_output(tail_since="since -6s", contains=()):
    """Últimas líneas del journal del juego (para confirmar un comando)."""
    out = journal(recent=tail_since)
    lines = [l.strip() for l in out.splitlines() if l.strip()]
    if contains:
        lines = [l for l in lines if any(c.lower() in l.lower() for c in contains)]
    return lines[-1] if lines else ""


def console(cmd, confirm=()):
    """Envía un comando a la consola del juego por el FIFO (consola.sh)."""
    r = run("/bin/bash", FIFO_CMD, cmd)
    if "Enviado" not in r and "enviado" not in r.lower():
        return f"⚠️ No llegó a la consola: {r.strip()[:120]}"
    if confirm:
        time.sleep(2.5)
        e = game_output(contains=confirm)
        if e:
            return f"✅ {e}"
    return "✅ Enviado a la consola."


def tg_json(method, **params):
    token = os.environ.get("MC_BOT_TOKEN", "")
    url = f"{TG_BASE}/bot{token}/{method}"
    data = urllib.parse.urlencode(params).encode("utf-8")
    req = urllib.request.Request(url, data=data)
    try:
        with urllib.request.urlopen(req, timeout=35) as res:
            return json.loads(res.read().decode("utf-8"))
    except Exception as e:  # noqa: BLE001
        log("api", method, "error:", repr(e)[:160])
        return None


def reply(chat_id, text):
    tg_json("sendMessage", chat_id=chat_id, text=text,
            parse_mode="Markdown", disable_web_page_preview="true")


def auth_ok(tg_id):
    admins = [a.strip() for a in
              os.environ.get("MC_BOT_ADMINS", "").split(",") if a.strip()]
    return str(tg_id) in admins


def admin_ids():
    return [a.strip() for a in
            os.environ.get("MC_BOT_ADMINS", "").split(",") if a.strip()]


def restart_bds():
    """Reinicio ASEGURADO (D-33): módulo compartido con el panel, verifica
    systemd + puerto TCP + 'Server started'. Devuelve (ok: bool, resumen)."""
    out = run("/usr/bin/sudo", "-n", "/opt/mcserver/modules/restart_server.sh",
              "restart", timeout=170).strip()
    log("restart", out[-200:])
    lines = [l for l in out.splitlines() if "[OK]" in l or "[FAIL]" in l]
    ok = any(l.startswith("[OK]") for l in lines)
    head = lines[-1] if lines else (out[-120:] or "sin salida")
    return ok, head


def watchdog_loop():
    """Vigila el servicio en segundo plano; avisa a los admins si BDS cae
    (5 min seguidos) y cuando se recupera. Rueda aparte del long-polling."""
    down_since = None
    notified = False
    while True:
        time.sleep(60)
        try:
            act = service_active()
        except Exception:  # noqa: BLE001
            continue
        if act:
            if notified:
                notified = False
                down_since = None
                log("watchdog: server recuperado")
                for cid in admin_ids():
                    reply(cid, "🟢 **BDS recuperado** — volvió a estar en línea.")
            continue
        if down_since is None:
            down_since = time.time()
        elif not notified and time.time() - down_since >= 5 * 60:
            notified = True
            log("watchdog: ALERTA BDS caído")
            for cid in admin_ids():
                reply(cid, "🚨 **ALERTA**: el BDS lleva **caído ~5 min**.\n"
                           "`/status` para ver · `/restart` para reiniciarlo.")


def dispatch(chat_id, tg_id, name, text):
    parts = text.strip().split()
    if not parts:
        return
    cmd = parts[0].lstrip("/").lower()
    args = parts[1:]

    help_txt = (
        "Comandos:\n"
        "`/status` · estado del server\n"
        "`/players` · quién está online\n"
        "`/restart` · reiniciar BDS\n"
        "`/allow <gamertag>` · invitar a entrar\n"
        "`/unallow <gamertag>` · quitar invitación\n"
        "`/kick <jugador>`\n`/ban <jugador>` · `/unban <jugador>`\n"
        "`/say <texto>` · mensaje a todos\n"
        "`/c <cmd>` · consola (lista blanca: "
        "list, say, tell, kick, gamerule, allowlist)\n"
        "`/help`\n"
        "El bot avisa solo si el server se cae y cuando vuelve (D-33)."
    )
    if cmd in ("start", "help"):
        reply(chat_id, help_txt)
        return

    if cmd == "status":
        reply(chat_id, status_text())
        return

    if cmd == "players":
        online, names = session()
        r = f"**{online}/{MAX_PLAYERS}** online\n" + \
            ("- " + "\n- ".join(f"`{n}`" for n in names) if names else
             "Nadie conectado.")
        reply(chat_id, r)
        return

    if cmd == "restart":
        reply(chat_id, "🔄 Reiniciando BDS… (verificación completa, ~1 min)")
        ok, head = restart_bds()
        time.sleep(2)
        act = service_active()
        online, _ = session()
        txt = (head if ok else "❌ " + head)
        txt += f"\nEstado: {'🟢 activo' if act else '🛑 caído'}"
        txt += f"\nJugadores: {online}/{MAX_PLAYERS}"
        reply(chat_id, txt)
        return

    if cmd == "say":
        if not args:
            reply(chat_id, "Uso: /say <texto>")
            return
        reply(chat_id, console("say " + " ".join(args), confirm=("say",)))
        return

    if cmd == "kick":
        if not args:
            reply(chat_id, "Uso: /kick <jugador>")
            return
        reply(chat_id, console("kick " + args[0], confirm=("kicked", "kick")))
        return

    if cmd in ("allow", "unallow"):
        if not args:
            reply(chat_id, f"Uso: /{cmd} <gamertag>")
            return
        tag = args[0]
        action = "add" if cmd == "allow" else "remove"
        reply(chat_id, console(f"allowlist {action} {tag}", confirm=(tag,)))
        return

    if cmd in ("ban", "unban"):
        if not args:
            reply(chat_id, f"Uso: /{cmd} <jugador>")
            return
        target = args[0]
        reply(chat_id, console(
            ("ban " if cmd == "ban" else "unban ") + target,
            confirm=(target, "banned", "unbanned")))
        return

    if cmd in ("c", "console"):
        if not args:
            reply(chat_id, "Uso: /c <comando>")
            return
        first = args[0].lower()
        if not first.startswith(ALLOWED_CMD):
            reply(chat_id,
                  "⛔ Comando fuera de la lista blanca. Permitidos: "
                  + ", ".join(ALLOWED_CMD))
            return
        reply(chat_id, console(" ".join(args), confirm=(args[0],)))
        return

    reply(chat_id, "No reconozco eso. `/help`")


def main():
    enabled = os.environ.get("MC_BOT_ENABLED", "false").lower() == "true"
    token = os.environ.get("MC_BOT_TOKEN", "")
    admins = [a.strip() for a in os.environ.get("MC_BOT_ADMINS", "").split(",")
              if a.strip()]
    if not enabled or not token:
        log("bot no configurado (MC_BOT_ENABLED/MC_BOT_TOKEN) — sale limpio.")
        return 0
    if not admins:
        log("bot sin admins (MC_BOT_ADMINS vacío) — sale limpio.")
        return 0

    log("bot iniciado, admins:", len(admins))
    threading.Thread(target=watchdog_loop, daemon=True).start()
    offset = 0
    while True:
        r = tg_json("getUpdates", timeout=25, offset=offset)
        if not r or not r.get("ok"):
            time.sleep(5)
            continue
        for up in r.get("result", []):
            offset = max(offset, up.get("update_id", 0) + 1)
            msg = up.get("message") or up.get("edited_message")
            if not msg:
                continue
            chat_id = msg.get("chat", {}).get("id")
            tg_id = msg.get("from", {}).get("id")
            txt = (msg.get("text") or "").strip()
            uname = (msg.get("from") or {}).get("username", "?")
            if not txt:
                continue
            log("msg", "user=", tg_id, "text=", txt[:80])
            if not auth_ok(tg_id):
                log("ignorado (no autorizado) user=", tg_id)
                continue
            try:
                dispatch(chat_id, tg_id, uname, txt)
            except Exception as e:  # noqa: BLE001
                log("error handler:", repr(e)[:200])


if __name__ == "__main__":
    sys.exit(main())