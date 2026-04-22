# Docker Compose Services

当前仓库用于管理多套 Docker Compose 服务。

## 当前服务与状态

以下状态基于 `2026-04-22 UTC` 在当前主机执行控制脚本后的结果：

| Stack | Service | 简要说明 | 当前状态 |
| --- | --- | --- | --- |
| infra | `docker-socket-proxy` | 为 Traefik / Homepage 提供只读 Docker API 代理 | 运行中 |
| infra | `traefik` | 统一入口网关，负责 HTTPS 与路由转发 | 运行中 |
| infra | `vaultwarden` | Bitwarden 兼容密码库服务 | 运行中，健康检查正常 |
| infra | `xray` | Xray 代理服务，通过 Traefik 暴露 `/ray` | 运行中 |
| infra | `projects` | 项目静态页与 Xray 配置展示服务 | 运行中 |
| infra | `homepage` | 内网 / 自托管服务导航页 | 运行中，健康检查正常 |
| cliproxyapi | `cliproxyapi` | OpenAI 兼容代理 API | 运行中 |
| sub2api | `sub2api` | 订阅转换 API 主服务 | 当前 compose 中已注释，未部署 |
| sub2api | `sub2api-postgres` | `sub2api` 的 PostgreSQL 数据库 | 当前 compose 中已注释，未部署 |
| sub2api | `sub2api-redis` | `sub2api` 的 Redis 缓存 / 队列 | 当前 compose 中已注释，未部署 |
| lobehub | `lobehub-postgres` | `LobeHub` 的 PostgreSQL 数据库 | 当前 compose 中已注释，未部署 |
| lobehub | `lobehub` | LobeHub Web 应用 | 当前 compose 中已注释，未部署 |

## 控制脚本

- `./ctrl_infra.sh`: 管理基础设施栈（Traefik、Vaultwarden、Homepage、Projects 等）；`xray` 仍在该 compose 中，但建议日常单独使用 `./ctrl_xray.sh`
- `./ctrl_xray.sh`: 单独管理 `xray` 服务，适合重启、拉取、看日志和状态检查
- `./ctrl_cliproxyapi.sh`: 管理 `cliproxyapi` 栈
- `./ctrl_sub2api.sh`: 管理 `sub2api` 栈
- `./ctrl_lobehub.sh`: 管理 `lobehub` 栈

## 刷新状态

如需重新确认当前运行状态，可执行：

```bash
./ctrl_infra.sh status
./ctrl_xray.sh status
./ctrl_cliproxyapi.sh status
./ctrl_sub2api.sh status
./ctrl_lobehub.sh status
```
