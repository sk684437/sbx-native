# Sbx Native

此分支仅用于用于serv00、ct8、HostUno等平台部署 VMess Ws + Argo、VLESS Reality、Hysteria2、TUIC、AnyTLS、SOCKS5 等代理，只有主进程，没有子进程，服务掉线了更新订阅来链接即可快速启动。

### serv00 | ct8 | HostUno 一键安装脚本（安装完先访问首页启动，过20秒再获取节点）
```bash
bash <(curl -Ls https://raw.githubusercontent.com/sk684437/sbx-native/refs/heads/serv00/ct8/install.sh)

```



## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `UPLOAD_URL` | 空 | Merge-sub 上传地址。填写后可上传订阅或节点。 |
| `PROJECT_URL` | 空 | 项目公网 URL。用于上传订阅和自动保活。 |
| `AUTO_ACCESS` | `false` | 设置为 `true` 时向保活服务提交 `PROJECT_URL`。 |
| `YT_WARPOUT` | `false` | 设置为 `true` 时强制 YouTube 走 WARP 出站规则。 |
| `FILE_PATH` |      | 运行目录，存放动态库、配置、订阅和临时文件。 |
| `SUB_PATH` | `sub` | 订阅token，例如 `/sub`。 |
| `UUID` | `0a6568ff-ea3c-4271-9020-450560e10d63` | 节点 UUID。建议自行修改。 |
| `NEZHA_SERVER` | 空 | 哪吒面板地址。v1：`nezha.xxx.com:8008` v0: `nezha.xxx.com` |
| `NEZHA_PORT` | 空 | 哪吒 v0 agent 端口；v1 留空。 |
| `NEZHA_KEY` | 空 | 哪吒 v1 的 `NZ_CLIENT_SECRET` 或 v0 agent 密钥。 |
| `ARGO_DOMAIN` | 空 | Cloudflare 固定隧道域名。为空时使用临时隧道。 |
| `ARGO_AUTH` | 空 | Cloudflare tunnel token 或 TunnelSecret JSON。 |
| `ARGO_PORT` | `8001` | Argo隧道端口，使用token需在cloudflare里设置一致 |
| `S5_PORT` | 空 | SOCKS5 入站端口。为空不启用。 |
| `TUIC_PORT` | 空 | TUIC 入站端口。为空不启用。 |
| `HY2_PORT` | 空 | Hysteria2 入站端口。为空不启用。 |
| `ANYTLS_PORT` | 空 | AnyTLS 入站端口。为空不启用。 |
| `REALITY_PORT` | 空 | VLESS Reality 入站端口。为空不启用。 |
| `CFIP` | `saas.sin.fan` | VMess Argo 节点中的优选域名或 IP。 |
| `CFPORT` | `443` | `CFIP` 对应端口。 |
| `PORT` | `3000` | HTTP 订阅服务监听端口。 |
| `NAME` | 空 | 节点名称前缀。 |
| `CHAT_ID` | 空 | Telegram chat id。 |
| `BOT_TOKEN` | 空 | Telegram bot token。`CHAT_ID` 和 `BOT_TOKEN` 都存在才推送。 |
| `DISABLE_ARGO` | `false` | 设置为 `true` 时禁用 Argo |
