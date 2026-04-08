#!/bin/bash
# 在现有 Xray 配置中追加 Shadowsocks inbound
# 用法: sudo bash add_shadowsocks.sh [端口]
# 默认端口: 18444
set -e

SS_PORT=${1:-18444}
CONFIG_DIR="/etc/xray"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ "$(id -u)" -ne 0 ] && error "请用 root 运行: sudo bash add_shadowsocks.sh"
[ ! -f "$CONFIG_DIR/config.json" ] && error "未找到 Xray 配置，请先运行 setup_xray.sh"

# 已有 SS inbound 则直接显示参数
if jq -e '.inbounds[] | select(.protocol == "shadowsocks")' "$CONFIG_DIR/config.json" > /dev/null 2>&1; then
  warn "已存在 Shadowsocks inbound，跳过生成（显示现有参数）"
  SS_PASS=$(jq -r '.inbounds[] | select(.protocol == "shadowsocks") | .settings.password' "$CONFIG_DIR/config.json")
  SS_PORT=$(jq -r '.inbounds[] | select(.protocol == "shadowsocks") | .port' "$CONFIG_DIR/config.json")
  SERVER_IP=$(curl -sf https://api.ipify.org 2>/dev/null || curl -sf https://ifconfig.me 2>/dev/null || echo "获取失败")
  echo ""
  echo -e "${CYAN}============================================================${NC}"
  echo -e "${GREEN}  当前 Shadowsocks 参数${NC}"
  echo -e "${CYAN}============================================================${NC}"
  echo -e "  IP       ${YELLOW}${SERVER_IP}${NC}"
  echo -e "  PORT     ${YELLOW}${SS_PORT}${NC}"
  echo -e "  PASSWORD ${YELLOW}${SS_PASS}${NC}"
  echo -e "  CIPHER   ${YELLOW}chacha20-ietf-poly1305${NC}"
  echo -e "${CYAN}============================================================${NC}"
  exit 0
fi

info "生成 Shadowsocks 密码..."
SS_PASS=$(openssl rand -base64 16)

info "更新 Xray 配置，添加 Shadowsocks inbound（端口 ${SS_PORT}）..."
jq --argjson port "$SS_PORT" --arg pass "$SS_PASS" '
  .inbounds += [{
    "port": $port,
    "protocol": "shadowsocks",
    "settings": {
      "method": "chacha20-ietf-poly1305",
      "password": $pass,
      "network": "tcp,udp"
    }
  }]
' "$CONFIG_DIR/config.json" > /tmp/xray_config_new.json
mv /tmp/xray_config_new.json "$CONFIG_DIR/config.json"

# 更新 node_params.env（去掉旧 SS_ 行再追加）
if [ -f "$CONFIG_DIR/node_params.env" ]; then
  grep -v '^SS_' "$CONFIG_DIR/node_params.env" > /tmp/params_clean.env || true
  mv /tmp/params_clean.env "$CONFIG_DIR/node_params.env"
fi
echo "SS_PORT=${SS_PORT}" >> "$CONFIG_DIR/node_params.env"
echo "SS_PASSWORD=${SS_PASS}" >> "$CONFIG_DIR/node_params.env"

systemctl restart xray
info "Xray 已重启"

# 放行端口（TCP + UDP）
iptables  -C INPUT -p tcp --dport ${SS_PORT} -j ACCEPT 2>/dev/null || iptables  -I INPUT -p tcp --dport ${SS_PORT} -j ACCEPT
ip6tables -C INPUT -p tcp --dport ${SS_PORT} -j ACCEPT 2>/dev/null || ip6tables -I INPUT -p tcp --dport ${SS_PORT} -j ACCEPT
iptables  -C INPUT -p udp --dport ${SS_PORT} -j ACCEPT 2>/dev/null || iptables  -I INPUT -p udp --dport ${SS_PORT} -j ACCEPT
ip6tables -C INPUT -p udp --dport ${SS_PORT} -j ACCEPT 2>/dev/null || ip6tables -I INPUT -p udp --dport ${SS_PORT} -j ACCEPT
command -v ufw &>/dev/null && ufw allow ${SS_PORT}/tcp comment "xray-ss" 2>/dev/null || true
command -v ufw &>/dev/null && ufw allow ${SS_PORT}/udp comment "xray-ss" 2>/dev/null || true

SERVER_IP=$(curl -sf https://api.ipify.org 2>/dev/null || curl -sf https://ifconfig.me 2>/dev/null || echo "获取失败，请手动填写服务器IP")

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}  Shadowsocks 添加完成！复制以下参数备用${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "  IP       ${YELLOW}${SERVER_IP}${NC}"
echo -e "  PORT     ${YELLOW}${SS_PORT}${NC}"
echo -e "  PASSWORD ${YELLOW}${SS_PASS}${NC}"
echo -e "  CIPHER   ${YELLOW}chacha20-ietf-poly1305${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "${YELLOW}⚠ 还需在 OCI 控制台「安全列表」放行 TCP+UDP ${SS_PORT} 端口！${NC}"
