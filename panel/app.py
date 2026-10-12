#!/usr/bin/env python3
"""Panel PWA fase 2 (D-17/D-18) — login, roles, estado, control y gate D-11.

D-43: añade funcionalidades tipo Aternos compatibles con BDS:
  allowlist, opciones (server.properties), copias de seguridad, mundos,
  tareas programadas, gamerules en vivo y gráfica de recursos.
"""
import collections
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import hashlib
import hmac
import json
import os
import re
import secrets
import subprocess
import threading
import time
from functools import wraps
from pathlib import Path

from flask import (Flask, abort, flash, jsonify, redirect, render_template,
                   request, session, url_for)
from waitress import serve

# ------------------------------------------------------------------ config --
def _expand(v, ctx):
    """Expande ${VAR:-default}, ${VAR} y $VAR usando ctx (keys ya leídas) y
    el entorno. Necesario porque mc.conf usa esa sintaxis bash (D-20)."""
    def repl(m):
        var, default = m.group(1), m.group(2) or ""
        if ctx.get(var):
            return ctx[var]
        if os.environ.get(var):
            return os.environ[var]
        return default
    v = re.sub(r"\$\{(\w+):-([^}]*)\}", repl, v)
    v = re.sub(r"\$\{(\w+)\}", lambda m: ctx.get(m.group(1)) or os.environ.get(m.group(1), ""), v)
    v = re.sub(r"\$(\w+)", lambda m: ctx.get(m.group(1)) or os.environ.get(m.group(1), ""), v)
    return v

def load_conf():
    conf = os.environ.get("MC_CONF", "/opt/mcserver/config/mc.conf")
    out = {}
    try:
        for line in Path(conf).read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.removeprefix("export ").strip()
            v = v.strip()
            # comentarios al final de la línea (" # ...") están fuera de las comillas
            if v[:1] in ('"', "'"):
                q = v[0]
                end = v.find(q, 1)
                if end > 0:
                    v = v[1:end]
            else:
                v = v.split(" #", 1)[0].strip()
            v = _expand(v, out)
            out[k] = v
    except FileNotFoundError:
        pass
    return out

C = load_conf()
MC_HOME = C.get("MC_HOME", "/opt/mcserver")
MC_SERVICE = C.get("MC_SERVICE", "mc")
MC_MAX_PLAYERS = C.get("MC_MAX_PLAYERS", "15")
LOG_DIR = Path(C.get("MC_LOG_DIR", f"{MC_HOME}/logs"))
LOG_DIR.mkdir(parents=True, exist_ok=True)
PANEL_DIR = Path(__file__).resolve().parent
USERS_FILE = PANEL_DIR / "users.json"
AUDIT = LOG_DIR / "panel-audit.log"
AUTH_LOG = LOG_DIR / "panel-auth.log"
RES_FILE = LOG_DIR / "resources.json"
PANEL_ADMIN = f"{MC_HOME}/modules/panel_admin.sh"
SECRET = C.get("MC_PANEL_SECRET") or secrets.token_hex(32)
BIND = C.get("MC_PANEL_BIND", "127.0.0.1")
PORT = int(C.get("MC_PANEL_PORT", "8443"))

app = Flask(__name__)
app.secret_key = SECRET
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax",
                  PERMANENT_SESSION_LIFETIME=86400 * 7)

SYSTEMCTL = "/usr/bin/systemctl"
JOURNALCTL = "/usr/bin/journalctl"
GAME_ADMIN = f"{MC_HOME}/modules/game_admin.sh"
FOUNDER = C.get("MC_FOUNDER", "founder")  # gamertag del fundador (root), D-34

# ------------------------------------------------------------- utilidades ---
def sh(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + r.stderr).strip()
    except Exception as e:  # noqa: BLE001
        return f"ERROR: {e}"

def sudo_sh(cmd, timeout=30):
    """Vía sudo restringida por /etc/sudoers.d/mc-panel."""
    return sh(["/usr/bin/sudo", "-n"] + cmd, timeout=timeout)

def audit(user, action, detail=""):
    with AUDIT.open("a", encoding="utf-8") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} user={user} action={action} {detail}\n")

def hash_pw(pw, salt=None):
    salt = salt or secrets.token_hex(16)
    h = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), 200_000).hex()
    return salt, h

