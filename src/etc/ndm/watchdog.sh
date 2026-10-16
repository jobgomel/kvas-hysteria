#!/bin/sh

# shellcheck source=/dev/null
if [ -f /opt/apps/kvas-hysteria/etc/conf/env.sh ]; then
    . /opt/apps/kvas-hysteria/etc/conf/env.sh
elif [ -f "$(dirname "$0")/../conf/env.sh" ]; then
    . "$(dirname "$0")/../conf/env.sh"
fi

PIDFILE="/var/run/hysteria.pid"
ACTIVE_FLAG="/var/run/hysteria.active"
LOGFILE="/var/log/hysteria.log"
INIT_SCRIPT="/opt/etc/init.d/S99hysteria"
TEST_SCRIPT="/opt/apps/kvas-hysteria/etc/ndm/test_connection.sh"
[ ! -f "$TEST_SCRIPT" ] && [ -f "$(dirname "$0")/test_connection.sh" ] && TEST_SCRIPT="$(dirname "$0")/test_connection.sh"
INTERVAL="${WATCHDOG_INTERVAL:-30}"

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] $1" >> "$LOGFILE"
}

check_internet() {
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 77.88.8.8 >/dev/null 2>&1
}

check_proxy() {
    if [ -f "$TEST_SCRIPT" ]; then
        sh "$TEST_SCRIPT" -q
    else
        curl -f -s -m 5 --connect-timeout 4 -x "socks5h://${PROXY_LOCAL_IP:-127.0.0.1}:${PROXY_LOCAL_PORT_SOCKS:-10808}" "https://checkip.amazonaws.com" >/dev/null 2>&1
    fi
}

log_msg "Служба мониторинга туннеля запущена."

while [ -f "$ACTIVE_FLAG" ]; do
    sleep "$INTERVAL"

    [ ! -f "$ACTIVE_FLAG" ] && break

    # 1. Проверка аварийного падения процесса Hysteria
    NEED_RESTART=0
    if [ ! -f "$PIDFILE" ]; then
        NEED_RESTART=1
    elif ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        NEED_RESTART=1
    fi

    if [ "$NEED_RESTART" -eq 1 ]; then
        log_msg "Процесс Hysteria упал. Перезапуск..."
        "$INIT_SCRIPT" restart
        continue
    fi

    # 2. Если у роутера нет физического интернета (WAN упал), туннель не трогаем
    if ! check_internet; then
        continue
    fi

    # 3. Проверка доступности прокси-канала с защитой от единичной потери пакетов
    if ! check_proxy; then
        sleep 4
        if [ -f "$ACTIVE_FLAG" ]; then
            if ! check_proxy; then
                log_msg "Туннель Hysteria завис или разорван. Перезапуск службы..."
                "$INIT_SCRIPT" restart
                sleep 5
            fi
        fi
    fi
done

log_msg "Служба мониторинга туннеля остановлена."
