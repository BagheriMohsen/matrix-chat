#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -eq 1 && -d $1 ]] || { echo "Usage: restore.sh backups/TIMESTAMP" >&2; exit 1; }
dir=$1
[[ -f .env && -f "$dir/synapse.pg.dump" && -f "$dir/synapse-files.tgz" && -f "$dir/deployment-config.tgz" && -f "$dir/SHA256SUMS" ]] || { echo "Target .env or required backup files missing." >&2; exit 1; }
(cd "$dir" && sha256sum -c SHA256SUMS)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
tar -xzf "$dir/deployment-config.tgz" -C "$stage"
cmp -s .env "$stage/.env" || { echo "Target .env differs from backup; select a matching recovery environment." >&2; exit 1; }
[[ -f secrets/tls/fullchain.pem && -f secrets/tls/privkey.pem && -f data/element/index.html ]] || { echo "Restore protected TLS material and Element assets in this recovery environment first." >&2; exit 1; }
read -r -p "Restore $dir into this deployment (current data is moved aside)? Type RESTORE: " answer
[[ $answer == RESTORE ]] || { echo "Cancelled."; exit 1; }
POSTGRES_DB=$(python3 scripts/render-config.py --get POSTGRES_DB)
POSTGRES_USER=$(python3 scripts/render-config.py --get POSTGRES_USER)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
docker compose down
[[ ! -e data ]] || mv data "data.pre-restore.$stamp"
mkdir -p data/synapse data/postgres
tar -xzf "$dir/synapse-files.tgz" -C data/synapse
[[ ! -d "data.pre-restore.$stamp/element" ]] || mv "data.pre-restore.$stamp/element" data/element
python3 scripts/render-config.py
docker compose up -d postgres
until docker compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null; do sleep 2; done
docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists < "$dir/synapse.pg.dump"
docker compose up -d
echo "Restore started. Verify login, media, and encrypted-room access; E2EE history still requires users' own recovery keys/devices. Prior data remains at data.pre-restore.$stamp."
