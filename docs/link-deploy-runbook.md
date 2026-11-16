# 部署清单：把 DS Bot 的中继跑起来（腾讯云）

照着从上往下做即可。每条命令可以直接粘贴；需要替换的地方只有下面这组占位符。
命令前标 `[root]` 的用 root，标 `[ops]` 的用你的普通账号（有 sudo）。

## 0. 占位符

| 占位符 | 填什么 | 例子 |
|---|---|---|
| `[RELAY_HOST]` | 中继用的域名 | `relay.imzhien.online` |
| `[SERVER_IP]` | 实例的公网 IP | `1.2.3.4` |
| `[DNSPOD_ID]` | DNSPod API 的 ID | 在「DNSPod 控制台 → 密钥管理」生成 |
| `[DNSPOD_TOKEN]` | DNSPod API 的 Token | 与上一行成对出现，只显示一次，先存好 |
| `[PHONE_NAME]` | 手机在电脑端显示的名字 | `iPhone 15` |

仓库是公开的（`https://github.com/54zhien/ds-bot-ios`，`main` 分支），下面直接 clone，不需要 deploy key。

## 1. 系统准备

`[root]` 先建一个日常账号，后面都用它：

```sh
adduser --disabled-password --gecos "" ops
usermod -aG sudo ops
```

`[root]` 建服务专用账号（不能登录，只用来跑服务）：

```sh
useradd --system --no-create-home --shell /usr/sbin/nologin dsbot
```

`[ops]` 打开防火墙，只放 22/80/443：

```sh
sudo apt-get update
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status
```

预期最后一行：

```
Status: active
22/tcp                     ALLOW       Anywhere
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
```

为什么留 80：证书我们用 DNS-01，不需要 80；但留着它有两件事——`acme.sh` 的 HTTP-01 兜底、以及少数客户端/检查工具会先打 80。留着无害，不开明文服务即可。

`[ops]` 打开自动安全更新：

```sh
sudo apt-get install -y unattended-upgrades
sudo systemctl enable --now unattended-upgrades
systemctl is-active unattended-upgrades
```

预期：`active`

## 2. 装 Node 24

`link/README.md:12` 要求 Node 24（服务端直接跑 `.ts`，靠 Node 的类型剥离）。

`[ops]` 用 NodeSource 装（固定这一种，不要混用 nvm）：

```sh
curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/nodesource.sh
sudo bash /tmp/nodesource.sh
sudo apt-get install -y nodejs
node -v
npm -v
```

预期 `node -v` 是 `v24.` 开头（例如 `v24.14.1`），`npm -v` 是 `11.` 或更高。

## 3. 拉代码、跑通、装成服务

`[ops]`：

```sh
sudo git clone --depth 1 https://github.com/54zhien/ds-bot-ios.git /opt/dsbot-ios
cd /opt/dsbot-ios/link
sudo npm ci
```

预期 `npm ci` 结尾有 `added N packages` 和 `found 0 vulnerabilities`。

`[ops]` 用两个命令证明装对了（这两个必须在服务器上能过）：

```sh
sudo npm run typecheck
sudo npm test
```

预期 `typecheck` 只打印 `> tsc --noEmit` 后退出 0；`npm test` 结尾是：

```
ℹ tests 45
ℹ pass 45
ℹ fail 0
```

（数字随版本变化，关键看 `fail 0`。）

`[ops]` 建数据目录并写 systemd unit：

```sh
sudo mkdir -p /var/lib/dsbot-link
sudo chown dsbot:dsbot /var/lib/dsbot-link
sudo tee /etc/systemd/system/dsbot-link.service >/dev/null <<'UNIT'
[Unit]
Description=DS Bot link Relay Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=dsbot
Group=dsbot
WorkingDirectory=/opt/dsbot-ios/link
ExecStart=/usr/bin/node server/main.ts
Environment=PORT=8787
Environment=HOST=127.0.0.1
Environment=DSBOT_LINK_DATA=/var/lib/dsbot-link/devices.json
Environment=DSBOT_LINK_TRUST_PROXY=1
Restart=always
RestartSec=2
StateDirectory=dsbot-link
ReadWritePaths=/var/lib/dsbot-link
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
```

几点说明，照着做就不用改：

