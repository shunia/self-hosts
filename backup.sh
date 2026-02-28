#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCK_DIR="$ROOT_DIR/.backup.lock"
BACKUP_ENV_FILE="${BACKUP_ENV_FILE:-$ROOT_DIR/.env.backup}"

KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
RUN_FORGET_PRUNE="${RUN_FORGET_PRUNE:-1}"
KEEP_STAGING_LOCAL="${KEEP_STAGING_LOCAL:-0}"
BACKUP_TAG="${BACKUP_TAG:-docker-compose}"
BACKUP_HOST="${BACKUP_HOST:-$(hostname -s)}"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./backup.sh
  ./backup.sh --help

Environment:
  BACKUP_ENV_FILE        Path to backup env file (default: ./.env.backup)
  KEEP_DAILY             Retention daily snapshots (default: 7)
  KEEP_WEEKLY            Retention weekly snapshots (default: 4)
  KEEP_MONTHLY           Retention monthly snapshots (default: 6)
  RUN_FORGET_PRUNE       Run restic forget --prune (default: 1)
  KEEP_STAGING_LOCAL     Keep _backup_staging/<timestamp> locally (default: 0)
  BACKUP_TAG             restic tag (default: docker-compose)
  BACKUP_HOST            restic host value (default: hostname -s)
USAGE
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
}

is_positive_int() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 ))
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

container_exists() {
  local container="$1"
  docker inspect "$container" >/dev/null 2>&1
}

container_running() {
  local container="$1"
  [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" == "true" ]]
}

dump_postgres() {
  local container="$1"
  local user="$2"
  local db="$3"
  local output_file="$4"

  if ! container_exists "$container"; then
    warn "Container not found, skip dump: $container"
    return 0
  fi
  if ! container_running "$container"; then
    warn "Container not running, skip dump: $container"
    return 0
  fi

  log "Dumping postgres from $container/$db to $output_file"
  docker exec "$container" sh -lc "PGPASSWORD=\"\$POSTGRES_PASSWORD\" pg_dump -U \"$user\" -d \"$db\" --no-owner --no-privileges" | gzip -9 > "$output_file"
}

cleanup() {
  if [[ -d "$LOCK_DIR" ]]; then
    rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
  fi
  if [[ "${KEEP_STAGING_LOCAL}" != "1" && -n "${STAGING_DIR_REL:-}" && -d "${ROOT_DIR}/${STAGING_DIR_REL}" ]]; then
    rm -rf -- "${ROOT_DIR}/${STAGING_DIR_REL}"
  fi
}

trap cleanup EXIT

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done

  require_command docker
  require_command restic
  require_command gzip

  load_backup_env
  validate_restic_env

  mkdir "$LOCK_DIR" 2>/dev/null || die "Another backup appears to be running (.backup.lock exists)"

  cd "$ROOT_DIR"

  local timestamp
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  STAGING_DIR_REL="_backup_staging/${timestamp}"
  mkdir -p "$STAGING_DIR_REL"

  dump_postgres "sub2api-postgres" "sub2api" "sub2api" "${STAGING_DIR_REL}/sub2api-postgres.sql.gz"
  dump_postgres "lobehub-postgres" "postgres" "lobehub" "${STAGING_DIR_REL}/lobehub-postgres.sql.gz"

  cat > "${STAGING_DIR_REL}/backup-manifest.txt" <<EOF
timestamp_utc=${timestamp}
host=${BACKUP_HOST}
tag=${BACKUP_TAG}
root_dir=${ROOT_DIR}
EOF

  local -a candidate_paths=(
    ".env"
    ".env.sub2api"
    "docker-compose.yml"
    "docker-compose.sub2api-allinone.yml"
    "docker-compose.cliproxyapi.yml"
    "docker-compose.lobehub.yml"
    "ctrl_infra.sh"
    "ctrl_sub2api.sh"
    "ctrl_cliproxyapi.sh"
    "ctrl_lobehub.sh"
    "install_vaultwarden.sh"
    "homepage-config"
    "traefik-data"
    "vw-data"
    "cliproxyapi-data"
    "lobehub-data"
    "sub2api-data"
    "sub2api-redis-data"
    "${STAGING_DIR_REL}"
  )

  local -a include_paths=()
  local path
  for path in "${candidate_paths[@]}"; do
    if [[ -e "$path" ]]; then
      include_paths+=("$path")
    else
      warn "Missing path, skipped: $path"
    fi
  done
  [[ "${#include_paths[@]}" -gt 0 ]] || die "No backup paths found"

  local -a backup_cmd=(
    restic
    backup
    --host "$BACKUP_HOST"
    --tag "$BACKUP_TAG"
    --exclude "traefik-data/logs/**"
    --exclude "cliproxyapi-data/logs/**"
  )
  backup_cmd+=("${include_paths[@]}")

  log "Creating restic snapshot"
  "${backup_cmd[@]}"

  if [[ "${RUN_FORGET_PRUNE}" == "1" ]]; then
    local -a forget_cmd=(
      restic
      forget
      --prune
      --host "$BACKUP_HOST"
      --tag "$BACKUP_TAG"
    )

    if is_positive_int "$KEEP_DAILY"; then
      forget_cmd+=(--keep-daily "$KEEP_DAILY")
    fi
    if is_positive_int "$KEEP_WEEKLY"; then
      forget_cmd+=(--keep-weekly "$KEEP_WEEKLY")
    fi
    if is_positive_int "$KEEP_MONTHLY"; then
      forget_cmd+=(--keep-monthly "$KEEP_MONTHLY")
    fi

    log "Applying retention policy (forget + prune)"
    "${forget_cmd[@]}"
  fi

  log "Recent snapshots"
  restic snapshots --host "$BACKUP_HOST" --tag "$BACKUP_TAG"

  log "Backup complete"
}

main "$@"
