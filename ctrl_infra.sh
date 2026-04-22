#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="docker-compose.yml"
TEMPLATES_DIR="templates"
GENERATED_DIR="generated-config"

cd "$(dirname "$0")"

# shellcheck disable=SC1091
source "./runtime_config.sh"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[ERROR] Missing $COMPOSE_FILE" >&2
  exit 1
fi

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

ensure_runtime_files() {
  runtime_config_generate_infra "$TEMPLATES_DIR" "$GENERATED_DIR"
}

ensure_permissions() {
  [[ -f ".env.backup" ]] && chmod 600 ".env.backup"

  if [[ -d "traefik-data/logs" ]]; then
    chmod 700 "traefik-data/logs"
  fi
  [[ -f "traefik-data/acme.json" ]] && chmod 600 "traefik-data/acme.json"
  [[ -f "traefik-data/logs/access.log" ]] && chmod 600 "traefik-data/logs/access.log"

  if [[ -d "vw-data" ]]; then
    find "vw-data" -type d -exec chmod 700 {} +
    find "vw-data" -type f -exec chmod 600 {} +
  fi
}

usage() {
  cat <<'USAGE'
Usage: ./ctrl_infra.sh <command> [args]

Commands:
  start           Start infra services (xray is included, but prefer ./ctrl_xray.sh for xray-only ops)
  stop            Stop infra services
  restart         Restart infra services
  rebuild         Recreate infra containers (up -d --force-recreate --remove-orphans)
  pull            Pull latest images for this stack
  down            Stop and remove containers/network (keep data volumes)
  status          Show service status
  logs [service]  Follow logs (default: all services)
  config          Validate and print merged compose config

Examples:
  ./ctrl_infra.sh start
  ./ctrl_infra.sh logs traefik
  ./ctrl_xray.sh restart
  ./ctrl_infra.sh rebuild
USAGE
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  start)
    ensure_runtime_files
    ensure_permissions
    compose up -d
    ;;
  stop)
    compose stop
    ;;
  restart)
    ensure_runtime_files
    ensure_permissions
    compose restart
    ;;
  rebuild)
    ensure_runtime_files
    ensure_permissions
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
    ensure_runtime_files
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