- `HOST=127.0.0.1`：只监听回环，公网由 nginx 进来（`server/main.ts:8-9` 的默认值是 `0.0.0.0`，我们不用）。
- `DSBOT_LINK_TRUST_PROXY=1`：nginx 后面必须开，原因见第 5 节。
- `ProtectSystem=strict` + `ReadWritePaths`：服务除了数据目录别处都写不了。
- `StateDirectory` 会让 systemd 自动建好 `/var/lib/dsbot-link` 并交给 `dsbot`。

`[ops]` 启动并设为开机自启：

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now dsbot-link
sudo systemctl status dsbot-link --no-pager
sudo journalctl -u dsbot-link -n 20 --no-pager
```

预期日志里只有一行：

```
DS Bot link Server: ws://127.0.0.1:8787/v1/link
```

这行来自 `server/main.ts:18`。**服务端没有连接级日志**，不要等它打印设备信息（见第 6 节的替代核对方法）。

自测一下本机端口：

```sh
curl -sS http://127.0.0.1:8787/healthz; echo
```

预期：`ok`（`server/server.ts:27-33`）。

## 4. 域名、DNS 与证书（必须 DNS-01）

### 4.1 加解析

在 DNSPod 里给 `imzhien.online` 加一条记录：

| 主机记录 | 类型 | 记录值 | TTL |
|---|---|---|---|
| `relay` | A | `[SERVER_IP]` | 600 |

`[ops]` 验证解析生效（可能等 1–10 分钟）：

```sh
dig +short [RELAY_HOST]
```

预期输出就是 `[SERVER_IP]`。

### 4.2 用 acme.sh + DNSPod 签证书

为什么必须 DNS-01：大陆实例未备案时 80/443 会被拦，HTTP-01 走不通；DNS-01 只要 DNSPod API 能改 TXT 记录就行，跟端口无关。

`[ops]` 安装 acme.sh（装到 /root 下）：

```sh
curl https://get.acme.sh | sudo sh -s email=admin@imzhien.online
sudo ls /root/.acme.sh/acme.sh
```

预期：打印出 `/root/.acme.sh/acme.sh`。

`[ops]` 签证书（`dns_dp` 是 DNSPod 的插件，需要 ID 与 Token 两个值）：

```sh
sudo env DP_Id="[DNSPOD_ID]" DP_Key="[DNSPOD_TOKEN]" \
  /root/.acme.sh/acme.sh --issue --dns dns_dp -d [RELAY_HOST] --keylength ec-256
```

预期结尾：

```
Your cert is in: /root/.acme.sh/[RELAY_HOST]_ecc/[RELAY_HOST].cer
```

`[ops]` 装到固定路径，并让 nginx 在续期后自动 reload：

```sh
sudo mkdir -p /etc/ssl/[RELAY_HOST]
sudo /root/.acme.sh/acme.sh --install-cert -d [RELAY_HOST] --ecc \
  --key-file       /etc/ssl/[RELAY_HOST]/key.pem \
  --fullchain-file /etc/ssl/[RELAY_HOST]/cert.pem \
  --reloadcmd      "systemctl reload nginx"
```

预期：`Installing key to: ...` / `Running reload cmd: systemctl reload nginx`。

`[ops]` 确认续期任务已经挂上：

```sh
sudo systemctl list-timers | grep -i acme || sudo crontab -l | grep acme
```

**不要用自签证书**：手机端的 WebSocket 走系统信任链，自签一律握手失败（本仓库没有覆盖这条的测试，属于平台行为，未验证到真机）。

## 5. nginx 反代

选 nginx 而不是 Caddy，因为要显式控制 `proxy_read_timeout`。

`[ops]` 安装并去掉默认站点：

```sh
sudo apt-get install -y nginx
sudo rm -f /etc/nginx/sites-enabled/default
nginx -v
```

`[ops]` 写站点配置：

```sh
sudo tee /etc/nginx/sites-available/dsbot-link >/dev/null <<'CONF'
map $http_upgrade $connection_upgrade { default upgrade; '' close; }

