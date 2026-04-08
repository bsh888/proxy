#!/bin/bash
# Xray VLESS+Reality 安装脚本
# 用法: sudo bash setup_xray.sh [端口]
# 默认端口: 443
# 重复执行: 只更新 Xray 二进制，不会重新生成凭据
set -e

PORT=${1:-18443}
INSTALL_DIR="/usr/local/xray"
CONFIG_DIR="/etc/xray"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ "$(id -u)" -ne 0 ] && error "请用 root 运行: sudo bash setup_xray.sh"

ARCH=$(uname -m)
case $ARCH in
  x86_64)  XRAY_ARCH="linux-64" ;;
  aarch64) XRAY_ARCH="linux-arm64-v8a" ;;
  *)       error "不支持的架构: $ARCH" ;;
esac

info "安装依赖..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl unzip jq

info "下载 Xray（获取最新版本）..."
XRAY_VERSION=$(curl -sf https://api.github.com/repos/XTLS/Xray-core/releases/latest \
  | grep '"tag_name"' | cut -d'"' -f4)
[ -z "$XRAY_VERSION" ] && error "无法获取最新版本号，请检查网络"
info "版本: $XRAY_VERSION"
curl -L --retry 3 -o /tmp/xray.zip \
  "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-${XRAY_ARCH}.zip"

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
unzip -o /tmp/xray.zip -d "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/xray"
ln -sf "$INSTALL_DIR/xray" /usr/local/bin/xray

# 已有配置则跳过凭据生成，避免重跑破坏现有连接
if [ -f "$CONFIG_DIR/config.json" ]; then
  warn "检测到已有配置文件，跳过凭据生成（仅更新 Xray 二进制）"
  warn "如需重新生成凭据，请先删除 $CONFIG_DIR/config.json 再运行本脚本"
  systemctl daemon-reload && systemctl restart xray
  info "Xray 已更新并重启"
  echo ""
  echo -e "${CYAN}当前节点参数：${NC}"
  cat "$CONFIG_DIR/node_params.env"
  exit 0
fi

info "首次安装，生成凭据..."
UUID=$(xray uuid)
KEYS=$(xray x25519 2>&1)
PRIVATE_KEY=$(echo "$KEYS" | grep -i 'private' | awk -F':' '{print $2}' | tr -d ' \r\n')
PUBLIC_KEY=$(echo "$KEYS"  | grep -i 'public'  | awk -F':' '{print $2}' | tr -d ' \r\n')
[ -z "$PRIVATE_KEY" ] && error "私钥解析失败，xray x25519 原始输出：\n$KEYS"
[ -z "$PUBLIC_KEY"  ] && error "公钥解析失败，xray x25519 原始输出：\n$KEYS"
SHORT_ID=$(openssl rand -hex 8)

cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${UUID}", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "microsoft.com:443",
        "serverNames": ["microsoft.com", "www.microsoft.com"],
        "privateKey": "${PRIVATE_KEY}",
        "shortIds": ["${SHORT_ID}"]
      }
    },
    "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
  }],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF

cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable xray && systemctl restart xray

# 放行端口（先检查是否已存在，避免重复规则）
iptables  -C INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null \
  || iptables  -I INPUT -p tcp --dport ${PORT} -j ACCEPT
ip6tables -C INPUT -p tcp --dport ${PORT} -j ACCEPT 2>/dev/null \
  || ip6tables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
command -v ufw &>/dev/null && ufw allow ${PORT}/tcp comment "xray" 2>/dev/null || true

SERVER_IP=$(curl -sf https://api.ipify.org 2>/dev/null \
  || curl -sf https://ifconfig.me 2>/dev/null \
  || echo "获取失败，请手动填写服务器IP")

cat > "$CONFIG_DIR/node_params.env" <<EOF
SERVER_IP=${SERVER_IP}
PORT=${PORT}
UUID=${UUID}
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
EOF

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}  安装完成！复制以下参数备用${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "  IP         ${YELLOW}${SERVER_IP}${NC}"
echo -e "  PORT       ${YELLOW}${PORT}${NC}"
echo -e "  UUID       ${YELLOW}${UUID}${NC}"
echo -e "  PUBLIC_KEY ${YELLOW}${PUBLIC_KEY}${NC}"
echo -e "  SHORT_ID   ${YELLOW}${SHORT_ID}${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "${YELLOW}⚠ 还需在 OCI 控制台「安全列表」放行 TCP ${PORT} 端口！${NC}"
