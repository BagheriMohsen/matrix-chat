#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  [[ ! -d data/postgres && ! -d data/synapse ]] || {
    echo "Existing data has no .env; restore its original credentials before continuing." >&2
    exit 1
  }
  umask 077
  python3 - <<'PY'
from pathlib import Path
import os
import secrets

template = Path(".env.example").read_text()
marker = "replace-with-a-long-random-password"
if template.count(marker) != 1:
    raise SystemExit("Unexpected .env.example password placeholder")
content = template.replace(marker, secrets.token_urlsafe(48))
with os.fdopen(os.open(".env", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as file:
    file.write(content)
PY
fi
[[ -f .env ]] || { echo ".env is missing." >&2; exit 1; }
python3 scripts/render-config.py
if grep -q '^POSTGRES_PASSWORD=replace-with-a-long-random-password$' .env; then
  echo "Replace the example database password before continuing." >&2
  exit 1
fi
PUBLIC_BASE_URL=$(python3 scripts/render-config.py --get PUBLIC_BASE_URL)
LOCAL_HOST=$(python3 scripts/render-config.py --get LOCAL_HOST)
LOCAL_ELEMENT_PORT=$(python3 scripts/render-config.py --get LOCAL_ELEMENT_PORT)

scripts/init.sh

# The local config changes only the client-facing URL; the Matrix identity and
# signing key stay in the existing production configuration and data directory.
docker run --rm --pull never -i -v "$PWD/data/synapse:/data" \
  -e PUBLIC_BASE_URL="$PUBLIC_BASE_URL" -e LOCAL_HOST="$LOCAL_HOST" -e LOCAL_ELEMENT_PORT="$LOCAL_ELEMENT_PORT" \
  --entrypoint python3 matrixdotorg/synapse:v1.161.0 - <<'PY'
from pathlib import Path
import os

original = Path("/data/homeserver.yaml").read_text()
old = f'public_baseurl: "{os.environ["PUBLIC_BASE_URL"].rstrip("/")}/"'
if original.count(old) != 1:
    raise SystemExit("Expected production public_baseurl was not found; preserving existing configuration")
local = original.replace(old, f'public_baseurl: "http://{os.environ["LOCAL_HOST"]}:{os.environ["LOCAL_ELEMENT_PORT"]}/"', 1)
target = Path("/data/homeserver.local.yaml")

def without_managed_blocks(content):
    import re
    for name in ("retention", "room permissions", "TURN"):
        content = re.sub(
            rf"(?ms)^# BEGIN managed {name} configuration\n.*?^# END managed {name} configuration\n?",
            "",
            content,
        )
    content = re.sub(r"(?m)^block_non_admin_invites: (?:true|false)\n?", "", content)
    return "\n".join(line for line in content.splitlines() if line.strip()) + "\n"

if target.exists():
    if without_managed_blocks(target.read_text()) != without_managed_blocks(local):
        raise SystemExit("Existing local Synapse config differs; refusing to overwrite it")
    target.write_text(local)
    os.chmod(target, 0o600)
    os.chown(target, 991, 991)
else:
    with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as file:
        file.write(local)
    os.chown(target, 991, 991)
PY

python3 scripts/render-config.py

mkdir -p data/element
if [[ ! -f data/element/index.html ]]; then
  [[ -f offline-bundle/static/element/index.html ]] || {
    echo "Element assets missing; run the verified offline export before local setup." >&2
    exit 1
  }
  cp -a offline-bundle/static/element/. data/element/
fi
chmod 755 data/element
echo "Local assets and configuration are ready. Existing data and credentials were preserved."