def load_users():
    if USERS_FILE.exists():
        return json.loads(USERS_FILE.read_text(encoding="utf-8"))
    # arranque inicial: admin con MC_PANEL_ADMIN_PASS
    boot = C.get("MC_PANEL_ADMIN_PASS") or ""
    if not boot:
        return {}
    salt, h = hash_pw(boot)
    users = {"admin": {"salt": salt, "hash": h, "role": "root", "enabled": True}}
    save_users(users)
    return users

def save_users(users):
    USERS_FILE.write_text(json.dumps(users, indent=2), encoding="utf-8")
    USERS_FILE.chmod(0o600)

def current_user():
    u = session.get("user")
    if not u:
        return None
    users = load_users()
    if u not in users or not users[u].get("enabled", True):
        return None
    return {"name": u, "role": users[u]["role"]}

# D-34: jerarquía root > admin > mod. login_required(role=MINIMO).
RANK = {"mod": 1, "admin": 2, "root": 3}

def login_required(role=None):
    need = RANK.get(role, 0) if role else 0
    def deco(fn):
        @wraps(fn)
        def inner(*a, **kw):
            user = current_user()
            if not user:
                return redirect(url_for("login", next=request.path))
            if RANK.get(user["role"], 0) < need:
                abort(403)
            return fn(user, *a, **kw)
        return inner
    return deco

def csrf_ok():
    return hmac.compare_digest(session.get("csrf", ""), request.form.get("csrf", ""))

# límite de intentos de login (5/min por IP)
_attempts = {}
def rate_limited(ip):
    now = time.time()
    wins = [t for t in _attempts.get(ip, []) if now - t < 60]
    _attempts[ip] = wins
    return len(wins) >= 5

# ---------------------------------------------------------------- estado ----
def server_state():
    st = sh([SYSTEMCTL, "is-active", MC_SERVICE])
    active = st == "active"
    ts = sh([SYSTEMCTL, "show", MC_SERVICE, "--property=ActiveEnterTimestamp", "--value"])
    uptime = 0
    try:
        import datetime as dt
        started = dt.datetime.strptime(ts.strip(), "%a %Y-%m-%d %H:%M:%S %Z")
        uptime = int((dt.datetime.now() - started).total_seconds())
    except Exception:  # noqa: BLE001
        pass
    mem = sh([SYSTEMCTL, "show", MC_SERVICE, "--property=MemoryCurrent", "--value"])
    try:
        mem_mb = int(mem.strip().strip('"')) // (1024 * 1024)
    except ValueError:
        mem_mb = 0
    version = "desconocida"
    vf = Path(C.get("MC_VERSION_FILE", f"{MC_HOME}/version.txt"))
    if vf.exists():
        version = vf.read_text().strip()
    return {"active": active, "status": st, "uptime_s": uptime,
            "ram_mb": mem_mb, "version": version}

def journal_tail(n=800):
    txt = sudo_sh([JOURNALCTL, "-u", MC_SERVICE, "--no-pager", "-o", "cat", "-n", str(n)])
    # [PSTAT] (D-39) es telemetría cada 2 s: no la ensuciamos en la consola.
    return "\n".join(l for l in txt.splitlines() if "[PSTAT]" not in l)

def players_online():
    """Nº de jugadores en línea. Fuente autoritativa: último latido
    `[STATUS] online=N` de bp_status (se emite al entrar/salir y cada 5 s).
    Si no hay latido (p. ej. pack ausente), se usa el diff conectar/desconectar."""
    txt = sudo_sh([JOURNALCTL, "-u", MC_SERVICE, "--no-pager", "-o", "cat", "-n", "2000"])
    n = None
    for l in txt.splitlines():
        m = STATUS_RE.search(l)
        if m:
            n = int(m.group(1))
    if n is not None:
        return n
    txt = sudo_sh([JOURNALCTL, "-u", MC_SERVICE, "--no-pager", "-o", "cat", "--since", "-7 days"])
    lines = txt.splitlines()
    start = 0
    for i, l in enumerate(lines):
        if "Server started" in l:
            start = i
    seg = lines[start:]
    conn = sum(1 for l in seg if "Player connected" in l)
    disc = sum(1 for l in seg if "Player disconnected" in l)
    return max(0, conn - disc)

