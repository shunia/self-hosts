#!/bin/bash

# =============================================================================
#         Traefik + Vaultwarden 自动化部署脚本
# =============================================================================
#
# 这个脚本将自动化在Ubuntu 24服务器上部署 Traefik 和 Vaultwarden
# 的完整流程。
#
# 它将执行以下操作:
# 1. 检查Sudo权限。
# 2. 安装必要的依赖 (Docker, Docker Compose, apache2-utils, openssl)。
# 3. 配置防火墙 (UFW)。
# 4. 提示用户输入所有必需的变量 (域名, 邮箱等)。
# 5. 生成 Traefik 仪表板的 htpasswd。
# 6. 生成 Vaultwarden 的 ADMIN_TOKEN。
# 7. 创建目录结构。
# 8. 写入 'traefik.yml', 'acme.json', 和 'docker-compose.yml'。
# 9. 启动 Docker Compose 服务。
#

# --- 脚本安全设置 ---
# -e: 如果任何命令失败，立即退出
# -u: 将未设置的变量视为错误
# -o pipefail: 管道中的任何命令失败，整个管道都失败
set -euo pipefail

# --- 颜色定义 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 助手函数 ---
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# =============================================================================
# 1. 系统和依赖检查
# =============================================================================

log_info "开始 Traefik + Vaultwarden 部署..."

# 检查是否以root或sudo权限运行
if [ "$EUID" -ne 0 ]; then
  log_error "请使用 sudo 权限运行此脚本 (e.g., 'sudo bash $0')"
fi

# 检查OS是否为Ubuntu 24 (可选，但推荐)
if ! grep -q "VERSION_ID=\"24.04\"" /etc/os-release; then
    log_warn "此脚本专为 Ubuntu 24.04 设计。您的系统版本不同，可能会遇到问题。"
    read -p "要继续吗? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        log_error "部署中止。"
    fi
fi

log_info "正在安装和更新依赖..."

# 安装依赖
apt-get update > /dev/null
apt-get install -y curl apache2-utils openssl ufw > /dev/null

# 安装 Docker
if ! command -v docker &> /dev/null; then
    log_info "未检测到 Docker，正在使用官方脚本安装..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh > /dev/null
    rm get-docker.sh
    # 将当前sudo用户添加到docker组
    usermod -aG docker "$SUDO_USER"
    log_warn "已将用户 '$SUDO_USER' 添加到 'docker' 组。"
    log_warn "您可能需要注销并重新登录，或运行 'newgrp docker' 才能以非root用户身份运行docker。"
else
    log_info "Docker 已安装。"
fi

# 检查 Docker Compose (v2)
if ! docker compose version &> /dev/null; then
    log_error "Docker Compose V2 未安装成功。请检查您的 Docker 安装。"
fi

log_info "依赖安装完毕。"

# =============================================================================
# 2. 配置防火墙 (UFW)
# =============================================================================

log_info "正在配置防火墙 (UFW)..."
ufw allow 80/tcp comment 'Traefik HTTP' > /dev/null
ufw allow 443/tcp comment 'Traefik HTTPS' > /dev/null
# 仅当UFW未启用时才启用它
if ! ufw status | grep -q "Status: active"; then
    echo "y" | ufw enable > /dev/null
fi
log_info "防火墙已允许端口 80 和 443。"

# =============================================================================
# 3. 获取用户输入
# =============================================================================

log_info "请输入必要的配置信息："

# 定义项目目录
PROJECT_DIR="/opt/traefik-vaultwarden"

# 获取Vaultwarden域名
read -p "请输入您的 Vaultwarden 域名 (e.g., vault.your-domain.com): " VW_DOMAIN
if [ -z "$VW_DOMAIN" ]; then
    log_error "Vaultwarden 域名不能为空。"
fi

# 获取Traefik仪表板域名
read -p "请输入您的 Traefik 仪表板域名 (e.g., traefik.your-domain.com): " TRAEFIK_DOMAIN
if [ -z "$TRAEFIK_DOMAIN" ]; then
    log_error "Traefik 域名不能为空。"
fi

# 获取Let's Encrypt邮箱
read -p "请输入您的 Let's Encrypt 邮箱 (用于SSL证书提醒): " LE_EMAIL
if [ -z "$LE_EMAIL" ]; then
    log_error "邮箱不能为空。"
fi

# 获取Traefik仪表板管理员用户名
read -p "请输入 Traefik 仪表板的管理员用户名 (e.g., admin): " TRAEFIK_USER
if [ -z "$TRAEFIK_USER" ]; then
    log_error "Traefik 用户名不能为空。"
fi

# 获取Traefik仪表板管理员密码
read -sp "请输入 Traefik 仪表板的管理员密码 (输入时隐藏): " TRAEFIK_PASS
echo
if [ -z "$TRAEFIK_PASS" ]; then
    log_error "Traefik 密码不能为空。"
fi

# =============================================================================
# 4. 生成动态数据
# =============================================================================

log_info "正在生成安全凭证..."

# 1. 生成 Vaultwarden Admin Token
VW_ADMIN_TOKEN=$(openssl rand -base64 48)

