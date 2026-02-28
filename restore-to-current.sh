#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_ENV_FILE="${BACKUP_ENV_FILE:-$ROOT_DIR/.env.backup}"
SNAPSHOT="${SNAPSHOT:-latest}"
FORCE_OVERWRITE="${FORCE_OVERWRITE:-0}"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./restore-to-current.sh
  ./restore-to-current.sh --snapshot <id|latest> [--force]

Behavior:
  - Restores a snapshot into ./_restore/<timestamp>
  - Copies restored /opt/docker-compose over current directory
  - Imports postgres dumps if present

Options:
  --snapshot <id|latest>   restic snapshot id or "latest"
  --force                  allow overwrite of current directory contents
USAGE
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
}

load_backup_env() {
  if [[ -f "$BACKUP_ENV_FILE" ]]; then
    log "Loading backup environment from $BACKUP_ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    source "$BACKUP_ENV_FILE"
    set +a
  fi
}

validate_restic_env() {
  [[ -n "${RESTIC_REPOSITORY:-}" ]] || die "RESTIC_REPOSITORY is required"
  if [[ -z "${RESTIC_PASSWORD:-}" && -z "${RESTIC_PASSWORD_FILE:-}" && -z "${RESTIC_PASSWORD_COMMAND:-}" ]]; then
    die "Set one of RESTIC_PASSWORD / RESTIC_PASSWORD_FILE / RESTIC_PASSWORD_COMMAND"
  fi
}

assert_safe() {
  if [[ "$FORCE_OVERWRITE" != "1" ]]; then
    die "Refusing to overwrite current directory without --force"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --snapshot)
        [[ $# -ge 2 ]] || die "Missing value for --snapshot"
        SNAPSHOT="$2"
        shift 2
        ;;
      --force)
        FORCE_OVERWRITE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  require_command restic
  require_command rsync
  require_command docker
  require_command gunzip

  load_backup_env
  validate_restic_env

  assert_safe

  log "Restoring snapshot '$SNAPSHOT' into _restore"
  ./restore.sh --snapshot "$SNAPSHOT"

  local latest_restore
  latest_restore="$(ls -dt "$ROOT_DIR"/_restore/*/opt/docker-compose 2>/dev/null | head -n 1 || true)"
  [[ -n "$latest_restore" ]] || die "Restore directory not found under _restore"

  log "Stopping stacks before overwrite"
  ./ctrl_lobehub.sh stop || true
  ./ctrl_sub2api.sh stop || true
  ./ctrl_cliproxyapi.sh stop || true
  ./ctrl_infra.sh stop || true

  log "Syncing restored content into current directory"
  rsync -a "$latest_restore"/ "$ROOT_DIR"/

  log "Starting databases for restore"
  ./ctrl_sub2api.sh start
  ./ctrl_lobehub.sh start

  local sub_dump
  local lobe_dump
  sub_dump="$(ls -t "$ROOT_DIR"/_backup_staging/*/sub2api-postgres.sql.gz 2>/dev/null | head -n 1 || true)"
  lobe_dump="$(ls -t "$ROOT_DIR"/_backup_staging/*/lobehub-postgres.sql.gz 2>/dev/null | head -n 1 || true)"

  if [[ -n "$sub_dump" ]]; then
    log "Importing sub2api postgres dump: $sub_dump"
    gunzip -c "$sub_dump" | docker exec -i sub2api-postgres psql -U sub2api -d sub2api
  else
    log "No sub2api postgres dump found"
  fi

  if [[ -n "$lobe_dump" ]]; then
    log "Importing lobehub postgres dump: $lobe_dump"
    gunzip -c "$lobe_dump" | docker exec -i lobehub-postgres psql -U postgres -d lobehub
  else
    log "No lobehub postgres dump found"
  fi

  log "Starting all stacks and checking status"
  ./ctrl_infra.sh start && ./ctrl_infra.sh status
  ./ctrl_sub2api.sh start && ./ctrl_sub2api.sh status
  ./ctrl_cliproxyapi.sh start && ./ctrl_cliproxyapi.sh status
  ./ctrl_lobehub.sh start && ./ctrl_lobehub.sh status

  log "Restore to current directory complete"
}

main "$@"