def last_names(limit=15):
    txt = sudo_sh([JOURNALCTL, "-u", MC_SERVICE, "--no-pager", "-o", "cat", "-n", "2000"])
    seen = {}
    for l in txt.splitlines():
        m = re.search(r"Player (connected|disconnected): ([^,]+)", l)
        if m:
            seen[m.group(2)] = m.group(1) == "connected"
    return sorted([n for n, on in seen.items() if on])[:limit]

# --- Historial de jugadores (todos los que entraron alguna vez · última conexión) ---
SEEN_FILE = LOG_DIR / "players_seen.json"
LIMA_TZ = ZoneInfo("America/Lima")
_seen_lock = threading.Lock()
_seen_cache = None

def load_seen():
    global _seen_cache
    if _seen_cache is None:
        data = {}
        if SEEN_FILE.exists():
            try:
                data = json.loads(SEEN_FILE.read_text(encoding="utf-8"))
            except (ValueError, OSError):
                data = {}
        _seen_cache = data
    return _seen_cache

def save_seen():
    if _seen_cache is None:
        return
    try:
        SEEN_FILE.write_text(
            json.dumps(_seen_cache, ensure_ascii=False, sort_keys=True, indent=1),
            encoding="utf-8")
    except OSError:
        pass

_JTS = re.compile(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[+-]\d{2}:\d{2}|Z))")
_JCONN = re.compile(r"Player connected: ([^,]+), xuid: (\d+)")
_JDISC = re.compile(r"Player disconnected: ([^,]+), xuid: (\d+)")

def refresh_seen_from_journal():
    """Escanea el journal por conexiones/desconexiones y actualiza el registro
    persistente (idempotente: guarda first_seen mínimo y last_seen máximo)."""
    txt = sudo_sh([JOURNALCTL, "-u", MC_SERVICE, "--no-pager", "-o", "short-iso",
                   "--since", "-60 days", "-g", "Player (connected|disconnected)"],
                  timeout=90)
    with _seen_lock:
        seen = load_seen()
        changed = False
        for line in txt.splitlines():
            m = _JTS.match(line)
            if not m:
                continue
            iso = m.group(1)
            mc = _JCONN.search(line)
            if mc:
                name, xuid = mc.group(1).strip(), mc.group(2)
                e = seen.setdefault(name, {})
                if "first_seen" not in e or iso < e["first_seen"]:
                    e["first_seen"] = iso
                if iso > e.get("last_seen", ""):
                    e["last_seen"] = iso
                e["xuid"] = xuid
                changed = True
                continue
            md = _JDISC.search(line)
            if md:
                name = md.group(1).strip()
                e = seen.setdefault(name, {})
                if iso > e.get("last_disconnect", ""):
                    e["last_disconnect"] = iso
                changed = True
        if changed:
            save_seen()
    return seen

def _to_lima(iso):
    if not iso:
        return ""
    try:
        return datetime.fromisoformat(iso).astimezone(LIMA_TZ).strftime("%Y-%m-%d %H:%M")
    except (ValueError, OSError):
        return iso

def players_history():
    """Lista de todos los jugadores vistos + última conexión y estado actual."""
    live, _ = live_players()
    online = {p["name"] for p in live}
    with _seen_lock:
        seen = dict(load_seen())
    now_iso = datetime.now(timezone.utc).isoformat()
    rows = []
    for name, e in seen.items():
        last = e.get("last_seen", "")
        rows.append({"name": name, "xuid": e.get("xuid", ""),
                     "first_seen": e.get("first_seen", ""),
                     "last_seen": last, "last_seen_local": _to_lima(last),
                     "last_disconnect": e.get("last_disconnect", ""),
                     "online": name in online})
    for name in online:
        if name not in seen:
            rows.append({"name": name, "xuid": "", "first_seen": "",
                         "last_seen": now_iso, "last_seen_local": _to_lima(now_iso),
                         "last_disconnect": "", "online": True})
    rows.sort(key=lambda r: (r["online"], r.get("last_seen") or ""), reverse=True)
    return rows

# D-39: telemetría de bp_status. [PSTAT] seq|dim|x|y|z|hp|hpmax|food|foodmax|sat|satmax|fx|name
PSTAT_RE = re.compile(
    r"\[PSTAT\]\s+(\d+)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|"
    r"([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|(.*)$")
STATUS_RE = re.compile(r"\[STATUS\]\s+online=(\d+)")
TOTEM_RE = re.compile(r"\[TOTEM\]\s+name=(.+)$")
TS_RE = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")