server {
  listen 443 ssl;
  http2 on;                       # nginx < 1.25.1 改成: listen 443 ssl http2;
  server_name [RELAY_HOST];

  ssl_certificate     /etc/ssl/[RELAY_HOST]/cert.pem;
  ssl_certificate_key /etc/ssl/[RELAY_HOST]/key.pem;
  ssl_protocols       TLSv1.2 TLSv1.3;

  location = /v1/link {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host       $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    proxy_buffering    off;
    proxy_read_timeout 90s;       # 必须大于 25s 心跳，否则代理会先掐断
    proxy_send_timeout 90s;
  }

  location = /healthz {
    proxy_pass http://127.0.0.1:8787;
    access_log off;
  }
}
CONF
sudo ln -sfn /etc/nginx/sites-available/dsbot-link /etc/nginx/sites-enabled/dsbot-link
sudo nginx -t
sudo systemctl reload nginx
```

预期：`nginx: configuration file /etc/nginx/nginx.conf test is successful`。

三个参数为什么这么写：

- `proxy_read_timeout 90s`：Server 每 25s 发一次 ping（`server/gateway.ts:53`、`135-145`），代理的读超时必须比心跳长，否则空闲链路会被 nginx 先关掉。
- `proxy_buffering off` + `proxy_http_version 1.1` + `Upgrade`/`Connection`：少任何一个，WebSocket 升级就变不成 `101`。
- `X-Forwarded-For` 配 `DSBOT_LINK_TRUST_PROXY=1`：Server 取 XFF 的**最后一段**作为客户端地址（`server/gateway.ts:101-108`），nginx 的 `$proxy_add_x_forwarded_for` 正好把真实客户端追加在最后。不开的话所有手机都算成 `127.0.0.1` 一个地址，单 IP 的 256 个 socket 与每小时 20 个新设备限额会被全站共用（`server/gateway.ts:85`、`116-125`）。

## 6. 验收

`[ops]` 四个检查，从下往上定位问题：

```sh
# 1) TLS 与 HTTP 通不通
curl -sS https://[RELAY_HOST]/healthz; echo

# 2) 服务在不在（/v1/link 只接 WebSocket 升级，普通请求一律 404）
curl -sSI https://[RELAY_HOST]/v1/link | head -n 1

# 3) 升级有没有被转过去（必须是 101）
curl -isS --http1.1 -m 3 \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  https://[RELAY_HOST]/v1/link | head -n 1 || true

# 4) 手机连上以后，服务端有几条连接
sudo ss -tn state established "( sport = :8787 )"
```

逐条预期：

1. `ok`
2. `HTTP/2 404`（这**正是**正常的：`server/server.ts:27-33` 对任何非升级请求都回 404，所以 404 说明 nginx 已经把请求送到 node；502 才是服务没起来）
3. `HTTP/1.1 101 Switching Protocols`
4. 每条在线链路一行；手机没连时可能只有 nginx 的空闲上游连接或 0 行

然后在电脑端：

1. DS Bot → **设置 → Phone** → 服务器填 `wss://[RELAY_HOST]/v1/link` → 打开「手机访问」。
2. 点配对，出现二维码。
3. 手机扫描（地址在二维码里，手机端没有手填地址的入口）。
4. 电脑端那台手机显示为 `[PHONE_NAME]`，状态「已连接」。

服务端没有设备注册日志（`server/main.ts:18` 只打启动那行），所以核对用这三个信号：第 4 步的 `ss` 连接数、`/var/lib/dsbot-link/devices.json` 里出现记录、电脑端列表里出现 `[PHONE_NAME]`。

```sh
sudo ls -l /var/lib/dsbot-link/devices.json
```

预期：配对成功后这个文件出现，权限 `-rw-------`（`server/store.ts:75-83` 用临时文件改名写入，权限 0600 在 `server/store.ts:81`）。

## 7. 备案分支：广州还是香港

判断点只有一个：`.online` 能不能备案。到腾讯云备案入口输入 `imzhien.online`，系统会直接告诉你结果——这比我猜可靠（`.online` 是否在工信部批复名单里，**我这里未验证**）。

**能备案 → 广州。** 大陆实例上域名要能过 80/443，必须先备案；未备案的域名打大陆机的 443 会被拦。流程：买广州实例 → 拿备案服务号 → 提交备案（个人主体一般 1–3 周）→ 通过后把 A 记录指到广州 IP，用同一条 acme.sh 命令重签证书即可。期间可以先在香港机上跑，域名 A 记录随时切。

**不能备案 / 不想等 → 香港。** 域名照用、证书照 DNS-01，完全不需要备案。代价是从大陆访问多一跳，延迟取决于线路（未验证具体数值，先用本机 `dig` + `curl -w '%{time_connect}' -o /dev/null -s https://[RELAY_HOST]/healthz` 对比）。

