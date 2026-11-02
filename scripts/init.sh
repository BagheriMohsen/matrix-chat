#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f .env ]] || { echo "Copy .env.example to .env and set a random POSTGRES_PASSWORD." >&2; exit 1; }
# Validate all user-supplied values before Docker receives them and render the
# non-secret Nginx/Element/Admin configuration files.
python3 scripts/render-config.py
MATRIX_SERVER_NAME=$(python3 scripts/render-config.py --get MATRIX_SERVER_NAME)

set_synapse_top_level_permissions() {
  local host_uid
  host_uid=$(id -u)
  docker run --rm --user 0:0 -e HOST_UID="$host_uid" -v "$PWD/data/synapse:/data" --entrypoint sh \
    matrixdotorg/synapse:v1.161.0 -ec '
      chown "$HOST_UID":991 /data
      chmod 770 /data
      find /data -maxdepth 1 -type f -exec chown "$HOST_UID":991 {} +
      find /data -maxdepth 1 -type f -exec chmod 640 {} +
    '
}

if [[ -d data/synapse ]]; then
  if docker run --rm --pull never -v "$PWD/data/synapse:/data:ro" --entrypoint sh \
    matrixdotorg/synapse:v1.161.0 -c 'test -f /data/homeserver.yaml && test -f /data/registration_shared_secret && find /data -maxdepth 1 -name "*.signing.key" -type f -print -quit | grep -q .'; then
    current_server=$(docker run --rm --pull never -v "$PWD/data/synapse:/data:ro" --entrypoint sed \
      matrixdotorg/synapse:v1.161.0 -nE 's/^server_name: "([^"]+)"$/\1/p' /data/homeserver.yaml)
    [[ $current_server == "$MATRIX_SERVER_NAME" ]] || { echo "MATRIX_SERVER_NAME cannot change after initialization." >&2; exit 1; }
    docker run --rm --user 0:0 -v "$PWD:/project" -w /project --entrypoint python3 \
      matrixdotorg/synapse:v1.161.0 scripts/render-config.py --turn-synapse
    set_synapse_top_level_permissions
    echo "Synapse is already initialized; preserving its configuration and keys."
    exit 0
  fi
  echo "Incomplete Synapse data found; refusing to overwrite it." >&2
  exit 1
fi
[[ ! -d data/postgres ]] || { echo "Existing database data found; refusing to overwrite it." >&2; exit 1; }
umask 077
mkdir -p data/synapse data/postgres data/element data/acme secrets/tls secrets/push-tls

# Generate Synapse's signing key and logging template with the official image.
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD/data/synapse:/data" \
  -e SYNAPSE_SERVER_NAME="$MATRIX_SERVER_NAME" -e SYNAPSE_REPORT_STATS=no \
  matrixdotorg/synapse:v1.161.0 generate

python3 scripts/render-config.py --homeserver
python3 - <<'PY'
from pathlib import Path
import secrets
Path("data/synapse/registration_shared_secret").write_text(secrets.token_hex(32))
PY
chmod 700 data data/synapse data/postgres secrets secrets/tls secrets/push-tls
chmod 755 data/element
set_synapse_top_level_permissions
echo "Initialization complete. Put CA-issued fullchain.pem and privkey.pem (mode 600) in both secrets/tls/ and secrets/push-tls/, then run make up."