def _f(v, d=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return d

def live_players():
    """Último lote [PSTAT] del journal -> (jugadores, últimos tótems)."""
    txt = sudo_sh([JOURNALCTL, "-u", MC_SERVICE, "--no-pager", "-o", "cat", "-n", "2500"])
    best_seq = -1
    status_n = None
    cur = {}
    totems = []
    for line in txt.splitlines():
        if "[PSTAT]" in line:
            m = PSTAT_RE.search(line)
            if not m:
                continue
            seq = int(m.group(1))
            if seq > best_seq:
                best_seq, cur = seq, {}
            if seq != best_seq:
                continue
            fx = []
            for part in m.group(12).split(";"):
                bits = part.split("=")
                if len(bits) == 3:
                    fx.append({"id": bits[0], "level": int(_f(bits[1])) + 1,
                               "secs": int(_f(bits[2]) / 20)})
            name = m.group(13).strip()
            cur[name] = {
                "name": name, "dim": m.group(2),
                "x": _f(m.group(3)), "y": _f(m.group(4)), "z": _f(m.group(5)),
                "health": _f(m.group(6)), "health_max": _f(m.group(7)) or 20,
                "food": _f(m.group(8)), "food_max": _f(m.group(9)) or 20,
                "sat": _f(m.group(10)), "sat_max": _f(m.group(11)) or 20,
                "effects": fx,
            }
        elif "[STATUS]" in line:
            ms = STATUS_RE.search(line)
            if ms:
                status_n = int(ms.group(1))
        elif "[TOTEM]" in line:
            m = TOTEM_RE.search(line)
            if m:
                t = TS_RE.match(line)
                totems.append({"name": m.group(1).strip(),
                               "time": t.group(1) if t else ""})
    players = list(cur.values())
    now_ms = time.time() * 1000.0
    # El lote [PSTAT] solo se emite con jugadores: si el latido [STATUS] dice 0
    # o el último muestreo es viejo (>15 s), no hay nadie conectado.
    if status_n == 0 or (best_seq > 0 and now_ms - best_seq > 15000):
        players = []
    return players, totems[-10:]

# --------------------------------------------- recursos y Aternos-like (D-43) -
RES_HIST = collections.deque(maxlen=180)      # ~1 h a 20 s
_res_lock = threading.Lock()
_res_prev = {"cpu_ns": None, "t": None}

def _cpu_ns():
    v = sh([SYSTEMCTL, "show", MC_SERVICE, "--property=CPUUsageNSec", "--value"])
    try:
        return int(v.strip().strip('"'))
    except (ValueError, AttributeError):
        return None

def sample_resources():
    """CPU% (delta de CPUUsageNSec) y RAM (MiB) del proceso BDS."""
    ns = _cpu_ns()
    mem = sh([SYSTEMCTL, "show", MC_SERVICE, "--property=MemoryCurrent", "--value"])
    try:
        ram = int(mem.strip().strip('"')) // (1024 * 1024)
    except (ValueError, AttributeError):
        ram = 0
    now = time.time()
    cpu = None
    if ns is not None and _res_prev["cpu_ns"] is not None:
        dn = ns - _res_prev["cpu_ns"]
        dt = now - _res_prev["t"]
        if dt > 0 and dn >= 0:
            cpu = round(100.0 * dn / (dt * 1e9), 1)
    _res_prev.update(cpu_ns=ns, t=now)
    with _res_lock:
        RES_HIST.append({"t": int(now), "ram": ram, "cpu": cpu})
        try:
            RES_FILE.write_text(json.dumps(list(RES_HIST)), encoding="utf-8")
        except OSError:
            pass

def load_resources():
    if RES_FILE.exists():
        try:
            for p in json.loads(RES_FILE.read_text(encoding="utf-8")):
                RES_HIST.append(p)
        except (ValueError, OSError):
            pass

def _sampler_loop():
    try:
        refresh_seen_from_journal()
    except Exception:  # noqa: BLE001
        pass
    tick = 0
    while True:
        try:
            sample_resources()
        except Exception:  # noqa: BLE001
            pass
        tick += 1
        if tick % 15 == 0:  # ~5 min: refresca el historial de jugadores
            try:
                refresh_seen_from_journal()
            except Exception:  # noqa: BLE001
                pass
        time.sleep(20)

# Claves de server.properties expuestas (las mismas que valida panel_admin.sh).
OPTION_KEYS = ["motd", "server-name", "gamemode", "difficulty", "force-gamemode",
               "max-players", "view-distance", "tick-distance", "player-idle-timeout",
               "allow-list", "default-player-permission-level", "allow-cheats",
               "texturepack-required"]

# Gamerules editables EN VIVO (D-43). Los nodos se aplican por la consola.
GAMERULES_BOOL = ["pvp", "keepinventory", "mobgriefing", "naturalregeneration",
                  "showcoordinates", "sendcommandfeedback", "commandblockoutput",
                  "dodaylightcycle", "doweathercycle", "doimmediaterespawn",
                  "showdeathmessages", "tntexplodes", "mobspawns"]
GAMERULES_NUM = ["randomtickspeed", "spawnradius", "maxcommandchainlength",
                 "functioncommandlimit"]

def _tab_rows(txt, ncol=3):
    rows = []
    for line in txt.splitlines():
        p = line.split("\t")
        if len(p) >= ncol:
            rows.append(p)
    return rows

def server_props():
    txt = sudo_sh([PANEL_ADMIN, "props", "get"], timeout=20)
    props = {}
    for line in txt.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        props[k.strip()] = v.strip()
    return props

def allowlist_entries():
    txt = sudo_sh([PANEL_ADMIN, "allowlist", "list"], timeout=20)
    return [{"name": p[0], "xuid": p[1] if len(p) > 1 else ""}
            for p in _tab_rows(txt, 1)]

def backups_list():
    rows = []
    for p in _tab_rows(sudo_sh([PANEL_ADMIN, "backup", "list"], timeout=20), 3):
        rows.append({"name": p[0],
                     "size": int(p[1]) if p[1].isdigit() else 0,
                     "date": p[2]})
    return rows

def worlds_list():
    rows = []
    for p in _tab_rows(sudo_sh([PANEL_ADMIN, "worlds"], timeout=30), 2):
        rows.append({"name": p[0], "mb": int(p[1]) if p[1].isdigit() else 0})
    return rows

def timers_list():
    labels = {"mc-backup.timer": "Copias de seguridad",
              "mc-checkver.timer": "Comprobación de versión",
              "mc-status.timer": "Latido de estado"}
    out = []
    for unit, label in labels.items():
        def val(prop):
            return sh([SYSTEMCTL, "show", unit, f"--property={prop}", "--value"],
                      timeout=10).strip()
        out.append({"unit": unit, "label": label,
                    "state": val("UnitFileState") or "?",
                    "next": val("NextElapseUSecRealtime") or "—",
                    "last": val("LastTriggerUSec") or ""})
    return out

# ----------------------------------------------------------------- rutas ----
@app.route("/")
def index():
    user = current_user()
    if not user:
        return redirect(url_for("login"))
    state = server_state()
    live, _ = live_players()
    names = [p["name"] for p in live] or last_names()
    return render_template("dashboard.html", user=user, state=state,
                           online=len(live) if live else players_online(),
                           maxp=MC_MAX_PLAYERS,
                           names=names, log=journal_tail(),
                           csrf=session.get("csrf", ""))

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        ip = request.remote_addr or "?"
        if rate_limited(ip):
            AUTH_LOG.write_text(
                (AUTH_LOG.read_text(encoding="utf-8") if AUTH_LOG.exists() else "")
                + f"{time.strftime('%Y-%m-%d %H:%M:%S')} AUTH_FAIL ip={ip} motivo=rate-limit\n",
                encoding="utf-8")
            time.sleep(2)
            flash("Demasiados intentos. Espera 1 minuto.")
            return render_template("login.html", csrf=session.get("csrf", "")), 429
        name = request.form.get("username", "").strip().lower()
        pw = request.form.get("password", "")
        users = load_users()
        ok = False
        if name in users and users[name].get("enabled", True):
            salt, hh = users[name]["salt"], users[name]["hash"]
            _, cand = hash_pw(pw, salt)
            ok = hmac.compare_digest(hh, cand)
        if not ok:
            with AUTH_LOG.open("a", encoding="utf-8") as f:
                f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} AUTH_FAIL ip={ip} user={name}\n")
            flash("Usuario o contraseña incorrectos.")
            return render_template("login.html", csrf=session.get("csrf", "")), 401
        with AUTH_LOG.open("a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} AUTH_OK ip={ip} user={name}\n")
        session.clear()
        session.permanent = True
        session["user"] = name
        session["csrf"] = secrets.token_hex(16)
        audit(name, "login")
        return redirect(request.args.get("next") or url_for("index"))
    if "csrf" not in session:
        session["csrf"] = secrets.token_hex(16)
    return render_template("login.html", csrf=session.get("csrf", ""))

