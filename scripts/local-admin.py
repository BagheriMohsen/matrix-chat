#!/usr/bin/env python3
"""Create or verify the local administrator without exposing its password in argv."""
import os
from pathlib import Path
import secrets
import subprocess


ROOT = Path(__file__).resolve().parent.parent
PASSWORD_FILE = ROOT / "secrets/local-admin-password"
REMOTE = r'''
import hashlib, hmac, json, sys, urllib.error, urllib.request
from pathlib import Path

base = "http://127.0.0.1:8008"
password = sys.stdin.read().strip()
user = "admin"

def request(path, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.load(response)

def login():
    return request("/_matrix/client/v3/login", {
        "type": "m.login.password",
        "identifier": {"type": "m.id.user", "user": user},
        "password": password,
    })["access_token"]

try:
    token = login()
except urllib.error.HTTPError as error:
    if error.code != 403:
        raise
    nonce = request("/_synapse/admin/v1/register")["nonce"]
    message = b"\0".join(part.encode() for part in (nonce, user, password, "admin"))
    mac = hmac.new(Path("/data/registration_shared_secret").read_text().strip().encode(), message, hashlib.sha1).hexdigest()
    request("/_synapse/admin/v1/register", {
        "nonce": nonce, "username": user, "password": password,
        "admin": True, "mac": mac,
    })
    token = login()

result = request("/_synapse/admin/v2/users?limit=1", token=token)
if "users" not in result:
    raise SystemExit("Administrator API verification failed")
print("Local administrator login and Admin API access verified.")
'''


def main():
    if not (ROOT / ".env").is_file():
        raise SystemExit("Run bash scripts/local-init.sh first.")
    PASSWORD_FILE.parent.mkdir(mode=0o700, exist_ok=True)
    if PASSWORD_FILE.exists():
        password = PASSWORD_FILE.read_text().strip()
    else:
        password = secrets.token_urlsafe(36)
        with os.fdopen(os.open(PASSWORD_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as file:
            file.write(password + "\n")
    subprocess.run(
        ["docker", "compose", "-p", "matrix_local", "-f", "compose.local.yaml",
         "exec", "-T", "synapse", "python3", "-c", REMOTE],
        cwd=ROOT, input=password, text=True, check=True,
    )


if __name__ == "__main__":
    main()
