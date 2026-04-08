#!/bin/bash
# 订阅服务器安装脚本 —— 在其中一台 OCI 服务器上运行
# 生成 Clash 订阅文件并通过 HTTP 对外提供访问
# 用法: sudo bash setup_sub_server.sh
# 支持 1 台或多台节点，每台节点同时生成 VLESS 和 Shadowsocks 两条代理
set -e

SUB_PORT=18088
SUB_DIR="/var/www/sub"
TOKEN_FILE="/var/www/sub/.token"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ "$(id -u)" -ne 0 ] && error "请用 root 运行: sudo bash setup_sub_server.sh"

mkdir -p "$SUB_DIR"

# 复用已有 token，避免重跑导致旧订阅 URL 失效
# 如需强制换新 token，先删除再运行：sudo rm /var/www/sub/.token
if [ -f "$TOKEN_FILE" ]; then
  SUB_TOKEN=$(cat "$TOKEN_FILE")
  info "复用已有订阅 token（订阅 URL 不变）"
else
  SUB_TOKEN=$(openssl rand -hex 16)
  echo "$SUB_TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  info "生成新订阅 token"
fi

echo ""
echo -e "${CYAN}=== 请输入节点参数 ===${NC}"
echo -e "（运行 setup_xray.sh 和 add_shadowsocks.sh 后每台服务器都会输出这些参数）"
echo ""

read -rp "节点数量: " NODE_COUNT
[[ ! "$NODE_COUNT" =~ ^[1-9][0-9]*$ ]] && error "节点数量必须是正整数"

# 用下标数组存储各节点参数
declare -a NAMES IPS
declare -a VLESS_PORTS UUIDS PUBKEYS SHORTIDS
declare -a SS_PORTS SS_PASSWORDS

for ((i = 1; i <= NODE_COUNT; i++)); do
  echo ""
  echo -e "${YELLOW}--- 节点 ${i} ---${NC}"
  read -rp "  备注名 (如 OCI-Osaka): " name
  read -rp "  服务器 IP: " ip

  echo -e "  ${CYAN}-- VLESS+Reality 参数 --${NC}"
  read -rp "  端口 (默认18443): " vless_port; vless_port=${vless_port:-18443}
  read -rp "  UUID: " uuid
  read -rp "  公钥 (PUBLIC_KEY): " pubkey
  read -rp "  SHORT_ID: " shortid

  echo -e "  ${CYAN}-- Shadowsocks 参数 --${NC}"
  read -rp "  端口 (默认18444): " ss_port; ss_port=${ss_port:-18444}
  read -rp "  密码 (SS_PASSWORD): " ss_pass

  # 去掉粘贴时可能带入的 \r
  name=$(echo "$name"       | tr -d '\r')
  ip=$(echo "$ip"           | tr -d '\r')
  vless_port=$(echo "$vless_port" | tr -d '\r')
  uuid=$(echo "$uuid"       | tr -d '\r')
  pubkey=$(echo "$pubkey"   | tr -d '\r')
  shortid=$(echo "$shortid" | tr -d '\r')
  ss_port=$(echo "$ss_port" | tr -d '\r')
  ss_pass=$(echo "$ss_pass" | tr -d '\r')

  NAMES+=("$name")
  IPS+=("$ip")
  VLESS_PORTS+=("$vless_port")
  UUIDS+=("$uuid")
  PUBKEYS+=("$pubkey")
  SHORTIDS+=("$shortid")
  SS_PORTS+=("$ss_port")
  SS_PASSWORDS+=("$ss_pass")
done

echo ""
info "生成订阅 YAML..."

YAML_FILE="${SUB_DIR}/clash.yaml"

# 头部（静态）
cat > "$YAML_FILE" <<'HEADER'
# Clash 订阅配置
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
ipv6: false

dns:
  enable: true
  ipv6: false
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
  fallback:
    - 8.8.8.8
    - 1.1.1.1
  fallback-filter:
    geoip: true
    geoip-code: CN

proxies:
HEADER

# 动态写入每个节点的 VLESS 和 SS 两条代理
for ((i = 0; i < NODE_COUNT; i++)); do
  # VLESS+Reality
  cat >> "$YAML_FILE" <<EOF
  - name: "${NAMES[$i]}-VLESS"
    type: vless
    server: ${IPS[$i]}
    port: ${VLESS_PORTS[$i]}
    uuid: ${UUIDS[$i]}
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    reality-opts:
      public-key: ${PUBKEYS[$i]}
      short-id: ${SHORTIDS[$i]}
    servername: microsoft.com
    client-fingerprint: chrome

