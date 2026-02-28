# Restic Backup Guide

## 1) Prerequisites

- `docker`
- `restic`
- `gzip`

## 2) Configure backup credentials

1. Copy `.env.backup.example` to `.env.backup`.
2. Fill in real values from Bitwarden:
   - `RESTIC_REPOSITORY`
   - `RESTIC_PASSWORD` (or `RESTIC_PASSWORD_FILE`)
   - backend credentials (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`, etc.)

`backup.sh` and `restore.sh` auto-load `.env.backup` if present.

## 3) Run backup

```bash
./backup.sh
```

What `backup.sh` does:
- Dumps postgres from `sub2api-postgres` and `lobehub-postgres` to `_backup_staging/<timestamp>/`.
- Backs up:
  - `.env`, `.env.sub2api`
  - `docker-compose*.yml`
  - `ctrl_*.sh`, `install_vaultwarden.sh`
  - `homepage-config/`
  - `traefik-data/`, `vw-data/`, `cliproxyapi-data/`, `lobehub-data/`, `sub2api-data/`, `sub2api-redis-data/`
  - generated SQL dumps in `_backup_staging/<timestamp>/`
- Applies retention policy (`keep-daily/weekly/monthly`) with `forget --prune`.

Notes:
- `traefik-data/logs/**` and `cliproxyapi-data/logs/**` are excluded.
- If a postgres container is absent or stopped, that dump is skipped with warning.

## 4) List snapshots

```bash
./restore.sh --list
```

## 5) Restore snapshot

```bash
./restore.sh --snapshot latest
```

By default this restores to a new folder:

```text
./_restore/<timestamp>
```

Or specify your own target:

```bash
./restore.sh --snapshot <snapshot_id> --target ./_restore/manual-restore
```

## 6) Restore databases from dump

After files are restored, import SQL dumps if needed:

```bash
gunzip -c <sub2api-postgres.sql.gz> | docker exec -i sub2api-postgres psql -U sub2api -d sub2api
gunzip -c <lobehub-postgres.sql.gz> | docker exec -i lobehub-postgres psql -U postgres -d lobehub
```

## 7) Suggested automation

Use `cron` or `systemd timer` to run daily:

```bash
0 3 * * * cd /opt/docker-compose && ./backup.sh >> /var/log/docker-compose-backup.log 2>&1
```
