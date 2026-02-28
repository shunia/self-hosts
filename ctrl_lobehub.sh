#!/usr/bin/env bash
set -euo pipefail

PROJECT="lobehub"
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.lobehub.yml"

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
Usage: ./ctrl_lobehub.sh <command> [args]

Commands:
  start           Start LobeHub (up -d)
  stop            Stop LobeHub
  restart         Restart LobeHub
  rebuild         Recreate container (up -d --force-recreate --remove-orphans)
  pull            Pull latest image for LobeHub
  down            Stop and remove container/network (keep data volumes)
  status          Show service status
  logs [service]  Follow logs (default: lobehub)
  config          Validate and print merged compose config

Examples:
  ./ctrl_lobehub.sh start
  ./ctrl_lobehub.sh logs
  ./ctrl_lobehub.sh rebuild
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
    service="${1:-lobehub}"
    compose logs -f --tail=200 "$service"
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
