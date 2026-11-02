#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

action=${1:-}
compose=(docker compose -f compose.yaml --profile admin)

local_admin_url() {
  local host port
  host=$(python3 scripts/render-config.py --get LOCAL_HOST)
  port=$(python3 scripts/render-config.py --get LOCAL_ADMIN_PORT)
  printf 'http://%s:%s/admin/' "$host" "$port"
}

require_env() {
  [[ -f .env ]] || { echo "Missing .env. Copy .env.example to .env first." >&2; exit 1; }
}

prepare_config() {
  require_env
  # Rendering changes only managed files on disk. Nginx is not reloaded here.
  python3 scripts/render-config.py
}

ketesa_id() {
  "${compose[@]}" ps -q ketesa 2>/dev/null || true
}

case "$action" in
  up)
    prepare_config
    "${compose[@]}" up -d --pull never --no-deps ketesa
    echo "Ketesa started. After Nginx has been explicitly reloaded, open $(local_admin_url) locally or through an SSH tunnel."
    ;;
  down)
    require_env
    "${compose[@]}" stop ketesa
    ;;
  status)
    require_env
    "${compose[@]}" ps ketesa
    ;;
  logs)
    require_env
    "${compose[@]}" logs --follow --tail=100 ketesa
    ;;
  check)
    prepare_config
    id=$(ketesa_id)
    [[ -n $id ]] || { echo "Ketesa is not running; run make admin-up first." >&2; exit 1; }
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id")
    [[ $health == healthy ]] || { echo "Ketesa container is $health." >&2; exit 1; }
    curl --fail --silent --max-time 5 "$(local_admin_url)" -o /dev/null
    echo "Ketesa is healthy and the localhost-only /admin/ route responds. Log in manually with an existing Synapse server-admin account."
    ;;
  *)
    echo "Usage: admin.sh {up|down|status|logs|check}" >&2
    exit 2
    ;;
esac
