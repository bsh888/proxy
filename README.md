# OCI 双节点代理部署说明

## 架构概览

```
你的电脑/手机
    │
    ├─── 订阅更新 (HTTP) ───→ Server1:18088  ← Python 服务，提供订阅文件
    │
    ├─── 代理流量 ──────────→ Server1:18444  ← Xray Shadowsocks
    └─── 代理流量 ──────────→ Server2:18444  ← Xray Shadowsocks
```

**协议：Shadowsocks（chacha20-ietf-poly1305）**
- 支持 TCP + UDP
- 简单可靠，国内链路稳定
- 资源占用极低，适合 1C1G 机器

**支持客户端：**
- macOS / Windows：[Clash Verge](https://github.com/clash-verge-rev/clash-verge-rev/releases)（订阅 `clash.yaml`）
- iOS：Spectre（订阅 `ss.txt`）

---

## 脚本说明

| 脚本 | 用途 | 在哪里运行 |
|------|------|-----------|
| `setup_xray.sh` | 安装 Xray，生成 Shadowsocks 配置 | Server1、Server2 各一次 |
| `setup_sub_server.sh` | 部署订阅 HTTP 服务，生成订阅文件 | 只在 Server1 |
| `uninstall.sh` | 卸载全部服务 | 需要清理的服务器上 |

---

## 部署步骤

### 第零步：OCI 控制台放行端口

**在开始部署前，先把端口打开。**

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

**需要添加的规则（共 3 条）：**

| 在哪台添加 | IP 协议 | 目标端口 | 说明 |
|-----------|---------|---------|------|
| Server1、Server2 都加 | TCP | `18444` | Xray Shadowsocks |
| Server1、Server2 都加 | UDP | `18444` | Xray Shadowsocks UDP |
| 只在 Server1 加 | TCP | `18088` | 订阅服务 |

> 如果两台服务器在不同区域，VCN 是分开的，需要分别进各自的 VCN 操作。

---

### 第一步：上传脚本到两台服务器

在本机执行（替换实际 IP）：

```bash
# 上传到 Server1
scp setup_xray.sh setup_sub_server.sh uninstall.sh ubuntu@<Server1_IP>:~/

# 上传到 Server2
scp setup_xray.sh uninstall.sh ubuntu@<Server2_IP>:~/
```

---

### 第二步：Server1 安装

```bash
ssh ubuntu@<Server1_IP>
sudo bash ~/setup_xray.sh
```

输出示例，**记下 PASSWORD**：

```
============================================================
  安装完成！复制以下参数备用
============================================================
  IP          1.2.3.4
  PORT        18444
  PASSWORD    xxxxxxxxxxxxxxxxxxxxxxxx
  CIPHER      chacha20-ietf-poly1305
============================================================
```

参数随时可查：
```bash
cat /etc/xray/node_params.env
```

验证服务：
```bash
systemctl status xray   # 应显示 active (running)
```

---

### 第三步：Server2 安装

```bash
ssh ubuntu@<Server2_IP>
sudo bash ~/setup_xray.sh
```

同样记录输出的 PASSWORD。

---

### 第四步：Server1 部署订阅服务

```bash
ssh ubuntu@<Server1_IP>
sudo bash ~/setup_sub_server.sh
```

按提示输入两台服务器的参数：

```
=== 请输入节点参数 ===

节点数量: 2

--- 节点 1 ---
  备注名 (如 OCI-Osaka): OCI-Osaka-1
  服务器 IP: <Server1_IP>
  端口 (默认18444): 18444
  密码 (SS_PASSWORD): xxxxxxxxxxxxxxxxxxxxxxxx

--- 节点 2 ---
  备注名 (如 OCI-Osaka): OCI-Osaka-2
  服务器 IP: <Server2_IP>
  端口 (默认18444): 18444
  密码 (SS_PASSWORD): yyyyyyyyyyyyyyyyyyyyyyyy
```

完成后输出两个订阅地址：

```
============================================================
  订阅服务部署完成！
============================================================
  Clash Verge 订阅 URL:
  http://1.2.3.4:18088/<token>/clash.yaml

  Spectre (iOS) 订阅 URL:
  http://1.2.3.4:18088/<token>/ss.txt
============================================================
```

两个 URL 也保存在 Server1 的 `/var/www/sub/sub_url.txt`：
```bash
cat /var/www/sub/sub_url.txt
```

**验证订阅服务可访问**（在本机执行）：
```bash
curl http://<Server1_IP>:18088/<token>/clash.yaml
```

---

### 第五步：Clash Verge 添加订阅

1. 打开 **Clash Verge** → 左侧 **配置**
2. 右上角点 **新建** → 类型选 **远程**
3. 粘贴 `clash.yaml` 那条 URL → 保存
4. 点击配置卡片的 **激活** 按钮

左侧 **代理** 页面可以看到 **⚡ 自动最优** 分组，两个节点测速有延迟数值即表示连通。

---

### 第六步（可选）：iOS Spectre 添加订阅

1. 打开 **Spectre** → 右上角 **+** → **添加分享的链接**
2. 粘贴 `ss.txt` 那条 URL → 完成

添加成功后可以看到 `OCI-Osaka-1` 和 `OCI-Osaka-2` 两个节点。

---

## 重新部署

需要完全重装时（换服务器、系统重装、排查问题等）：

**两台服务器各自执行卸载：**
```bash
sudo bash ~/uninstall.sh
```

**然后从第二步开始重新执行即可。** 脚本均为幂等设计，重复执行不会产生冲突。

---

## 卸载

在需要清理的服务器上执行：

```bash
sudo bash ~/uninstall.sh
```

脚本自动检测并清理：
- Xray 服务、二进制、配置文件、iptables 规则（18444 TCP+UDP）
- 如果是 Server1（检测到订阅服务），同时清理订阅服务、文件、iptables 规则（18088）

> OCI 控制台「安全列表」中的入站规则需手动删除。

---

## 日常维护

### 查看服务状态

```bash
systemctl status xray          # 两台都有
systemctl status sub-server    # 仅 Server1
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
journalctl -u xray -f       # 实时
journalctl -u xray -n 50    # 最近 50 条
```

---

## 安全说明

两层保护：

| 层级 | 保护内容 | 机制 |
|------|---------|------|
| 第一层 | 订阅文件 | URL 中含随机 token，他人无法猜到地址 |
| 第二层 | 代理本身 | Shadowsocks 用随机密码鉴权 |

### 情况一：订阅 URL 泄露

换掉 token，旧 URL 立即失效：

```bash
ssh ubuntu@<Server1_IP>
sudo rm /var/www/sub/.token
sudo bash ~/setup_sub_server.sh
```

脚本生成新 token，重新录入节点参数（密码不变，从 `node_params.env` 查看）。完成后在 Clash Verge / Spectre 中更新订阅 URL。

### 情况二：SS 密码泄露

需要在两台服务器上重新生成密码：

```bash
# 每台服务器上执行
sudo rm /etc/xray/config.json
sudo bash ~/setup_xray.sh
```

记录新密码后，在 Server1 重新运行 `setup_sub_server.sh` 更新订阅。

---

## 常见问题

**Q: 节点显示 Timeout？**
1. 确认 OCI 控制台安全列表已放行 18444 TCP+UDP
2. 确认 Xray 运行正常：`systemctl status xray`
3. 测试端口连通性：`nc -zv <服务器IP> 18444`

**Q: 订阅 URL 无法访问？**
1. 确认 OCI 控制台安全列表已放行 TCP 18088
2. 确认订阅服务运行：`systemctl status sub-server`
3. 确认 URL 完整正确：`cat /var/www/sub/sub_url.txt`

**Q: 重装系统后如何恢复？**
执行重新部署流程：`uninstall.sh` → `setup_xray.sh`（两台）→ `setup_sub_server.sh`（Server1）→ 客户端更新订阅。