# 2. 生成 Htpasswd
RAW_HASH=$(htpasswd -nb "$TRAEFIK_USER" "$TRAEFIK_PASS")
# 为 Docker Compose 的 YML 文件转义 '$' 字符
ESCAPED_HASH=$(echo "$RAW_HASH" | sed -e 's/\$/\$\$/g')

log_info "凭证生成完毕。"

# =============================================================================
# 5. 创建目录和配置文件
# =============================================================================

log_info "正在创建项目目录于 $PROJECT_DIR ..."
mkdir -p "$PROJECT_DIR/traefik-data"
mkdir -p "$PROJECT_DIR/vw-data"

# --- 写入 traefik.yml ---
log_info "正在创建 traefik.yml..."
cat <<EOF > "$PROJECT_DIR/traefik-data/traefik.yml"
global:
  checkNewVersion: true
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https

  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik_proxy

certificatesResolvers:
  myresolver:
    acme:
      email: "$LE_EMAIL"
      storage: "/etc/traefik/acme.json"
      httpChallenge:
        entryPoint: web
EOF

# --- 创建 acme.json 并设置权限 ---
log_info "正在创建 acme.json 并设置权限..."
touch "$PROJECT_DIR/traefik-data/acme.json"
chmod 600 "$PROJECT_DIR/traefik-data/acme.json"

# --- 写入 docker-compose.yml ---
log_info "正在创建 docker-compose.yml..."
cat <<EOF > "$PROJECT_DIR/docker-compose.yml"
version: '3.8'

services:
  traefik:
    image: "traefik:v3.0"
    container_name: "traefik"
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./traefik-data/traefik.yml:/etc/traefik/traefik.yml:ro"
      - "./traefik-data/acme.json:/etc/traefik/acme.json"
    networks:
      - traefik_proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-dashboard.rule=Host(\`$TRAEFIK_DOMAIN\`)"
      - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
      - "traefik.http.routers.traefik-dashboard.tls.certresolver=myresolver"
      - "traefik.http.routers.traefik-dashboard.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=${ESCAPED_HASH}"

  vaultwarden:
    image: "vaultwarden/server:latest"
    container_name: "vaultwarden"
    restart: unless-stopped
    volumes:
      - "./vw-data:/data"
    environment:
      WEBSOCKET_ENABLED: "true"
      ADMIN_TOKEN: "${VW_ADMIN_TOKEN}"
    networks:
      - traefik_proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.vaultwarden-http.rule=Host(\`$VW_DOMAIN\`)"
      - "traefik.http.routers.vaultwarden-http.entrypoints=websecure"
      - "traefik.http.routers.vaultwarden-http.service=vaultwarden-svc"
      - "traefik.http.routers.vaultwarden-http.tls.certresolver=myresolver"
      
      - "traefik.http.routers.vaultwarden-ws.rule=Host(\`$VW_DOMAIN\`) && Path(\`/notifications/hub\`)"
      - "traefik.http.routers.vaultwarden-ws.entrypoints=websecure"
      - "traefik.http.routers.vaultwarden-ws.service=vaultwarden-ws-svc"
      - "traefik.http.routers.vaultwarden-ws.tls.certresolver=myresolver"

      - "traefik.http.services.vaultwarden-svc.loadbalancer.server.port=80"
      - "traefik.http.services.vaultwarden-ws-svc.loadbalancer.server.port=3012"

networks:
  traefik_proxy:
    name: traefik_proxy
EOF

log_info "所有配置文件已在 $PROJECT_DIR 中创建。"

# =============================================================================
# 6. 启动服务
# =============================================================================

log_info "正在使用 Docker Compose 启动服务... (这可能需要几分钟)"

# 切换到项目目录
cd "$PROJECT_DIR"

# 启动服务
if docker compose up -d; then
    log_info "服务启动成功！"
else
    log_error "Docker Compose 启动失败。请运行 'cd $PROJECT_DIR && docker compose logs' 查看错误。"
fi

# =============================================================================
# 7. 完成
# =============================================================================

echo
log_success "================= 部署完成 ================="
log_info "您的服务正在运行中。"
echo
log_info "请确保您的DNS A记录已正确设置："
log_info "  - $VW_DOMAIN -> (您的服务器IP)"
log_info "  - $TRAEFIK_DOMAIN -> (您的服务器IP)"
echo
log_info "您可以访问以下地址:"
echo -e "  - ${GREEN}Vaultwarden:${NC} https://$VW_DOMAIN"
echo -e "  - ${GREEN}Traefik 仪表盘:${NC} https://$TRAEFIK_DOMAIN"
echo -e "    (用户: $TRAEFIK_USER, 密码: [您设置的密码])"
echo
log_warn "!!! 请务必保存您的 Vaultwarden 管理员令牌 !!!"
log_warn "这是访问 /admin 页面所必需的："
echo -e "${YELLOW}ADMIN_TOKEN: $VW_ADMIN_TOKEN${NC}"
echo
log_info "要查看服务日志, 请运行:"
log_info "cd $PROJECT_DIR && docker compose logs -f"
echo
log_success "================================================="