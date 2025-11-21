#!/bin/sh
# 确保目录存在
mkdir -p /opt/goaccess/db /var/www/html

# 设置语言环境变量为中文
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# 启动 goaccess
# 注意：这里直接指定了配置文件路径，且通过 user: root 解决了权限问题
# 我们使用 exec 直接替换当前 shell 进程，并且指向 goaccess 二进制文件
exec /usr/bin/goaccess /logs/reverse-proxy.log \
  --real-time-html \
  --persist --restore \
  --db-path=/opt/goaccess/db \
  --html-report-title='Synology Nginx Real-Time Dashboard' \
  --config-file=/etc/goaccess/goaccess.conf \
  -o /var/www/html/report.html \
  --addr=0.0.0.0 \
  --port=7890
