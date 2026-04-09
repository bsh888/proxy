#!/bin/bash
# 卸载脚本 —— 清除 Xray 代理服务和订阅服务
# 用法: sudo bash uninstall.sh
# 自动检测订阅服务是否存在，存在则一并清理
set -e

INSTALL_DIR="/usr/local/xray"
CONFIG_DIR="/etc/xray"
SUB_DIR="/var/www/sub"
XRAY_PORTS=(18444)   # SS 端口
SUB_PORT=18088

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ "$(id -u)" -ne 0 ] && error "请用 root 运行: sudo bash uninstall.sh"

# 自动检测是否安装了订阅服务
REMOVE_SUB=false
if [ -f /etc/systemd/system/sub-server.service ] || [ -f /usr/local/bin/sub-server.py ]; then
  REMOVE_SUB=true
fi

echo ""
echo -e "${YELLOW}以下内容将被删除：${NC}"
echo -e "  • Xray 服务（systemd）"
echo -e "  • Xray 二进制: ${INSTALL_DIR}、/usr/local/bin/xray"
echo -e "  • Xray 配置:  ${CONFIG_DIR}"
echo -e "  • iptables 规则: 端口 ${XRAY_PORTS[*]}"
if $REMOVE_SUB; then
  echo -e "  • 订阅服务（systemd）"
  echo -e "  • 订阅脚本: /usr/local/bin/sub-server.py"
  echo -e "  • 订阅文件: ${SUB_DIR}"
  echo -e "  • iptables 规则: 端口 ${SUB_PORT}"
fi
echo ""
read -rp "确认卸载？[y/N] " confirm
[[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "已取消。"; exit 0; }

# ── 卸载 Xray ──────────────────────────────────────────────────
info "停止并禁用 Xray 服务..."
if systemctl is-active --quiet xray 2>/dev/null; then
  systemctl stop xray
fi
if systemctl is-enabled --quiet xray 2>/dev/null; then
  systemctl disable xray
fi
rm -f /etc/systemd/system/xray.service

info "删除 Xray 文件..."
rm -rf "$INSTALL_DIR"
rm -f /usr/local/bin/xray
rm -rf "$CONFIG_DIR"

info "清理 iptables 规则..."
for port in "${XRAY_PORTS[@]}"; do
  for proto in tcp udp; do
    iptables  -D INPUT -p $proto --dport $port -j ACCEPT 2>/dev/null || true
    ip6tables -D INPUT -p $proto --dport $port -j ACCEPT 2>/dev/null || true
  done
  command -v ufw &>/dev/null && ufw delete allow $port/tcp 2>/dev/null || true
  command -v ufw &>/dev/null && ufw delete allow $port/udp 2>/dev/null || true
done

# ── 卸载订阅服务（可选）────────────────────────────────────────
if $REMOVE_SUB; then
  info "停止并禁用订阅服务..."
  if systemctl is-active --quiet sub-server 2>/dev/null; then
    systemctl stop sub-server
  fi
  if systemctl is-enabled --quiet sub-server 2>/dev/null; then
    systemctl disable sub-server
  fi
  rm -f /etc/systemd/system/sub-server.service
  rm -f /usr/local/bin/sub-server.py
  rm -rf "$SUB_DIR"

  info "清理订阅服务 iptables 规则..."
  iptables  -D INPUT -p tcp --dport $SUB_PORT -j ACCEPT 2>/dev/null || true
  ip6tables -D INPUT -p tcp --dport $SUB_PORT -j ACCEPT 2>/dev/null || true
  command -v ufw &>/dev/null && ufw delete allow $SUB_PORT/tcp 2>/dev/null || true
fi

systemctl daemon-reload
info "卸载完成。"
echo ""
echo -e "${YELLOW}提示：OCI 控制台「安全列表」中的入站规则需手动删除。${NC}"
