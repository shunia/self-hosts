# Xray + Traefik 安装说明

## 目标

在当前这个 `docker-compose` 仓库里新增一个 `Xray` 服务，对外暴露为：

- 域名：`xray.260055.xyz`
- 协议：`VLESS + XHTTP`
- 传输层：`HTTP/2`
- TLS：由现有 `Traefik` 终止
- Xray 监听：容器内 `0.0.0.0:10000`
- Traefik 对接方式：`docker provider + labels`

这个仓库里的 `Traefik` 是 Docker 容器，且当前只启用了 `docker provider`，没有启用 `file provider`。因此这里不采用宿主机 `systemd + 127.0.0.1:10000 + /etc/traefik/dynamic/*.yml` 的做法。

官方资料里，Xray 已将 `XHTTP` 作为新的主力传输层，`WebSocket` 已不再推荐继续新部署。当前改造方式是：客户端到 Traefik 走 `HTTPS + H2`，Traefik 到 Xray 后端走 `h2c`。

## 当前实现

- `Xray` 服务定义在 `docker-compose.yml`
- Xray 配置文件在 `xray-config/config.json`
- Traefik 证书解析器沿用现有的 `myresolver`
- 域名通过 `.env` 中的 `XRAY_DOMAIN` 控制
- Traefik 通过 `traefik.http.services.xray.loadbalancer.server.scheme=h2c` 与 Xray 后端通信

默认参数：

- 域名：`xray.260055.xyz`
- XHTTP 路径：`/ray/`
- UUID：`248c20b6-83a8-4770-845b-ac46e992400c`

如需修改 UUID 或路径，直接编辑 `xray-config/config.json`。

## 安装前提

- `xray.260055.xyz` 已添加 DNS 解析并指向当前机器
- 现有 `Traefik` 栈可正常签发证书
- `80/443` 仍由当前仓库里的 `traefik` 容器占用

## 已落地的文件

`docker-compose.yml` 中新增：

```yaml
  xray:
    image: "ghcr.io/xtls/xray-core:26.4.17@sha256:1880a26aee27e82d779b9632a88d5256403e8b33d9abffa1c7920f2fffb73bc3"
    container_name: "xray"
    restart: unless-stopped
    command:
      - "run"
      - "-config"
      - "/etc/xray/config.json"
    volumes:
      - "./xray-config/config.json:/etc/xray/config.json:ro"
    networks:
      - traefik_proxy
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik_proxy"
      - "traefik.http.routers.xray.rule=Host(`${XRAY_DOMAIN}`) && (Path(`/ray`) || PathPrefix(`/ray/`))"
      - "traefik.http.routers.xray.entrypoints=websecure"
      - "traefik.http.routers.xray.tls.certresolver=myresolver"
      - "traefik.http.services.xray.loadbalancer.server.port=10000"
      - "traefik.http.services.xray.loadbalancer.server.scheme=h2c"
```

`xray-config/config.json`：

```json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 10000,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "248c20b6-83a8-4770-845b-ac46e992400c"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "path": "/ray/"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
```

## 启用步骤

先校验 Compose：

```bash
./ctrl_infra.sh config
```

启动或更新 `xray`：

```bash
docker compose -f docker-compose.yml up -d xray
```

查看状态：

```bash
./ctrl_infra.sh status
```

查看日志：

```bash
docker compose -f docker-compose.yml logs -f xray
```

如果你改过 `XRAY_DOMAIN`、Traefik 标签或 `xray-config/config.json`，可直接重建：

```bash
docker compose -f docker-compose.yml up -d --force-recreate xray
```

## 客户端参数

- 地址：`xray.260055.xyz`
- 端口：`443`
- 用户 ID：`248c20b6-83a8-4770-845b-ac46e992400c`
- 加密：`none`
- 传输：`xhttp`
- 路径：`/ray/`
- TLS：开启
- SNI：`xray.260055.xyz`
- ALPN：`h2`
- `mode`：建议 `auto`

按 Xray 官方说明，客户端在 `TLS + H2` 下，`XHTTP` 默认会走 `stream-up` 行为；服务端这里保持最简配置，只填 `path`，兼容性更稳。

## 验收

检查配置是否通过：

```bash
./ctrl_infra.sh config
```

检查容器是否启动：

```bash
docker compose -f docker-compose.yml ps xray
```

检查 Xray 日志：

```bash
docker compose -f docker-compose.yml logs --tail=100 xray
```

检查 Traefik 是否已发现路由：

```bash
./ctrl_infra.sh logs traefik
```

如果客户端无法连通，优先检查：

- `XRAY_DOMAIN` 的 DNS 是否已生效
- `xray-config/config.json` 中的 UUID 与客户端是否一致
- 路径是否仍为 `/ray/`
- 客户端传输是否已改为 `xhttp`
- 客户端 TLS ALPN 是否已设为 `h2`
- `traefik` 和 `xray` 是否都在 `traefik_proxy` 网络中
