#!/bin/bash
# 凭据轮换脚本 —— 怀疑订阅或 UUID 泄露时执行
# 在两台服务器上各跑一次，然后在订阅服务器上重新跑本脚本更新订阅文件
# 用法: sudo bash rotate_credentials.sh

set -e
CONFIG_DIR="/etc/xray"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ "$(id -u)" -ne 0 ] && error "请用 root 运行: sudo bash rotate_credentials.sh"
[ ! -f "$CONFIG_DIR/config.json" ] && error "未找到 Xray 配置，请先运行 setup_xray.sh"

info "生成新的 UUID 和密钥..."
NEW_UUID=$(xray uuid)
NEW_KEYS=$(xray x25519 2>&1)
NEW_PRIVATE=$(echo "$NEW_KEYS" | grep -i 'private' | awk -F':' '{print $2}' | tr -d ' \r\n')
NEW_PUBLIC=$(echo "$NEW_KEYS"  | grep -i 'public'  | awk -F':' '{print $2}' | tr -d ' \r\n')
[ -z "$NEW_PRIVATE" ] && error "私钥解析失败，xray x25519 原始输出：\n$NEW_KEYS"
[ -z "$NEW_PUBLIC"  ] && error "公钥解析失败，xray x25519 原始输出：\n$NEW_KEYS"
NEW_SHORTID=$(openssl rand -hex 8)

# 读取旧端口
OLD_PORT=$(grep -o '"port": [0-9]*' "$CONFIG_DIR/config.json" | awk '{print $2}')

info "更新 Xray 配置..."
cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": ${OLD_PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${NEW_UUID}", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "microsoft.com:443",
        "serverNames": ["microsoft.com", "www.microsoft.com"],
        "privateKey": "${NEW_PRIVATE}",
        "shortIds": ["${NEW_SHORTID}"]
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

systemctl restart xray

SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me)

# 更新参数文件
cat > "$CONFIG_DIR/node_params.env" <<EOF
SERVER_IP=${SERVER_IP}
PORT=${OLD_PORT}
UUID=${NEW_UUID}
PUBLIC_KEY=${NEW_PUBLIC}
SHORT_ID=${NEW_SHORTID}
EOF

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}  凭据已更新！记录新参数${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "  IP         ${YELLOW}${SERVER_IP}${NC}"
echo -e "  PORT       ${YELLOW}${OLD_PORT}${NC}"
echo -e "  UUID       ${YELLOW}${NEW_UUID}${NC}"
echo -e "  PUBLIC_KEY ${YELLOW}${NEW_PUBLIC}${NC}"
echo -e "  SHORT_ID   ${YELLOW}${NEW_SHORTID}${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "${YELLOW}下一步：${NC}"
echo -e "  1. 在另一台服务器上也执行 rotate_credentials.sh"
echo -e "  2. 在订阅服务器上重新执行 setup_sub_server.sh 更新订阅文件"
echo -e "  3. 在 Clash Verge 中点击订阅的「更新」按钮"
