#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_ENV_FILE="${BACKUP_ENV_FILE:-$ROOT_DIR/.env.backup}"

SNAPSHOT="${SNAPSHOT:-latest}"
TARGET_DIR="${TARGET_DIR:-$ROOT_DIR/_restore/$(date -u +%Y%m%dT%H%M%SZ)}"
FORCE_TARGET="${FORCE_TARGET:-0}"

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
  ./restore.sh --list
  ./restore.sh [--snapshot <id|latest>] [--target <dir>] [--force-target]

Examples:
  ./restore.sh --list
  ./restore.sh --snapshot latest
  ./restore.sh --snapshot 3f0d1a5b --target ./_restore/manual-restore
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

list_snapshots() {
  restic snapshots
}

print_next_steps() {
  local target="$1"
  log "Restore finished to: $target"
  log "Recovered dumps (if present):"
  find "$target" -type f \( -name "sub2api-postgres.sql.gz" -o -name "lobehub-postgres.sql.gz" \) 2>/dev/null || true

  cat <<EOF

Suggested next steps:
1. Inspect restored files under:
   $target
2. Stop related stacks before in-place replacement:
   ./ctrl_lobehub.sh stop
   ./ctrl_sub2api.sh stop
   ./ctrl_cliproxyapi.sh stop
   ./ctrl_infra.sh stop
3. Restore postgres dumps as needed:
   gunzip -c <sub2api-postgres.sql.gz> | docker exec -i sub2api-postgres psql -U sub2api -d sub2api
   gunzip -c <lobehub-postgres.sql.gz> | docker exec -i lobehub-postgres psql -U postgres -d lobehub
4. Start stacks and validate:
   ./ctrl_infra.sh start && ./ctrl_infra.sh status
   ./ctrl_sub2api.sh start && ./ctrl_sub2api.sh status
   ./ctrl_cliproxyapi.sh start && ./ctrl_cliproxyapi.sh status
   ./ctrl_lobehub.sh start && ./ctrl_lobehub.sh status
EOF
}

main() {
  local list_only=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --list)
        list_only=1
        shift
        ;;
      --snapshot)
        [[ $# -ge 2 ]] || die "Missing value for --snapshot"
        SNAPSHOT="$2"
        shift 2
        ;;
      --target)
        [[ $# -ge 2 ]] || die "Missing value for --target"
        TARGET_DIR="$2"
        shift 2
        ;;
      --force-target)
        FORCE_TARGET=1
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
  load_backup_env
  validate_restic_env

  if [[ "$list_only" == "1" ]]; then
    list_snapshots
    exit 0
  fi

  if [[ -e "$TARGET_DIR" && "$FORCE_TARGET" != "1" ]]; then
    die "Target exists: $TARGET_DIR (use --force-target to allow)"
  fi
  mkdir -p "$TARGET_DIR"

  log "Restoring snapshot '$SNAPSHOT' to '$TARGET_DIR'"
  restic restore "$SNAPSHOT" --target "$TARGET_DIR"

  print_next_steps "$TARGET_DIR"
}

main "$@"
