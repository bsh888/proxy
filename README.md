# OCI 双节点代理部署说明

## 架构概览

```
你的电脑 (Clash Verge)
    │
    ├─── 订阅更新 (HTTP) ───→ Server1:18088  ← Python 服务，提供 clash.yaml
    │
    ├─── 代理流量 ──────────→ Server1:18443/18444  ← Xray VLESS+Reality / Shadowsocks
    └─── 代理流量 ──────────→ Server2:18443/18444  ← Xray VLESS+Reality / Shadowsocks
```

**同时支持两种协议：**

| 协议 | 端口 | 特点 |
|------|------|------|
| VLESS + XTLS-Reality | 18443 | 流量伪装成正常 HTTPS，隐蔽性强 |
| Shadowsocks (chacha20) | 18444 | 简单可靠，不依赖 TLS 握手，国内链路稳定 |

订阅中同时包含两种协议各两个节点，共 4 条代理。Clash Verge 默认使用 SS 自动最优分组。

---

## 脚本说明

| 脚本 | 用途 | 在哪里运行 |
|------|------|-----------|
| `setup_xray.sh` | 安装 Xray，生成 VLESS+Reality 配置 | Server1、Server2 各一次 |
| `add_shadowsocks.sh` | 在现有 Xray 中追加 Shadowsocks inbound | Server1、Server2 各一次 |
| `setup_sub_server.sh` | 部署订阅 HTTP 服务，生成 clash.yaml | 只在 Server1 |
| `rotate_credentials.sh` | 凭据泄露时轮换 UUID/密钥 | Server1、Server2 各一次 |
| `uninstall.sh` | 卸载全部服务 | 需要清理的服务器上 |

---

## 部署步骤

### 第零步：OCI 控制台放行端口

**在开始部署前，先把端口打开**，否则后续验证无法通过。

