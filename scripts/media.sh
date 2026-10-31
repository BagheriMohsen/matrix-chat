#!/usr/bin/env python3
"""Inspect and manually delete local media through Synapse's Admin API."""

import datetime
import getpass
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote


ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "data/synapse/homeserver.yaml"
match = re.search(r'^server_name: "([^"]+)"$', CONFIG.read_text(), re.MULTILINE) if CONFIG.is_file() else None
if not match:
    raise SystemExit("Cannot determine MATRIX_SERVER_NAME; initialize Synapse first.")
SERVER = match.group(1)
REMOTE = r'''import json, sys, urllib.error, urllib.request
token = sys.stdin.readline().rstrip("\n")
method, path = sys.argv[1:]
request = urllib.request.Request("http://127.0.0.1:8008" + path,
    data=b"{}" if method == "POST" else None, method=method)
request.add_header("Authorization", "Bearer " + token)
request.add_header("Content-Type", "application/json")
try:
    with urllib.request.urlopen(request, timeout=60) as response:
        print(response.read().decode())
except urllib.error.HTTPError as error:
    raise SystemExit(f"HTTP {error.code}: {error.read().decode()}")
'''


def docker(*args, input_text=None):
    result = subprocess.run(
        ["docker", "compose", "exec", "-T", "synapse", *args],
        cwd=ROOT,
        input=input_text,
        text=True,
        capture_output=True,
    )
    if result.returncode:
        raise SystemExit(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def usage():
    print("Media-store allocated KiB:", docker("du", "-sk", "/data/media_store").split()[0])
    print("Host filesystem (KiB blocks):", flush=True)
    subprocess.run(["df", "-Pk", str(ROOT / "data/synapse")], check=True)


def request(token, method, path):
    return json.loads(docker("python3", "-c", REMOTE, method, path, input_text=token + "\n"))


def media_id(mxc):
    match = re.fullmatch(r"mxc://" + re.escape(SERVER) + r"/([A-Za-z0-9_-]+)", mxc)
    if not match:
        raise SystemExit(f"Provide one local mxc://{SERVER}/<media_id> URI.")
    return match.group(1)


def confirm(expected):
    if input(f"Type {expected} to confirm: ") != expected:
        raise SystemExit("Cancelled.")


def main():
    args = sys.argv[1:]
    if args == ["usage"]:
        usage()
        return
    if len(args) not in (2, 3) or args[0] not in {"list-user", "info", "delete", "purge-before"}:
        raise SystemExit(f"Usage: media.sh usage | list-user @user:{SERVER} | info MXC | delete MXC [--execute] | purge-before YYYY-MM-DD [--execute]")
    action, target = args[:2]
    execute = len(args) == 3 and args[2] == "--execute"
    if len(args) == 3 and not execute:
        raise SystemExit("Only --execute is accepted as a third argument.")
    if execute and action not in {"delete", "purge-before"}:
        raise SystemExit("--execute is only valid for delete and purge-before.")

    if action == "list-user":
        if not re.fullmatch(r"@[^:/]+:" + re.escape(SERVER), target):
            raise SystemExit("Provide a local Matrix user ID.")
        path = "/_synapse/admin/v1/users/" + quote(target, safe="") + "/media?limit=100"
    elif action in {"info", "delete"}:
        path = "/_synapse/admin/v1/media/" + SERVER + "/" + media_id(target)
    else:
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", target):
            raise SystemExit("Use a YYYY-MM-DD UTC cutoff date.")
        try:
            cutoff = datetime.date.fromisoformat(target)
        except ValueError:
            raise SystemExit("Use a YYYY-MM-DD UTC cutoff date.") from None
        if cutoff > datetime.datetime.now(datetime.timezone.utc).date() - datetime.timedelta(days=90):
            raise SystemExit("Cutoff must be at least 90 days old.")
        before_ts = int(datetime.datetime.combine(cutoff, datetime.time(), datetime.timezone.utc).timestamp() * 1000)
        path = f"/_synapse/admin/v1/media/delete?before_ts={before_ts}&keep_profiles=true"
        print(f"Local media last accessed before {target} UTC may be deleted; profiles are kept.")
        print("Synapse has no exact dry-run for this purge. Old media may still be referenced, including encrypted attachments.")
        if not execute:
            return

    token = getpass.getpass("Server-admin access token (not echoed): ")
    if action == "list-user":
        print(json.dumps(request(token, "GET", path), indent=2))
    elif action == "info":
        print(json.dumps(request(token, "GET", path), indent=2))
    elif action == "delete":
        print(json.dumps(request(token, "GET", path), indent=2))
        if not execute:
            print("Inspection only. Re-run with --execute to delete this exact media item.")
            return
        confirm("DELETE " + target)
        print(json.dumps(request(token, "DELETE", path), indent=2))
        usage()
    else:
        confirm("PURGE " + target)
        print(json.dumps(request(token, "POST", path), indent=2))
        usage()


if __name__ == "__main__":
    main()
