#!/usr/bin/env bash
set -euo pipefail

PROJECT="sub2api"
ENV_FILE=".env.sub2api"
COMPOSE_FILE="docker-compose.sub2api-allinone.yml"

cd "$(dirname "$0")"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] Missing $ENV_FILE" >&2
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[ERROR] Missing $COMPOSE_FILE" >&2
  exit 1
fi

compose() {
  docker compose --env-file "$ENV_FILE" -p "$PROJECT" -f "$COMPOSE_FILE" "$@"
}

usage() {
  cat <<'USAGE'
Usage: ./sub2api_ctl.sh <command> [args]

Commands:
  start           Start all sub2api services (up -d)
  stop            Stop all sub2api services
  restart         Restart all sub2api services
  rebuild         Recreate containers (up -d --force-recreate --remove-orphans)
  pull            Pull latest images for sub2api stack
  down            Stop and remove containers/network (keep data volumes)
  status          Show service status
  logs [service]  Follow logs (default: all services)
  config          Validate and print merged compose config

Examples:
  ./sub2api_ctl.sh start
  ./sub2api_ctl.sh logs sub2api
  ./sub2api_ctl.sh rebuild
USAGE
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  start)
    compose up -d
    ;;
  stop)
    compose stop
    ;;
  restart)
    compose restart
    ;;
  rebuild)
    compose up -d --force-recreate --remove-orphans
    ;;
  pull)
    compose pull
    ;;
  down)
    compose down
    ;;
  status)
    compose ps
    ;;
  logs)
    service="${1:-}"
    if [[ -n "$service" ]]; then
      compose logs -f --tail=200 "$service"
    else
      compose logs -f --tail=200
    fi
    ;;
  config)
    compose config
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "[ERROR] Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
