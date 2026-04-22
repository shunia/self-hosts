#!/usr/bin/env bash
set -euo pipefail

PROJECT="cliproxyapi"
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.cliproxyapi.yml"
CONFIG_TEMPLATE="templates/cliproxyapi-config.yaml.example"
CONFIG_FILE="cliproxyapi-data/config/config.yaml"

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

ensure_runtime_config() {
  if [[ ! -f "$CONFIG_TEMPLATE" ]]; then
    echo "[ERROR] Missing $CONFIG_TEMPLATE" >&2
    exit 1
  fi

  mkdir -p "cliproxyapi-data/config" "cliproxyapi-data/auths" "cliproxyapi-data/logs"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_TEMPLATE" "$CONFIG_FILE"
    echo "[WARN] Initialized $CONFIG_FILE from template; review upstreams and API keys before exposing the service." >&2
  fi
}

ensure_permissions() {
  if [[ -d "cliproxyapi-data/auths" ]]; then
    chmod 700 "cliproxyapi-data/auths"
    find "cliproxyapi-data/auths" -type f -exec chmod 600 {} +
  fi

  if [[ -d "cliproxyapi-data/config" ]]; then
    chmod 700 "cliproxyapi-data/config"
    find "cliproxyapi-data/config" -type f -exec chmod 600 {} +
  fi
}

usage() {
  cat <<'USAGE'
Usage: ./ctrl_cliproxyapi.sh <command> [args]

Commands:
  start           Start CLIProxyAPI (up -d)
  stop            Stop CLIProxyAPI
  restart         Restart CLIProxyAPI
  rebuild         Recreate container (up -d --force-recreate --remove-orphans)
  pull            Pull latest image for CLIProxyAPI
  down            Stop and remove container/network (keep data volumes)
  status          Show service status
  logs [service]  Follow logs (default: cliproxyapi)
  config          Validate and print merged compose config

Examples:
  ./ctrl_cliproxyapi.sh start
  ./ctrl_cliproxyapi.sh logs
  ./ctrl_cliproxyapi.sh rebuild
USAGE
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  start)
    ensure_runtime_config
    ensure_permissions
    compose up -d
    ;;
  stop)
    compose stop
    ;;
  restart)
    ensure_runtime_config
    ensure_permissions
    compose restart
    ;;
  rebuild)
    ensure_runtime_config
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
    service="${1:-cliproxyapi}"
    compose logs -f --tail=200 "$service"
    ;;
  config)
    ensure_runtime_config
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
