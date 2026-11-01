#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

action=${1:-}
mode=${2:-}
calls=${3:-0}

case "$mode" in
  production)
    compose=(docker compose -f compose.yaml --profile admin)
    services=(postgres synapse ketesa nginx)
    ;;
  local)
    compose=(docker compose -p matrix_local -f compose.local.yaml)
    services=(postgres synapse ketesa nginx)
    ;;
  *)
    echo "Mode must be production or local (use: make MODE=local ...)." >&2
    exit 2
    ;;
esac

[[ $calls == 0 || $calls == 1 ]] || { echo "CALLS must be 0 or 1." >&2; exit 2; }
if [[ $calls == 1 ]]; then
  [[ $mode == production ]] || { echo "CALLS=1 is supported only for production." >&2; exit 2; }
  compose+=(--profile calls)
  services+=(coturn)
fi

require_env() {
  [[ -f .env ]] || { echo "Missing .env. Copy .env.example to .env first." >&2; exit 1; }
}

prepare_element_assets() {
  if [[ -f offline-bundle/static/element/index.html ]]; then
    local checksum
    [[ -f offline-bundle/SHA256SUMS ]] || {
      echo "offline-bundle has no checksum manifest." >&2; exit 1;
    }
    checksum=$(awk '$2 == "./static/element/index.html" {print $1}' offline-bundle/SHA256SUMS)
    [[ $checksum =~ ^[a-f0-9]{64}$ ]] || {
      echo "offline-bundle has no valid Element checksum." >&2; exit 1;
    }
    printf '%s  %s\n' "$checksum" offline-bundle/static/element/index.html | sha256sum -c - >/dev/null
    return
  fi
  [[ ! -e offline-bundle ]] || {
    echo "offline-bundle exists but Element assets are incomplete." >&2; exit 1;
  }
  echo "Element assets are missing; preparing the verified offline bundle."
  bash scripts/offline-export.sh
}

setting() {
  python3 scripts/render-config.py --get "$1"
}

urls() {
  if [[ $mode == local ]]; then
    local host element_port admin_port
    host=$(setting LOCAL_HOST)
    element_port=$(setting LOCAL_ELEMENT_PORT)
    admin_port=$(setting LOCAL_ADMIN_PORT)
    element_url="http://$host:$element_port"
    api_url="$element_url/_matrix/client/versions"
    admin_url="http://$host:$admin_port/admin/"
  else
    element_url=$(setting PUBLIC_BASE_URL)
    api_url="$element_url/_matrix/client/versions"
    admin_url=""
  fi
}

container_health() {
  local service=$1 container health name
  container=$("${compose[@]}" ps -q "$service" 2>/dev/null || true)
  if [[ -z $container ]]; then
    printf '%s\t%s\t%s\n' "$service" not-created unavailable
    return
  fi
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || printf unavailable)
  name=$(docker inspect --format '{{.Name}}' "$container" 2>/dev/null | sed 's#^/##' || printf unavailable)
  printf '%s\t%s\t%s\n' "$service" "$name" "$health"
}

