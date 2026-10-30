#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f .env ]] || { echo "Copy .env.example to .env and set a random POSTGRES_PASSWORD." >&2; exit 1; }
[[ ! -e data/synapse/homeserver.yaml && ! -e data/postgres/PG_VERSION ]] || { echo "Existing deployment data found; refusing to overwrite it." >&2; exit 1; }
set -a
source .env
set +a
umask 077
mkdir -p data/synapse data/postgres data/element data/acme secrets/tls

# Generate Synapse's signing key and logging template with the official image.
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD/data/synapse:/data" \
  -e SYNAPSE_SERVER_NAME=ct.koten.ir -e SYNAPSE_REPORT_STATS=no \
  matrixdotorg/synapse:v1.161.0 generate

python3 - <<'PY'
from pathlib import Path
import os
import secrets
template = Path("config/synapse/homeserver.yaml.template").read_text()
for key in ("POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD"):
    value = os.environ[key]
    if any(c in value for c in "\n\r\""):
        raise SystemExit(f"{key} must not contain a quote or newline")
    template = template.replace(f"__{key}__", value)
Path("data/synapse/homeserver.yaml").write_text(template)
Path("data/synapse/registration_shared_secret").write_text(secrets.token_hex(32))
PY
chmod 700 data data/synapse data/postgres secrets secrets/tls
chmod 755 data/element
find data/synapse -maxdepth 1 -type f -exec chmod 600 {} +
docker run --rm -v "$PWD/data/synapse:/data" --entrypoint chown \
  matrixdotorg/synapse:v1.161.0 -R 991:991 /data
echo "Initialization complete. Put a CA-issued fullchain.pem and privkey.pem in secrets/tls/ (mode 600), then run scripts/offline-export.sh while online and docker compose up -d."
