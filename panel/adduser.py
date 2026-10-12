#!/usr/bin/env python3
"""Crear/actualizar usuario del panel (D-30/D-34).

Uso (en el VPS, carpeta del panel):
  ./venv/bin/python adduser.py NOMBRE ROL          # pide contraseña por stdin
  ./venv/bin/python adduser.py NOMBRE ROL CONTRA   # para uso no interactivo

Roles: root | admin | mod   (root = solo el fundador; gestiona usuarios y OP)
"""
import hashlib
import json
import secrets
import sys
from pathlib import Path

USERS_FILE = Path(__file__).resolve().parent / "users.json"
ITER = 200_000


def hash_pw(pw, salt=None):
    salt = salt or secrets.token_hex(16)
    h = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), ITER).hex()
    return salt, h


def main():
    if len(sys.argv) not in (3, 4) or sys.argv[2] not in ("root", "admin", "mod"):
        print(__doc__)
        sys.exit(1)
    name = sys.argv[1].strip().lower()
    role = sys.argv[2]
    pw = sys.argv[3] if len(sys.argv) == 4 else input("Contraseña: ")
    if len(pw) < 8:
        print("ERROR: la contraseña debe tener >= 8 caracteres")
        sys.exit(1)

    users = json.loads(USERS_FILE.read_text(encoding="utf-8")) if USERS_FILE.exists() else {}
    salt, h = hash_pw(pw)
    prev = users.get(name, {})
    users[name] = {"salt": salt, "hash": h, "role": role,
                   "enabled": prev.get("enabled", True)}
    USERS_FILE.write_text(json.dumps(users, indent=2), encoding="utf-8")
    USERS_FILE.chmod(0o600)
    print(f"OK: usuario '{name}' rol={role}")


if __name__ == "__main__":
    main()
