#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker-compose.yml"

cd "$(dirname "$0")"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[ERROR] Missing $COMPOSE_FILE" >&2
  exit 1
fi

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

usage() {
  cat <<'USAGE'
Usage: ./docker_compose_ctl.sh <command> [args]

Commands:
  start           Start all services (up -d)
  stop            Stop all services
  restart         Restart all services
  rebuild         Recreate containers (up -d --force-recreate --remove-orphans)
  pull            Pull latest images for this stack
  down            Stop and remove containers/network (keep data volumes)
  status          Show service status
  logs [service]  Follow logs (default: all services)
  config          Validate and print merged compose config

Examples:
  ./docker_compose_ctl.sh start
  ./docker_compose_ctl.sh logs traefik
  ./docker_compose_ctl.sh rebuild
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