@app.route("/logout", methods=["POST"])
def logout():
    user = current_user()
    if user:
        audit(user["name"], "logout")
    session.clear()
    return redirect(url_for("login"))

@app.route("/api/status")
@login_required()
def api_status(user):
    s = server_state()
    live, _ = live_players()
    s["online"] = len(live) if live else players_online()
    s["names"] = [p["name"] for p in live] or last_names()
    return jsonify(s)

@app.route("/api/players")
@login_required()
def api_players(user):
    """D-39: vida/saturación/efectos/coords por jugador + últimos tótems."""
    live, totems = live_players()
    return jsonify({"online": len(live), "players": live, "totems": totems})

@app.route("/api/players-history")
@login_required()
def api_players_history(user):
    """Todos los jugadores que se conectaron alguna vez + última conexión."""
    rows = players_history()
    return jsonify({"total": len(rows),
                    "online": sum(1 for r in rows if r["online"]),
                    "players": rows})

@app.route("/api/server/<action>", methods=["POST"])
@login_required(role="admin")  # D-30: mods no arrancan/paran el server
def api_server(user, action):
    if action not in ("start", "stop", "restart"):
        abort(400)
    if not csrf_ok():
        abort(403)
    user = current_user()
    # D-33: control por restart_server.sh = verificación real (systemd + puerto
    # TCP + "Server started"). Bloquea hasta el resultado; START/STOP/RESTART.
    out = sudo_sh(["/opt/mcserver/modules/restart_server.sh", action], timeout=170)
    ok = "[OK]" in out and "[FAIL]" not in out
    detail = out.replace("\n", " | ")[-400:] if out else "sin salida (¿sudo ok?)"
    audit(user["name"], f"server.{action}", detail)
    time.sleep(2)
    st = server_state()
    return jsonify({"ok": ok, "status": st["status"], "detail": detail or "OK"})

