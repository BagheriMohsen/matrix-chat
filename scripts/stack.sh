#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

action=${1:-}
mode=${2:-}
calls=${3:-0}

case "$mode" in
  production)
    compose=(docker compose -f compose.yaml)
    services=(postgres synapse nginx)
    ;;
  local)
    compose=(docker compose -p matrix_local -f compose.local.yaml)
    services=(postgres synapse synapse-admin nginx)
    ;;
  *)
    echo "Mode must be production or local (use: make MODE=local ...)." >&2
    exit 2
    ;;
esac

[[ $calls == 0 || $calls == 1 ]] || { echo "CALLS must be 0 or 1." >&2; exit 2; }
calls_compose=(docker compose -f compose.yaml --profile calls)
if [[ $calls == 1 ]]; then
  [[ $mode == production ]] || { echo "CALLS=1 is supported only for the production Compose profile." >&2; exit 2; }
  compose+=(--profile calls)
  services+=(coturn)
fi

require_env() {
  [[ -f .env ]] || { echo "Missing .env. Copy .env.example to .env first." >&2; exit 1; }
}

setting() {
  python3 scripts/render-config.py --get "$1"
}

urls() {
  if [[ $mode == local ]]; then
    local host element_port admin_port admin_path
    host=$(setting LOCAL_HOST)
    element_port=$(setting LOCAL_ELEMENT_PORT)
    admin_port=$(setting LOCAL_ADMIN_PORT)
    admin_path=$(setting ADMIN_PATH)
    element_url="http://$host:$element_port"
    api_url="$element_url/_matrix/client/versions"
    if [[ $admin_path == / ]]; then
      admin_url="http://$host:$admin_port/"
    else
      admin_url="http://$host:$admin_port$admin_path/"
    fi
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
    printf '%s\t%s\t%s\n' "$service" "not-created" "unavailable"
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
    [[ $health == healthy ]] || return 1
  done
}

check_url() {
  local label=$1 url=$2
  if curl --fail --silent --location --max-time 5 -o /dev/null "$url"; then
    printf '  %-14s %s (available)\n' "$label:" "$url"
    return 0
  fi
  printf '  %-14s %s (unavailable)\n' "$label:" "$url"
  return 1
}

dashboard() {
  local bad=0 service name health turn_enabled turn_line turn_health
  urls
  printf '\nMatrix stack status\n'
  printf '  Mode: %s\n' "$mode"
  printf '\nServices\n'
  for service in "${services[@]}"; do
    IFS=$'\t' read -r _ name health <<< "$(container_health "$service")"
    printf '  %-14s %-32s %s\n' "$service" "$name" "$health"
    [[ $health == healthy ]] || bad=1
  done
  printf '\nURLs\n'
  check_url "Element Web" "$element_url" || bad=1
  check_url "Matrix API" "$api_url" || bad=1
  if [[ -n $admin_url ]]; then
    check_url "Synapse Admin" "$admin_url" || bad=1
  else
    printf '  %-14s disabled in production\n' "Synapse Admin:"
  fi
  turn_enabled=$(setting TURN_ENABLED)
  if [[ $turn_enabled == 1 ]]; then
    turn_line=$("${calls_compose[@]}" ps -q coturn 2>/dev/null || true)
    if [[ -n $turn_line ]]; then
      turn_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$turn_line" 2>/dev/null || printf unavailable)
    else
      turn_health=not-running
    fi
    printf '  %-14s configured; coturn is %s (two-client call test required)\n' "Calling:" "$turn_health"
  else
    printf '  %-14s disabled\n' "Calling:"
  fi
  if (( bad )); then
    printf '\nWarning: one or more services or endpoints are unavailable. See: make MODE=%s logs\n' "$mode" >&2
    return 1
  fi
}

initialize() {
  require_env
  if [[ $mode == local ]]; then
    bash scripts/local-init.sh
  else
    bash scripts/init.sh
    if [[ ! -f data/element/index.html && -f offline-bundle/static/element/index.html ]]; then
      cp -a offline-bundle/static/element/. data/element/
    fi
    [[ -f data/element/index.html ]] || { echo "Element assets are missing; run scripts/offline-export.sh first." >&2; exit 1; }
    [[ -f secrets/tls/fullchain.pem && -f secrets/tls/privkey.pem ]] || { echo "Production TLS files are missing from secrets/tls/." >&2; exit 1; }
  fi
}

case "$action" in
  up)
    initialize
    if [[ $calls == 1 && $(setting TURN_ENABLED) != 1 ]]; then
      echo "CALLS=1 requires TURN_ENABLED=1 and valid TURN settings in .env." >&2
      exit 1
    fi
    "${compose[@]}" up -d --pull never
    for _ in $(seq 1 30); do
      all_healthy && { dashboard; exit 0; }
      sleep 2
    done
    dashboard || true
    echo "Timed out waiting for healthy services." >&2
    exit 1
    ;;
  down)
    if [[ $mode == production ]]; then
      "${calls_compose[@]}" stop
    else
      "${compose[@]}" stop
    fi
    ;;
  status)
    require_env
    dashboard
    ;;
  logs)
    "${compose[@]}" logs --follow --tail=100 "${services[@]}"
    ;;
  *)
    echo "Usage: stack.sh {up|down|status|logs} {production|local} [0|1]" >&2
    exit 2
    ;;
esac
