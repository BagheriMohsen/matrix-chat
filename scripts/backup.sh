#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo ".env missing" >&2; exit 1; }
POSTGRES_DB=$(python3 scripts/render-config.py --get POSTGRES_DB)
POSTGRES_USER=$(python3 scripts/render-config.py --get POSTGRES_USER)
umask 077
server_name=$(sed -nE 's/^server_name: "([^"]+)"$/\1/p' data/synapse/homeserver.yaml)
[[ -n $server_name && -f "data/synapse/$server_name.signing.key" ]] || { echo "Synapse configuration or signing key missing." >&2; exit 1; }
stamp=$(date -u +%Y%m%dT%H%M%SZ); out="backups/$stamp"
mkdir -p "$out"
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > "$out/synapse.pg.dump"
tar -C data/synapse -czf "$out/synapse-files.tgz" media_store "$server_name.signing.key" registration_shared_secret homeserver.yaml
tar -C . -czf "$out/deployment-config.tgz" compose.yaml config .env
sha256sum "$out"/* > "$out/SHA256SUMS"
echo "Backup created at $out. Encrypt it before any off-host transfer; it contains keys and credentials."