两条路径不影响代码和配置：换机器只要重做第 1–5 节，第 6 节验收不变。

## 8. 日常运维

### 8.1 日志

服务端只打启动那一行，日志量极小。给 journald 加个上限就够，不需要 logrotate：

```sh
sudo mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=200M\n' | sudo tee /etc/systemd/journald.conf.d/99-dsbot.conf
sudo systemctl restart systemd-journald
```

看日志：

```sh
sudo journalctl -u dsbot-link -n 50 --no-pager
sudo journalctl -u dsbot-link -f
```

### 8.2 限额调优

默认值（`README.md:26-34`，代码见 `server/gateway.ts:40-50`）：

| 变量 | 默认 | 什么时候要动 |
|---|---|---|
| `DSBOT_LINK_MAX_SOCKETS` | 1024 | 单机个人用不到；几百台手机同时在线才需要抬 |
| `DSBOT_LINK_MAX_LINKS` | 1024 | 同上，按「手机×电脑」的对数算 |
| `DSBOT_LINK_MAX_SOCKETS_PER_ADDRESS` | 256 | 只有在同一个出口 IP 后面有大量设备时才需要抬（家庭/校园 NAT 通常远低于此） |
| `DSBOT_LINK_MAX_NEW_DEVICES_PER_HOUR` | 20 | 新增设备只发生在配对时；一次配十几台手机才需要抬 |
| `DSBOT_LINK_DEVICE_TTL_DAYS` | 不设（永不清理） | 建议设 90：长期不用的设备记录自动清掉（`server/gateway.ts:127-133`） |

改法：编辑 unit 里的 `Environment=` 行 → `sudo systemctl daemon-reload && sudo systemctl restart dsbot-link`。

### 8.3 备份

`devices.json` 是唯一的状态（设备表 + token 哈希）。写入是临时文件 + rename，随便拷不会拷到半个文件（`server/store.ts:75-83`）。

```sh
sudo mkdir -p /var/backups
echo '0 4 * * * root tar czf /var/backups/dsbot-link-$(date +\%F).tar.gz -C /var/lib dsbot-link/devices.json && find /var/backups -name "dsbot-link-*.tar.gz" -mtime +14 -delete' | sudo tee /etc/cron.d/dsbot-link-backup
sudo chmod 644 /etc/cron.d/dsbot-link-backup
```

恢复：停服务 → 解压回 `/var/lib/dsbot-link/` → `chown dsbot:dsbot` → 起服务。

### 8.4 升级

```sh
sudo systemctl stop dsbot-link
cd /opt/dsbot-ios && sudo git pull --ff-only
cd link && sudo npm ci && sudo npm run typecheck && sudo npm test
sudo systemctl start dsbot-link
sudo journalctl -u dsbot-link -n 5 --no-pager
```

停服务的瞬间所有手机断链，手机端会按退避重连（1s 起、×2、封顶 60s）；连续 7 次失败（约 63 秒）后会显示「未连接」并给一个「重试」按钮，服务回来后点它或等下一轮即可。

## 附：出问题时按这个顺序看

| 现象 | 先看哪里 |
|---|---|
| `curl https://[RELAY_HOST]/healthz` 超时 | 安全组/ufw 是否放 443、nginx 是否在跑、DNS 是否指对 |
| `/healthz` 返回 nginx 默认页 | `sites-enabled` 里还有 default，或 `server_name` 不匹配 |
| `/healthz` 返回 502 | `systemctl status dsbot-link`，多半是 node 没起来或端口不对 |
| 升级检查不是 101 | nginx 少了 `proxy_http_version 1.1` / `Upgrade` / `Connection` 之一 |
| 手机一直「正在重新连接…」 | `sudo ss -tn state established "( sport = :8787 )"` 有没有连接；再看 `journalctl` 有无启动行 |
| 连上一会儿就掉，间隔很规律 | `proxy_read_timeout` 是不是小于 25s 心跳 |
| 手机提示证书错误 | 是否用了自签；acme.sh 装的是 fullchain 还是单证书 |

更多网络受限场景（只放行 80/443、UDP 全封、SNI 拦截）的判断方法见 `docs/link-deployment.md`。
