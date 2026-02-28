# Restic 备份指南

## 1) 前置条件

- `docker`
- `restic`
- `gzip`

## 2) 配置备份凭据

1. 复制 `.env.backup.example` 为 `.env.backup`。
2. 从 Bitwarden 填入真实值：
   - `RESTIC_REPOSITORY`
   - `RESTIC_PASSWORD`（或 `RESTIC_PASSWORD_FILE`）
   - 后端凭据（`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` 等）

如果存在 `.env.backup`，`backup.sh` 和 `restore.sh` 会自动加载。

## 3) 执行备份

```bash
./backup.sh
```

`backup.sh` 做的事情：
- 导出 `sub2api-postgres` 与 `lobehub-postgres` 的数据库到 `_backup_staging/<timestamp>/`。
- 备份以下内容：
  - `.env`、`.env.sub2api`
  - `docker-compose*.yml`
  - `ctrl_*.sh`、`install_vaultwarden.sh`
  - `homepage-config/`
  - `traefik-data/`、`vw-data/`、`cliproxyapi-data/`、`lobehub-data/`、`sub2api-data/`、`sub2api-redis-data/`
  - `_backup_staging/<timestamp>/` 下生成的 SQL 导出文件
- 应用保留策略（`keep-daily/weekly/monthly` + `forget --prune`）。

说明：
- `traefik-data/logs/**` 和 `cliproxyapi-data/logs/**` 会被排除。
- 如果数据库容器不存在或未运行，会提示并跳过导出。

## 4) 查看快照

```bash
./restore.sh --list
```

## 5) 恢复快照到新目录

```bash
./restore.sh --snapshot latest
```

默认恢复到：

```text
./_restore/<timestamp>
```

也可以指定目标目录：

```bash
./restore.sh --snapshot <snapshot_id> --target ./_restore/manual-restore
```

## 6) 从导出文件恢复数据库

恢复后如需导入 SQL：

```bash
gunzip -c <sub2api-postgres.sql.gz> | docker exec -i sub2api-postgres psql -U sub2api -d sub2api
gunzip -c <lobehub-postgres.sql.gz> | docker exec -i lobehub-postgres psql -U postgres -d lobehub
```

## 7) 自动化建议

可以用 `cron` 或 `systemd timer` 每日执行：

```bash
0 3 * * * cd /opt/docker-compose && ./backup.sh >> /var/log/docker-compose-backup.log 2>&1
```

## 8) 一键恢复到当前目录（辅助脚本）

如果你要把快照直接覆盖到当前工作目录（会覆盖文件）：

```bash
./restore-to-current.sh --force
```

可选：

```bash
./restore-to-current.sh --snapshot <id|latest> --force
```

脚本执行流程：
- 恢复快照到 `./_restore/<timestamp>`
- 停止所有栈
- 将恢复内容 rsync 覆盖到当前目录
- 启动数据库并导入 SQL（如果存在）
- 启动所有栈并输出状态