@app.route("/api/cmd/<kind>", methods=["POST"])
@login_required()  # D-30/D-33 fase 3: kick/ban también para mods; say solo admin
def api_cmd(user, kind):
    if not csrf_ok():
        abort(403)
    name = (request.form.get("name") or "").strip()[:24]
    if kind == "say":
        if RANK.get(user["role"], 0) < RANK["admin"]:
            abort(403)
        text = (request.form.get("text") or "").strip()[:140]
        if "\n" in text:
            abort(400)
        cmd = "say " + text
    elif kind in ("kick", "ban", "unban"):
        if not re.fullmatch(r"[A-Za-zÀ-ÿ0-9_ §?.]+", name or ""):
            abort(400)
        cmd = kind + " " + name
    else:
        abort(400)
    r = sh(["/bin/bash", "/opt/mcserver/modules/consola.sh", cmd], timeout=25)
    audit(user["name"], f"cmd.{kind}", r[:140])
    return jsonify({"ok": "Enviado" in r and "ERROR" not in r, "out": r[:200]})

@app.route("/api/security", methods=["GET"])
@login_required(role="root")
def api_security(user):
    users = [{"name": n, "role": v["role"], "enabled": v.get("enabled", True)}
             for n, v in sorted(load_users().items())]
    ops_txt = sudo_sh([GAME_ADMIN, "list"], timeout=20)
    ops = []
    for line in ops_txt.splitlines():
        p = line.split("\t")
        if len(p) >= 2:
            ops.append({"name": p[0], "level": p[1], "xuid": p[2] if len(p) > 2 else ""})
    return jsonify({"users": users, "ops": ops})


