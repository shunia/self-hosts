#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker-compose.yml"
SERVICE="xray"

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
Usage: ./ctrl_xray.sh <command>

Commands:
  start     Start xray (up -d)
  stop      Stop xray
  restart   Restart xray
  rebuild   Recreate xray container (up -d --force-recreate --no-deps)
  pull      Pull latest xray image
  down      Stop and remove xray container
  status    Show xray status
  logs      Follow xray logs
  config    Validate and print xray compose config

Examples:
  ./ctrl_xray.sh start
  ./ctrl_xray.sh logs
  ./ctrl_xray.sh rebuild
USAGE
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  start)
    compose up -d "$SERVICE"
    ;;
  stop)
    compose stop "$SERVICE"
    ;;
  restart)
    compose restart "$SERVICE"
    ;;
  rebuild)
    compose up -d --force-recreate --no-deps "$SERVICE"
    ;;
  pull)
    compose pull "$SERVICE"
    ;;
  down)
    compose stop "$SERVICE"
    compose rm -f "$SERVICE"
    ;;
  status)
    compose ps "$SERVICE"
    ;;
  logs)
    compose logs -f --tail=200 "$SERVICE"
    ;;
  config)
    compose config "$SERVICE"
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
