#!/usr/bin/env python3
"""Local-only Synapse user administration; tokens and passwords never use argv."""
import getpass
import json
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
config = ROOT / "data/synapse/homeserver.yaml"
server_name = next((line.split('"', 2)[1] for line in config.read_text().splitlines() if line.startswith('server_name: "')), None)
if not server_name:
    raise SystemExit("Cannot determine MATRIX_SERVER_NAME; initialize Synapse first.")


def docker(*args, input_text=None):
    result = subprocess.run(
        ["docker", "compose", "exec", "-T", "synapse", *args], cwd=ROOT,
        input=input_text, text=True, capture_output=True,
    )
    if result.returncode:
        raise SystemExit(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def request(token, endpoint, method, body=None):
    remote = r'''import sys, urllib.request
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
    return docker("python3", "-c", remote, "http://127.0.0.1:8008" + endpoint, method, input_text=token + "\n" + payload + "\n")


def confirm(expected):
    if input(f"Type {expected} to confirm: ") != expected:
        raise SystemExit("Cancelled.")


def user_id(localpart):
    if not localpart or any(character in localpart for character in "@:/"):
        raise SystemExit("Provide a localpart, not a full Matrix ID.")
    return "@" + localpart + ":" + server_name


def main():
    args = sys.argv[1:]
    actions = {"create", "admin", "password", "deactivate", "list", "lock", "unlock", "suspend", "unsuspend", "devices", "revoke-device", "revoke-all"}
    if not args or args[0] not in actions:
        raise SystemExit("Usage: users.sh {create|admin|password|deactivate|list|lock|unlock|suspend|unsuspend|devices|revoke-device|revoke-all} [localpart] [device_id]")
    action = args[0]

    if action in {"create", "admin"}:
        if len(args) != 2:
            raise SystemExit("Provide one localpart.")
        command = ["docker", "compose", "exec", "synapse", "register_new_matrix_user", "-c", "/data/homeserver.yaml", "-u", args[1]]
        command.append("-a" if action == "admin" else "--no-admin")
        subprocess.run(command + ["http://localhost:8008"], cwd=ROOT, check=True)
        raise SystemExit("Answer the password prompts.")

    if action == "list":
        if len(args) != 1:
            raise SystemExit("list takes no user argument.")
        token = getpass.getpass("Server-admin access token (not echoed): ")
        print(request(token, "/_synapse/admin/v3/users?limit=100", "GET"))
        return

    if action == "revoke-device":
        if len(args) != 3 or not args[2]:
            raise SystemExit("Provide a localpart and device ID.")
    elif len(args) != 2:
        raise SystemExit("Provide one localpart.")

    user = user_id(args[1])
    encoded_user = quote(user, safe="")
    if action == "password":
        password = getpass.getpass("New password: ")
        if password != getpass.getpass("Confirm password: "):
            raise SystemExit("Passwords differ.")
        endpoint, method, body = f"/_synapse/admin/v2/users/{encoded_user}", "PUT", {"password": password, "logout_devices": True}
    elif action == "deactivate":
        confirm("DEACTIVATE " + user)
        endpoint, method, body = f"/_synapse/admin/v1/deactivate/{encoded_user}", "POST", {"erase": False}
    elif action in {"lock", "unlock"}:
        confirm(("LOCK " if action == "lock" else "UNLOCK ") + user)
        endpoint, method, body = f"/_synapse/admin/v2/users/{encoded_user}", "PUT", {"locked": action == "lock"}
    elif action in {"suspend", "unsuspend"}:
        confirm(("SUSPEND " if action == "suspend" else "UNSUSPEND ") + user)
        endpoint, method, body = f"/_synapse/admin/v1/suspend/{encoded_user}", "PUT", {"suspend": action == "suspend"}
    elif action == "devices":
        endpoint, method, body = f"/_synapse/admin/v2/users/{encoded_user}/devices", "GET", None
    elif action == "revoke-device":
        confirm("REVOKE " + user + " " + args[2])
        endpoint, method, body = f"/_synapse/admin/v2/users/{encoded_user}/devices/{quote(args[2], safe='')}", "DELETE", None
    else:
        endpoint, method, body = f"/_synapse/admin/v2/users/{encoded_user}/devices", "GET", None

    token = getpass.getpass("Server-admin access token (not echoed): ")
    if action == "revoke-all":
        devices = json.loads(request(token, endpoint, method)).get("devices", [])
        device_ids = [device["device_id"] for device in devices]
        if not device_ids:
            print("No devices to revoke.")
            return
        confirm("REVOKE ALL " + user)
        print(request(token, f"/_synapse/admin/v2/users/{encoded_user}/delete_devices", "POST", {"devices": device_ids}))
        return
    print(request(token, endpoint, method, body))


if __name__ == "__main__":
    main()