@app.route("/api/security/user/<name>", methods=["POST"])
@login_required(role="root")
def api_security_user(user, name):
    if not csrf_ok():
        abort(403)
    name = name.strip().lower()
    users = load_users()
    if name == user["name"]:
        return jsonify({"ok": False, "detail": "no puedes modificarte a ti mismo"}), 400
    if name not in users:
        return jsonify({"ok": False, "detail": "usuario inexistente"}), 404
    act = request.form.get("action", "")
    if act == "role":
        role = request.form.get("role", "")
        if role not in RANK:
            return jsonify({"ok": False, "detail": "rol inválido"}), 400
        users[name]["role"] = role
        audit(user["name"], "sec.role", f"user={name} rol={role}")
    elif act == "revoke":
        users[name]["enabled"] = False
        audit(user["name"], "sec.revoke", f"user={name}")
    elif act == "enable":
        users[name]["enabled"] = True
        audit(user["name"], "sec.enable", f"user={name}")
    elif act == "pass":
        pw = request.form.get("password", "")
        if len(pw) < 8:
            return jsonify({"ok": False, "detail": "mínimo 8 caracteres"}), 400
        salt, h = hash_pw(pw)
        users[name].update({"salt": salt, "hash": h})
        audit(user["name"], "sec.pass", f"user={name}")
    else:
        abort(400)
    save_users(users)
    return jsonify({"ok": True})


@app.route("/api/security/game/<action>", methods=["POST"])
@login_required(role="root")
def api_security_game(user, action):
    if not csrf_ok():
        abort(403)
    if action not in ("op", "deop", "survival", "deop-all-except"):
        abort(400)
    name = (request.form.get("name") or "").strip()
    if action == "deop-all-except":
        name = FOUNDER  # nunca deja sin OP al fundador (D-34)
    if not re.fullmatch(r"[A-Za-z0-9_]{1,16}", name or ""):
        return jsonify({"ok": False, "detail": "gamertag inválido"}), 400
    args = [GAME_ADMIN, action, name]
    if action == "op":
        xuid = (request.form.get("xuid") or "").strip()
        if xuid:
            if not xuid.isdigit():
                return jsonify({"ok": False, "detail": "xuid inválido"}), 400
            args.append(xuid)
    out = sudo_sh(args, timeout=25)
    ok = "[OK]" in out and "[FAIL]" not in out
    audit(user["name"], f"sec.game.{action}", f"name={name} {out[:120]}")
    return jsonify({"ok": ok, "detail": out.replace("\n", " | ")[-300:] or "sin salida"})


@app.route("/api/console", methods=["POST"])
@login_required(role="root")
def api_console(user):
    """Consola del BDS solo-root (D-35): envía un comando al FIFO del server."""
    if not csrf_ok():
        abort(403)
    cmd = (request.form.get("cmd") or "").strip()
    if not cmd or "\n" in cmd or len(cmd) > 200:
        return jsonify({"ok": False, "detail": "comando vacío o inválido"}), 400
    r = sh(["/bin/bash", f"{MC_HOME}/modules/consola.sh", cmd], timeout=25)
    ok = "Enviado" in r and "ERROR" not in r
    audit(user["name"], "console", cmd[:160])
    return jsonify({"ok": ok, "detail": r.replace("\n", " | ")[:200] or "sin salida"})


@app.route("/api/update/<kind>", methods=["POST"])
@login_required(role="admin")
def api_update(user, kind):
    if not csrf_ok():
        abort(403)
    user = current_user()
    if kind == "stage":
        audit(user["name"], "update.stage")
        # asíncrono: el staging tarda (descarga + smoke test). Corre como mcpanel
        # (staging es suyo); no necesita sudo.
        env = {**os.environ, "MC_CONF": C.get("MC_CONF", "/opt/mcserver/config/mc.conf")}
        subprocess.Popen(["/opt/mcserver/modules/check_version.sh", "--stage"],
                         env=env,
                         stdout=open(LOG_DIR / "stage.log", "a"),
                         stderr=subprocess.STDOUT)
        return jsonify({"ok": True, "msg": "Staging lanzado (mira logs/stage.log)"})
    if kind == "gate":
        out = sudo_sh(["/opt/mcserver/modules/update.sh", "--prod", "--yes"], timeout=300)
        audit(user["name"], "update.gate", out[-500:])
        ok = "PRODUCCIÓN OK" in out
        return jsonify({"ok": ok, "out": out[-2000:]})
    abort(400)

@app.route("/api/resources")
@login_required()
def api_resources(user):
    """D-43: histórico RAM/CPU para la gráfica (últimas ~3 h)."""
    with _res_lock:
        hist = list(RES_HIST)
    return jsonify({"points": hist[-180:]})


@app.route("/api/timers")
@login_required()
def api_timers(user):
    """D-43: tareas programadas (mc-backup/checkver/status)."""
    return jsonify({"timers": timers_list()})


