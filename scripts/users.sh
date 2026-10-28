#!/usr/bin/env python3
"""Local-only user administration. Tokens and passwords travel via stdin, never argv."""
import getpass, json, subprocess, sys

if len(sys.argv) < 2 or sys.argv[1] not in {"create", "admin", "password", "deactivate", "list"}:
    raise SystemExit("Usage: users.sh {create|admin|password|deactivate|list} [localpart]")
action = sys.argv[1]
if action in {"create", "admin"}:
    if len(sys.argv) != 3: raise SystemExit("Provide one localpart.")
    subprocess.run(["docker", "compose", "exec", "synapse", "register_new_matrix_user", "-c", "/data/homeserver.yaml", "http://localhost:8008"], check=True)
    raise SystemExit("Answer the interactive prompts; choose admin only for the initial admin.")
if action == "list":
    endpoint, method, body = "/_synapse/admin/v2/users?limit=100", "GET", None
else:
    if len(sys.argv) != 3: raise SystemExit("Provide one localpart.")
    user = "@" + sys.argv[2] + ":ct.koten.ir"
    if action == "password":
        password = getpass.getpass("New password: ")
        if password != getpass.getpass("Confirm password: "): raise SystemExit("Passwords differ.")
        endpoint, method, body = f"/_synapse/admin/v2/users/{user}", "PUT", {"password": password, "logout_devices": True}
    else:
        if input(f"Deactivate {user}? Type DEACTIVATE: ") != "DEACTIVATE": raise SystemExit("Cancelled.")
        endpoint, method, body = f"/_synapse/admin/v1/deactivate/{user}", "POST", {"erase": False}
token = getpass.getpass("Server-admin access token (not echoed): ")
remote = r'''import json, sys, urllib.request
token = sys.stdin.readline().rstrip("\n")
body = sys.stdin.readline()
req = urllib.request.Request(sys.argv[1], data=(body.encode() if body else None), method=sys.argv[2])
req.add_header("Authorization", "Bearer " + token)
req.add_header("Content-Type", "application/json")
try:
 print(urllib.request.urlopen(req, timeout=20).read().decode())
except Exception as exc:
 raise SystemExit(exc)
'''
payload = "" if body is None else json.dumps(body, separators=(",", ":"))
subprocess.run(["docker", "compose", "exec", "-T", "synapse", "python3", "-c", remote, "http://127.0.0.1:8008" + endpoint, method], input=token + "\n" + payload + "\n", text=True, check=True)
