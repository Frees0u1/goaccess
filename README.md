# GoAccess 实时看板（群晖 Nginx）

使用 Docker 快速部署 GoAccess，对群晖 DSM 上的 Nginx `access.log` 进行实时分析，并输出可视化监控看板。

## 目录结构

```
docker-compose.yml
goaccess/goaccess.conf
Caddyfile
env.sample
```

## 快速开始

1) 复制环境变量样例（可选）

```bash
cp env.sample .env
```

根据实际情况修改 `.env`：

- `NGX_LOG_DIR`：群晖上的 Nginx 日志目录，通常为 `/var/log/nginx`
- `DASHBOARD_PORT`：看板访问端口（默认 8080）
- `WS_PORT`：GoAccess 实时推送端口（默认 7890）

2) 启动

```bash
docker compose up -d
```

3) 访问

- 看板页面: `http://<NAS_IP>:8080/`
- 实时 WebSocket: `ws://<NAS_IP>:7890`（页面会自动连接，无需手动访问）

## 群晖兼容说明

- 默认使用 Nginx Combined 日志格式（`COMBINED`）。如果你的 `access.log` 在末尾还有自定义字段（如上游地址、耗时等），可在 `goaccess/goaccess.conf` 中改用自定义 `log-format`，例如：

```
log-format %h %^[%d:%t %^] "%r" %s %b "%R" "%u" %^
```

- 实时看板采用 GoAccess 内置 WebSocket（端口 7890）。页面默认使用当前页面的 Host 自动连接到 `:7890`，因此通常无需设置 `ws-url`。

## 数据持久化

- GoAccess 的数据库位于 `./data/db`，可跨重启保留累计统计。
- 生成的看板 HTML 输出到 `./data/html/report.html`，由 Caddy 静态服务对外提供。

## 常见问题

- 看不到数据
  - 确认 `NGX_LOG_DIR` 指向的目录在容器内可读（挂载为 `:ro` 即只读即可）
  - `access.log` 文件名或路径不同于默认，请调整 `docker-compose.yml` 或日志路径
  - 日志格式不匹配：根据你的实际 `access.log` 改写 `log-format`

- 权限问题
  - 默认容器以 root 读取日志；若你的系统限制，请在群晖 Docker 中添加相应权限或以 root 运行

- HTTPS/域名
  - 可在群晖的“反向代理”或任意前端代理（如 Nginx/Caddy/Traefik）上为 `:8080`/`:7890` 配置证书与路由
  - 若走同域同端口，需将 WebSocket 路径代理到 `goaccess:7890`，并在 `goaccess.conf` 配置 `ws-url` 为页面下相对地址

## 管理命令

```bash
# 查看日志
docker compose logs -f goaccess

# 重启
docker compose restart

# 停止并清理
docker compose down
```


## 操作记录与扩展指南（反向代理 + GoAccess）

### 我们已完成的配置
- 开启并统一记录反代域名访问日志（仅这些域名会被记录）
  - 在 `sites-enabled/99-reverse-proxy-access-log.conf` 定义增强日志格式并按域名启用：
    - 使用 `log_format goaccess_rp`，包含 hostname、path、request_time 等
    - 使用 `map $server_name $loggable { hostnames; ... }` 精确匹配域名
    - `access_log /var/log/nginx/reverse-proxy.log goaccess_rp if=$loggable;`
- 对个别域名（如 `home`、`vesper`）在 `server.ReverseProxy.conf` 的对应 `server` 内显式开启 `access_log`，确保不被下级覆盖
- 修正日志文件权限（`http:http`，0640），并通过 `nginx -s reopen` 重新打开句柄
- 配置日志轮转：`/etc/logrotate.d/nginx-reverse-proxy`，按天轮转、保留 7 天、压缩归档
- GoAccess 解析配置已适配增强日志格式：
  - 文件：`goaccess/goaccess.conf`
  - 关键行：
    ``` 
    time-format %T
    date-format %d/%b/%Y
    log-format %h - %^[%d:%t %^] "%r" %s %b "%R" "%u" %T %^ %v %U
    ```
  - 说明：`%T`=请求总时延（request_time），`%v`=hostname（server_name），`%U`=path（request_uri），上游时延暂用 `%^` 忽略

### 常用验证与排错
- 验证新配置已加载
  - `sudo nginx -t && sudo nginx -s reload`
  - `sudo nginx -T | sed -n '/99-reverse-proxy-access-log.conf/,+40p'`
- 验证日志是否写入
  - 触发请求：`curl -k -I --resolve your.domain:443:127.0.0.1 https://your.domain/`
  - 查看：`sudo tail -n 30 /var/log/nginx/reverse-proxy.log`
- 检查是否被下级关闭
  - `sudo grep -n 'access_log off' /etc/nginx/sites-enabled/server.ReverseProxy.conf`
  - 若命中，在对应 `server` 内显式加入：`access_log /var/log/nginx/reverse-proxy.log goaccess_rp;`
- 权限与进程用户
  - `sudo ls -ld /var/log/nginx && sudo ls -l /var/log/nginx/reverse-proxy.log`
  - `ps -eo user,pid,cmd | grep '[n]ginx'`
  - 必要时：`sudo chown http:http /var/log/nginx/reverse-proxy.log && sudo chmod 0640 /var/log/nginx/reverse-proxy.log && sudo nginx -s reopen`
- 轮转是否工作
  - 干跑：`sudo logrotate -d /etc/logrotate.d/nginx-reverse-proxy`
  - 强制一次：`sudo logrotate -f /etc/logrotate.d/nginx-reverse-proxy`
  - 查看：`sudo ls -lh /var/log/nginx/reverse-proxy.log*`
- GoAccess 无数据或解析错误
  - 确认日志在增长；查看容器日志：`docker logs -n 200 goaccess`
  - 确认 `goaccess.conf` 的 `log-format` 与 Nginx 实际格式一致

### 新增反向代理域名时怎么做
1) 将新域名加入 map 列表（推荐方式）
   - 编辑 `99-reverse-proxy-access-log.conf` 的 map 段：
     ```
     map $server_name $loggable { hostnames;
         default 0;
         # 已有域名...
         new.example.com 1;      # 在此追加新域名
     }
     ```
   - 重新加载：`sudo nginx -t && sudo nginx -s reload`
   - 触发请求并在 `reverse-proxy.log` 中确认出现新域名的日志
2) 如该域名对应的 `server` 或 `location` 中存在 `access_log off;`
   - 在该 `server` 内显式加入：`access_log /var/log/nginx/reverse-proxy.log goaccess_rp;`
   - 再次 `nginx -t && nginx -s reload`
3) GoAccess 端无需更改
   - `goaccess.conf` 已适配增强格式；只要 `reverse-proxy.log` 里有新域名的日志，面板会自动统计

### 参考（Nginx 日志行字段顺序）
```
$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent \
"$http_referer" "$http_user_agent" $request_time $upstream_response_time \
$server_name $request_uri
```
- 对应 GoAccess：`%h - %^[%d:%t %^] "%r" %s %b "%R" "%u" %T %^ %v %U`