EOF

  # Shadowsocks
  cat >> "$YAML_FILE" <<EOF
  - name: "${NAMES[$i]}-SS"
    type: ss
    server: ${IPS[$i]}
    port: ${SS_PORTS[$i]}
    cipher: chacha20-ietf-poly1305
    password: "${SS_PASSWORDS[$i]}"
    udp: true

EOF
done

# 构建节点名列表
SS_NODES=""
VLESS_NODES=""
ALL_NODES=""
for ((i = 0; i < NODE_COUNT; i++)); do
  SS_NODES="${SS_NODES}, \"${NAMES[$i]}-SS\""
  VLESS_NODES="${VLESS_NODES}, \"${NAMES[$i]}-VLESS\""
  ALL_NODES="${ALL_NODES}, \"${NAMES[$i]}-SS\", \"${NAMES[$i]}-VLESS\""
done
# 去掉开头 ", "
SS_NODES="${SS_NODES:2}"
VLESS_NODES="${VLESS_NODES:2}"
ALL_NODES="${ALL_NODES:2}"

# 节点选择组：SS 优先（REALITY 当前不可用则手动切）
SELECT_PROXIES="\"⚡ SS自动最优\", \"🔄 SS故障切换\", \"⚡ VLESS自动最优\", ${ALL_NODES}, \"DIRECT\""

cat >> "$YAML_FILE" <<EOF
proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies: [${SELECT_PROXIES}]

  - name: "⚡ SS自动最优"
    type: url-test
    proxies: [${SS_NODES}]
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50

  - name: "🔄 SS故障切换"
    type: fallback
    proxies: [${SS_NODES}]
    url: "http://www.gstatic.com/generate_204"
    interval: 60

  - name: "⚡ VLESS自动最优"
    type: url-test
    proxies: [${VLESS_NODES}]
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    tolerance: 50

rules:
  - DOMAIN-SUFFIX,localhost,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,🚀 节点选择
EOF

info "创建订阅 HTTP 服务 (Python)..."
cat > /usr/local/bin/sub-server.py <<PYEOF
#!/usr/bin/env python3
import http.server

TOKEN = "${SUB_TOKEN}"
SUB_FILE = "${SUB_DIR}/clash.yaml"
PORT = ${SUB_PORT}

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != f"/{TOKEN}/clash.yaml":
            self.send_response(404); self.end_headers()
            return
        with open(SUB_FILE, 'rb') as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Disposition", "attachment; filename=clash.yaml")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, fmt, *args):
        pass

print(f"订阅服务运行在 :{PORT}", flush=True)
http.server.HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
PYEOF
chmod +x /usr/local/bin/sub-server.py

cat > /etc/systemd/system/sub-server.service <<EOF
[Unit]
Description=Clash Subscription Server
After=network.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/sub-server.py
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload && systemctl enable sub-server && systemctl restart sub-server

# 放行订阅端口（先检查是否已存在，避免重复规则）
iptables  -C INPUT -p tcp --dport ${SUB_PORT} -j ACCEPT 2>/dev/null \
  || iptables  -I INPUT -p tcp --dport ${SUB_PORT} -j ACCEPT
ip6tables -C INPUT -p tcp --dport ${SUB_PORT} -j ACCEPT 2>/dev/null \
  || ip6tables -I INPUT -p tcp --dport ${SUB_PORT} -j ACCEPT
command -v ufw &>/dev/null && ufw allow ${SUB_PORT}/tcp 2>/dev/null || true

SERVER_IP=$(curl -sf https://api.ipify.org 2>/dev/null \
  || curl -sf https://ifconfig.me 2>/dev/null \
  || echo "获取失败，请手动填写服务器IP")
SUB_URL="http://${SERVER_IP}:${SUB_PORT}/${SUB_TOKEN}/clash.yaml"

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${GREEN}  订阅服务部署完成！${NC}"
echo -e "${CYAN}============================================================${NC}"
echo -e "  订阅 URL:"
echo -e "  ${YELLOW}${SUB_URL}${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "在 Clash Verge 中:"
echo -e "  配置 → 新建订阅 → 粘贴上方 URL → 确认"
echo ""
echo -e "${YELLOW}⚠ 还需在 OCI 控制台「安全列表」放行 TCP ${SUB_PORT} 端口！${NC}"
echo ""
echo -e "如果订阅 URL 泄露，执行以下命令立即更换 token:"
echo -e "  ${CYAN}sudo rm ${TOKEN_FILE} && sudo bash setup_sub_server.sh${NC}"

echo "$SUB_URL" > "${SUB_DIR}/sub_url.txt"