all_healthy() {
  local service line health
  for service in "${services[@]}"; do
    line=$(container_health "$service")
    health=${line##*$'\t'}
    [[ $health == healthy || $health == running ]] || return 1
  done
}

check_url() {
  local label=$1 url=$2
  if curl --fail --silent --location --max-time 5 -o /dev/null "$url"; then
    printf '  %-16s %s (available)\n' "$label:" "$url"
    return 0
  fi
  printf '  %-16s %s (unavailable)\n' "$label:" "$url"
  return 1
}

dashboard() {
  local bad=0 service name health turn_enabled=0 turn_line turn_health make_prefix
  urls
  printf '\nMatrix stack status\n  Mode: %s\n\nServices\n' "$mode"
  for service in "${services[@]}"; do
    IFS=$'\t' read -r _ name health <<< "$(container_health "$service")"
    printf '  %-14s %-32s %s\n' "$service" "$name" "$health"
    [[ $health == healthy || $health == running ]] || bad=1
  done
  printf '\nURLs\n'
  check_url 'Element Web' "$element_url" || bad=1
  check_url 'Matrix API' "$api_url" || bad=1
  if [[ -n $admin_url ]]; then
    check_url 'Ketesa Admin' "$admin_url" || bad=1
  else
    printf '  %-16s localhost/SSH tunnel only (/admin/)\n' 'Ketesa Admin:'
  fi
  if grep -q '^TURN_ENABLED=' .env; then
    turn_enabled=$(setting TURN_ENABLED)
  fi
  if [[ $turn_enabled == 1 ]]; then
    local turn_compose=(docker compose -f compose.yaml --profile calls)
    turn_line=$("${turn_compose[@]}" ps -q coturn 2>/dev/null || true)
    if [[ -n $turn_line ]]; then
      turn_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$turn_line" 2>/dev/null || printf unavailable)
    else
      turn_health=not-running
    fi
    printf '  %-16s configured; coturn is %s (two-client call test required)\n' 'Calling:' "$turn_health"
  else
    printf '  %-16s disabled\n' 'Calling:'
  fi
  make_prefix=make
  [[ $mode == local ]] && make_prefix='make MODE=local'
  printf '\nLifecycle\n  Restart: %s restart\n  Update:  git pull --ff-only && %s update\n' "$make_prefix" "$make_prefix"
  if (( bad )); then
    printf '\nWarning: one or more services or endpoints are unavailable. See: make MODE=%s logs\n' "$mode" >&2
    return 1
  fi
}

initialize() {
  require_env
  if [[ $mode == local ]]; then
    prepare_element_assets
    bash scripts/local-init.sh
  else
    bash scripts/init.sh
    if [[ ! -f data/element/index.html ]]; then
      prepare_element_assets
      cp -a offline-bundle/static/element/. data/element/
    fi
    [[ -f data/element/index.html ]] || {
      echo "Element assets are missing; run scripts/offline-export.sh first." >&2; exit 1;
    }
    [[ -f secrets/tls/fullchain.pem && -f secrets/tls/privkey.pem ]] || {
      echo "Production TLS files are missing from secrets/tls/." >&2; exit 1;
    }
  fi
}

validate_calls() {
  if [[ $calls == 1 && $(setting TURN_ENABLED) != 1 ]]; then
    echo "CALLS=1 requires TURN_ENABLED=1 and valid TURN settings in .env." >&2
    exit 1
  fi
}

validate_compose() {
  "${compose[@]}" config -q
}

wait_for_ready() {
  local i
  for ((i=0; i<30; i++)); do
    if all_healthy; then
      dashboard
      return
    fi
    sleep 2
  done
  dashboard || true
  echo 'Timed out waiting for running/healthy services.' >&2
  return 1
}

# Validate the running Nginx configuration before reloading mounted config files.
# This does not recreate or restart the Nginx container.
reload_nginx_if_running() {
  local container
  container=$("${compose[@]}" ps -q nginx 2>/dev/null || true)
  [[ -n $container ]] || return 0
  if ! docker exec "$container" nginx -t; then
    echo 'Nginx configuration validation failed; refusing to reload.' >&2
    return 1
  fi
  docker exec "$container" nginx -s reload
}

start_stack() {
  initialize
  validate_calls
  validate_compose
  "${compose[@]}" up -d --pull never "${services[@]}"
  reload_nginx_if_running
  wait_for_ready
}

update_stack() {
  initialize
  validate_calls
  validate_compose
  echo 'Applying checked-out repository changes; Git is not modified.'
  "${compose[@]}" pull --policy missing "${services[@]}"
  "${compose[@]}" up -d --pull never "${services[@]}"
  reload_nginx_if_running
  wait_for_ready
}

restart_stack() {
  initialize
  validate_calls
  validate_compose
  local affected=(synapse ketesa nginx)
  [[ $calls == 1 ]] && affected+=(coturn)
  "${compose[@]}" up -d --pull never --force-recreate --no-deps "${affected[@]}"
  wait_for_ready
}

case "$action" in
  up)
    start_stack
    ;;
  restart)
    restart_stack
    ;;
  update)
    update_stack
    ;;
  down)
    require_env
    "${compose[@]}" stop "${services[@]}"
    # Stop an already-running TURN service even when CALLS=0.
    if [[ $mode == production && $calls == 0 ]]; then
      docker compose -f compose.yaml --profile calls stop coturn
    fi
    ;;
  status)
    require_env
    dashboard
    ;;
  logs)
    require_env
    "${compose[@]}" logs --follow --tail=100 "${services[@]}"
    ;;
  *)
    echo 'Usage: stack.sh {up|down|restart|update|status|logs} {production|local} [0|1]' >&2
    exit 2
    ;;
esac
