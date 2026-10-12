#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# dns_cloudflare.py — añade A records al zone DNS en Cloudflare (sólo añade,
# nunca borra ni toca registros existentes). Idempotente.
#
#   export CLOUDFLARE_API_TOKEN="..."   (token con permiso Zone:DNS:Edit)
#   python dns_cloudflare.py --zone example.com --ip 203.0.113.10 \
#          --names panel mc
#
# Los nombres se crean como A -> <ip>, TTL auto (1), sin proxy (grey cloud)
# para que Caddy emita el certificado Let's Encrypt directo.
# Si el registro ya existe con otro valor, NO lo toca: sólo avisa.
# =============================================================================
import json
import sys
import urllib.parse
import urllib.request

API = "https://api.cloudflare.com/client/v4"


def cf(method, path, token, payload=None):
    url = f"{API}{path}"
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode("utf-8"))


def main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--zone", required=True)
    ap.add_argument("--ip", required=True)
    ap.add_argument("--names", nargs="+", required=True)
    ap.add_argument("--proxied", action="store_true",
                    help="crear con proxy Cloudflare activo (por defecto off)")
    a = ap.parse_args(argv)

    import os
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
    if not token:
        print("FALTA: export CLOUDFLARE_API_TOKEN=... (permiso Zone DNS:Edit)")
        return 2

    z = cf("GET", f"/zones?name={urllib.parse.quote(a.zone)}", token)
    zones = (z.get("result") or [])
    if not zones:
        print("No encontré el zone:", a.zone, "| errores:", z.get("errors"))
        return 3
    zid = zones[0]["id"]
    print("zone:", a.zone, zid)

    for n in a.names:
        fqdn = n if "." in n and n != a.zone else f"{n}.{a.zone}"
        fqdn = fqdn if n != "@" else a.zone
        r = cf("GET", f"/zones/{zid}/dns_records?type=A&name={urllib.parse.quote(fqdn)}", token)
        recs = r.get("result") or []
        if recs:
            cur = recs[0].get("content", "")
            if cur == a.ip:
                print(f"OK ya existe: {fqdn} -> {cur}")
            else:
                print(f"AVISO {fqdn} ya existe apuntando a {cur} (NO lo toco)")
            continue
        body = {"type": "A", "name": fqdn, "content": a.ip,
                "ttl": 1, "proxied": bool(a.proxied)}
        c = cf("POST", f"/zones/{zid}/dns_records", token, body)
        if c.get("success"):
            print(f"CREADO: {fqdn} -> {a.ip}")
        else:
            print(f"ERROR creando {fqdn}:", c.get("errors"))
            return 4
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))