**导航路径：**
1. 登录 [cloud.oracle.com](https://cloud.oracle.com)，点左上角 **≡ 菜单**
2. **网络 (Networking)** → **虚拟云网络 (Virtual Cloud Networks)**
3. 点击你的 VCN 名称
4. 左侧「资源」栏 → **安全列表 (Security Lists)** → **Default Security List for...**
5. 点击 **添加入站规则 (Add Ingress Rules)**

**每条规则填写方式：**

| 字段 | 值 |
|------|----|
| 无状态 | 不勾 |
| 源类型 | CIDR |
| 源 CIDR | `0.0.0.0/0` |
| 源端口范围 | 留空 |
| 目标端口范围 | 填对应端口 |

**需要添加的规则（共 5 条）：**

| 在哪台添加 | IP 协议 | 目标端口 | 说明 |
|-----------|---------|---------|------|
| Server1、Server2 都加 | TCP | `18443` | Xray VLESS+Reality |
| Server1、Server2 都加 | TCP | `18444` | Xray Shadowsocks |
| Server1、Server2 都加 | UDP | `18444` | Xray Shadowsocks UDP |
| 只在 Server1 加 | TCP | `18088` | 订阅服务 |

> 如果两台服务器在不同区域，VCN 是分开的，需要分别进各自的 VCN 操作。

---

### 第一步：上传脚本到两台服务器

在本机执行（把 `<Server1_IP>` 和 `<Server2_IP>` 替换成实际 IP）：

```bash
# 上传到 Server1
scp setup_xray.sh add_shadowsocks.sh setup_sub_server.sh uninstall.sh ubuntu@<Server1_IP>:~/

# 上传到 Server2
scp setup_xray.sh add_shadowsocks.sh uninstall.sh ubuntu@<Server2_IP>:~/
```

---

### 第二步：Server1 安装（SSH 进入 Server1）

```bash
ssh ubuntu@<Server1_IP>
```

**2.1 安装 Xray（VLESS+Reality）**

```bash
sudo bash ~/setup_xray.sh
```

输出示例，**记下这些参数**：

```
============================================================
  安装完成！复制以下参数备用
============================================================
  IP         1.2.3.4
  PORT       18443
  UUID       xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  PUBLIC_KEY xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
  SHORT_ID   a1b2c3d4e5f6a7b8
============================================================
```

**2.2 添加 Shadowsocks**

```bash
sudo bash ~/add_shadowsocks.sh
```

输出示例，**记下 PASSWORD**：

```
============================================================
  Shadowsocks 添加完成！复制以下参数备用
============================================================
  IP       1.2.3.4
  PORT     18444
  PASSWORD xxxxxxxxxxxxxxxxxxxxxxxx
  CIPHER   chacha20-ietf-poly1305
============================================================
```

**2.3 验证服务**

```bash
systemctl status xray   # 应显示 active (running)
```

> 参数随时可查：`cat /etc/xray/node_params.env`

---

### 第三步：Server2 安装（SSH 进入 Server2）

```bash
ssh ubuntu@<Server2_IP>
```

步骤与 Server2 完全相同，依次执行：

```bash
sudo bash ~/setup_xray.sh
sudo bash ~/add_shadowsocks.sh
systemctl status xray
```

同样记录输出的全部参数。

---

### 第四步：Server1 部署订阅服务

回到 Server1：

```bash
ssh ubuntu@<Server1_IP>
sudo bash ~/setup_sub_server.sh
```

按提示依次输入**两台服务器**的参数（从上面记录的内容粘贴）：

```
=== 请输入节点参数 ===

节点数量: 2

--- 节点 1 ---
  备注名 (如 OCI-Osaka): OCI-Osaka-1
  服务器 IP: <Server1_IP>
  -- VLESS+Reality 参数 --
  端口 (默认18443): 18443
  UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  公钥 (PUBLIC_KEY): xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=
  SHORT_ID: a1b2c3d4e5f6a7b8
  -- Shadowsocks 参数 --
  端口 (默认18444): 18444
  密码 (SS_PASSWORD): xxxxxxxxxxxxxxxxxxxxxxxx

--- 节点 2 ---
  备注名 (如 OCI-Osaka): OCI-Osaka-2
  服务器 IP: <Server2_IP>
  -- VLESS+Reality 参数 --
  端口 (默认18443): 18443
  UUID: yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
  公钥 (PUBLIC_KEY): yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy=
  SHORT_ID: b2c3d4e5f6a7b8c9
  -- Shadowsocks 参数 --
  端口 (默认18444): 18444
  密码 (SS_PASSWORD): yyyyyyyyyyyyyyyyyyyyyyyy
```

完成后输出订阅 URL：

```
============================================================
  订阅服务部署完成！
============================================================
  订阅 URL:
  http://1.2.3.4:18088/a3f8c2e1d4b7xxxx/clash.yaml
============================================================
```

订阅 URL 也保存在 `/var/www/sub/sub_url.txt`，可随时查看：
```bash
cat /var/www/sub/sub_url.txt
```

**验证订阅服务可访问**（在本机执行）：
```bash
curl http://<Server1_IP>:18088/<token>/clash.yaml
```

能看到 YAML 内容表示正常。

---

### 第五步：Clash Verge 添加订阅

1. 打开 **Clash Verge**
2. 左侧点击 **配置 (Profiles)**
3. 右上角点 **新建**
4. 类型选 **远程 (Remote)**
5. 粘贴上一步得到的订阅 URL
6. 点 **保存**，等待下载完成
7. 点击配置卡片的 **激活** 按钮

**验证节点：** 左侧点击 **代理 (Proxies)**，在 **⚡ SS自动最优** 分组中能看到 `OCI-Osaka-1-SS` 和 `OCI-Osaka-2-SS`，测速有延迟数值即表示连通。

---

## 重新部署

如果需要完全重装（换服务器、系统重装后、排查问题等），按以下流程操作。

### 第一步：卸载旧安装

**在 Server1 上执行**（自动清理 Xray + 订阅服务）：
```bash
sudo bash ~/uninstall.sh
```

**在 Server2 上执行**（只清理 Xray）：
```bash
sudo bash ~/uninstall.sh
```

脚本会自动检测当前服务器安装了哪些服务（Xray / 订阅服务），并一并清理，包括 systemd 服务、二进制文件、配置文件、iptables 规则。

> OCI 控制台「安全列表」中的入站规则无法通过脚本删除，如需清理需手动操作，但通常保留不影响重新部署。

### 第二步：重新安装

卸载完成后，从 **[第二步](#第二步server1-安装ssh-进入-server1)** 开始重新执行即可。脚本均为幂等设计，重复执行不会产生冲突。

---

## 卸载

在需要清理的服务器上执行（两台都要分别跑）：

```bash
sudo bash ~/uninstall.sh
```

脚本会自动检测并清理：
- Xray 服务、二进制、配置文件、iptables 规则（18443、18444 TCP+UDP）
- 如果是 Server1（检测到订阅服务），同时清理订阅服务、文件、iptables 规则（18088）

> OCI 控制台「安全列表」中的入站规则需手动删除。

---

## 日常维护

### 查看服务状态

```bash
# Xray 代理服务（两台都有）
systemctl status xray

# 订阅服务（仅 Server1）
systemctl status sub-server
```

### 重启服务

```bash
systemctl restart xray
systemctl restart sub-server
```

### 查看节点参数

```bash
cat /etc/xray/node_params.env
```

### 查看订阅 URL

```bash
cat /var/www/sub/sub_url.txt   # 在 Server1 上执行
```

### 查看 Xray 日志

```bash
journalctl -u xray -f         # 实时查看
journalctl -u xray -n 50      # 最近 50 条
```

---

## 安全说明

本方案有两层保护：

| 层级 | 保护内容 | 机制 |
|------|---------|------|
| 第一层 | 订阅文件 | URL 中含随机 token，他人无法猜到地址 |
| 第二层 | 代理本身 | VLESS 用 UUID 鉴权，SS 用随机密码鉴权 |

### 情况一：订阅 URL 泄露

只有订阅地址暴露，UUID/密码未被使用。换掉 token，旧 URL 立即失效：

```bash
ssh ubuntu@<Server1_IP>
sudo rm /var/www/sub/.token
sudo bash ~/setup_sub_server.sh
```

脚本会生成新 token，重新询问节点参数（UUID 和 SS 密码不变，从 `/etc/xray/node_params.env` 查看即可）。完成后在 Clash Verge 中删除旧订阅，添加新 URL。

### 情况二：UUID 或 SS 密码泄露

需要在两台服务器上各换一套新凭据，再更新订阅。

**第 1 步：两台服务器各执行凭据轮换**

```bash
# Server1
ssh ubuntu@<Server1_IP>
sudo bash ~/rotate_credentials.sh

# Server2
ssh ubuntu@<Server2_IP>
sudo bash ~/rotate_credentials.sh
```

记录两台服务器输出的新 UUID、PUBLIC_KEY、SHORT_ID。

**第 2 步：SS 密码也需要轮换**（`rotate_credentials.sh` 只轮换 VLESS 凭据）

```bash
# 在每台服务器上执行，删除旧 SS inbound 后重新添加
sudo jq 'del(.inbounds[] | select(.protocol == "shadowsocks"))' /etc/xray/config.json > /tmp/cfg.json
sudo mv /tmp/cfg.json /etc/xray/config.json
sudo rm -f /etc/xray/node_params.env   # 旧 SS_PASSWORD 已失效，清空让 add_shadowsocks 重写
# 注意：先把 VLESS 参数手动写回 node_params.env，再运行 add_shadowsocks.sh
sudo bash ~/add_shadowsocks.sh
```

> 更简单的方式：直接重新部署（uninstall → install），凭据全部重新生成。

**第 3 步：Server1 重新运行订阅脚本**

```bash
sudo bash ~/setup_sub_server.sh
```

用新参数录入，完成后在 Clash Verge 中更新订阅。

---

## 常见问题

**Q: Clash Verge 无法连接代理？**
1. 确认 OCI 控制台安全列表已放行 18443 TCP、18444 TCP+UDP
2. 确认 Xray 服务正在运行：`systemctl status xray`
3. 测试端口连通性：`nc -zv <服务器IP> 18444`
4. 优先使用 `-SS` 节点；VLESS+Reality 在部分国内链路上握手会被干扰

**Q: 订阅 URL 无法访问？**
1. 确认 OCI 控制台安全列表已放行 TCP 18088
2. 确认订阅服务正在运行：`systemctl status sub-server`
3. 确认 URL 中的 token 正确：`cat /var/www/sub/sub_url.txt`

**Q: 重装系统后如何恢复？**
执行重新部署流程：`uninstall.sh` → `setup_xray.sh` → `add_shadowsocks.sh` → `setup_sub_server.sh`，Clash Verge 中更新订阅。
