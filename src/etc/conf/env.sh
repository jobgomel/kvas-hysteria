#!/bin/sh

# Подключение системных констант приложения
[ -f /opt/apps/kvas-hysteria/etc/conf/const.sh ] && . /opt/apps/kvas-hysteria/etc/conf/const.sh

# Параметры прокси-сервера Hysteria
PROXY_LOCAL_IP="127.0.0.1"
PROXY_LOCAL_PORT_SOCKS=10808
PROXY_LOCAL_PORT_HTTP=10809