@app.route("/api/allowlist")
@login_required(role="admin")
def api_allowlist(user):
    props = server_props()
    return jsonify({"entries": allowlist_entries(),
                    "enabled": props.get("allow-list", "false") == "true"})


@app.route("/api/allowlist/<action>", methods=["POST"])
@login_required(role="admin")
def api_allowlist_act(user, action):
    if not csrf_ok():
        abort(403)
    if action not in ("add", "remove"):
        abort(400)
    name = (request.form.get("name") or "").strip()
    if not re.fullmatch(r"[A-Za-z0-9_]{1,16}", name or ""):
        return jsonify({"ok": False, "detail": "gamertag inválido"}), 400
    out = sudo_sh([PANEL_ADMIN, "allowlist", action, name], timeout=20)
    ok = "[OK]" in out and "[FAIL]" not in out
    audit(user["name"], f"allowlist.{action}", name)
    return jsonify({"ok": ok, "detail": out.replace("\n", " | ")[-200:] or "sin salida"})


@app.route("/api/options")
@login_required(role="admin")
def api_options(user):
    props = server_props()
    return jsonify({"options": {k: props.get(k, "") for k in OPTION_KEYS},
                    "all": props})


@app.route("/api/options", methods=["POST"])
@login_required(role="admin")
def api_options_set(user):
    if not csrf_ok():
        abort(403)
    key = (request.form.get("key") or "").strip()
    val = (request.form.get("value") or "").strip()
    if key not in OPTION_KEYS:
        return jsonify({"ok": False, "detail": "clave no editable"}), 400
    if not val or len(val) > 120 or "\n" in val or "\r" in val:
        return jsonify({"ok": False, "detail": "valor inválido"}), 400
    out = sudo_sh([PANEL_ADMIN, "props", "set", key, val], timeout=20)
    ok = "[OK]" in out and "[FAIL]" not in out
    audit(user["name"], "options.set", f"{key}={val}")
    return jsonify({"ok": ok, "detail": out.replace("\n", " | ")[-200:] or "sin salida"})


@app.route("/api/backups")
@login_required(role="admin")
def api_backups(user):
    return jsonify({"backups": backups_list()})


@app.route("/api/backups/create", methods=["POST"])
@login_required(role="admin")
def api_backups_create(user):
    if not csrf_ok():
        abort(403)
    out = sudo_sh([PANEL_ADMIN, "backup", "create"], timeout=200)
    ok = "[OK]" in out and "[FAIL]" not in out
    audit(user["name"], "backup.create", out.replace("\n", " | ")[-200:])
    return jsonify({"ok": ok, "detail": out.replace("\n", " | ")[-300:] or "sin salida"})


@app.route("/api/worlds")
@login_required(role="admin")
def api_worlds(user):
    return jsonify({"worlds": worlds_list(),
                    "active": C.get("MC_LEVEL_NAME", "world")})


@app.route("/api/gamerule", methods=["POST"])
@login_required(role="admin")
def api_gamerule(user):
    if not csrf_ok():
        abort(403)
    name = (request.form.get("name") or "").strip().lower()
    value = (request.form.get("value") or "").strip().lower()
    if name in GAMERULES_BOOL:
        if value not in ("true", "false"):
            return jsonify({"ok": False, "detail": "usa true/false"}), 400
    elif name in GAMERULES_NUM:
        if not re.fullmatch(r"\d{1,6}", value or ""):
            return jsonify({"ok": False, "detail": "valor numérico inválido"}), 400
    else:
        return jsonify({"ok": False, "detail": "gamerule no permitida"}), 400
    cmd = f"gamerule {name} {value}"
    r = sh(["/bin/bash", f"{MC_HOME}/modules/consola.sh", cmd], timeout=25)
    ok = "Enviado" in r and "ERROR" not in r
    audit(user["name"], "gamerule", cmd)
    return jsonify({"ok": ok, "detail": r.replace("\n", " | ")[:200] or "sin salida"})


@app.route("/manifest.json")
def manifest():
    return app.send_static_file("manifest.json")

@app.route("/sw.js")
def sw():
    return app.send_static_file("sw.js")

@app.route("/icon.svg")
def icon():
    return app.send_static_file("icon.svg")

# --------------------------------------------------------------- arranque ---
if __name__ == "__main__":
    load_users()
    load_resources()
    threading.Thread(target=_sampler_loop, daemon=True).start()
    serve(app, host=BIND, port=PORT, threads=8)
