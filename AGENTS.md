# Repository Guidelines

## Project Structure & Module Organization
- Root stack definitions: `docker-compose.yml` (Traefik, Vaultwarden, Uptime Kuma, Beszel, Homepage), `docker-compose.sub2api-allinone.yml`, and `docker-compose.cliproxyapi.yml`.
- Operational entrypoints: `ctrl_infra.sh`, `ctrl_sub2api.sh`, and `ctrl_cliproxyapi.sh`.
- Bootstrap utility: `install_vaultwarden.sh` for first-time host setup.
- Homepage service catalog: `homepage-config/services.yaml` stores URL entries shown in Homepage.
- Runtime data directories (`traefik-data/`, `vw-data/`, `sub2api-*/`, `cliproxyapi-data/`, `uptime-kuma-data/`, `beszel-*`) are persistent state, not application source code.
- Environment files: `.env` (infra + cliproxyapi) and `.env.sub2api` (sub2api stack).

## Build, Test, and Development Commands
- `./ctrl_infra.sh start|stop|restart|status|logs [service]|config`
- `./ctrl_sub2api.sh start|rebuild|pull|status|logs [service]|config`
- `./ctrl_cliproxyapi.sh start|rebuild|pull|status|logs|config`
- Use `pull` before planned upgrades; use `rebuild` after image, env, or compose changes.
- Direct compose validation example:
  - `docker compose --env-file .env.sub2api -p sub2api -f docker-compose.sub2api-allinone.yml config`

## Coding Style & Naming Conventions
- Shell scripts should use Bash with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Keep script constants uppercase (`PROJECT`, `ENV_FILE`, `COMPOSE_FILE`) and helper functions lowercase (`compose`, `usage`).
- Compose YAML uses 2-space indentation, quoted strings, explicit `container_name`, and env interpolation (`${VAR}` or `${VAR:?ERROR}`).
- Name new control scripts as `ctrl_<stack>.sh` and compose files as `docker-compose.<stack>.yml`.
- When adding/removing externally exposed containers or changing service domains, update `homepage-config/services.yaml` in the same change.

## Testing Guidelines
- No automated test framework exists in this repository.
- Minimum verification for changes:
  - Run `./ctrl_<stack>.sh config` for affected stacks.
  - Run `./ctrl_<stack>.sh start` then `./ctrl_<stack>.sh status`.
  - Run targeted log and health checks (example: `./ctrl_sub2api.sh logs sub2api`, then check `/health` endpoint).

## Commit & Pull Request Guidelines
- Git history is not present in this checkout, so follow Conventional Commits (`feat:`, `fix:`, `chore:`) for consistency.
- Keep commits scoped to one stack or one operational concern.
- PRs should include purpose, changed files, env vars added/changed, validation commands run, and rollback steps.

## Security & Configuration Tips
- Never commit secret values from `.env*` or credentials under data directories.
- Preserve strict permissions on certificate/state files (for example `traefik-data/acme.json` with `chmod 600`).
- Prefer pinned image digests for internet-facing services where practical.
