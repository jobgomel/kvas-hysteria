#!/bin/sh

# Импортируем общие переменные среды
# shellcheck source=/dev/null
if [ -f /opt/apps/kvas-hysteria/etc/conf/env.sh ]; then
    . /opt/apps/kvas-hysteria/etc/conf/env.sh
elif [ -f "$(dirname "$0")/../conf/env.sh" ]; then
    . "$(dirname "$0")/../conf/env.sh"
fi

PROXY_LOCAL_IP="${PROXY_LOCAL_IP:-127.0.0.1}"
PROXY_LOCAL_PORT_SOCKS="${PROXY_LOCAL_PORT_SOCKS:-10808}"

CHECK_URLS="${CHECK_URLS:-https://checkip.amazonaws.com https://icanhazip.com https://api.ipify.org https://ipinfo.io/ip https://ifconfig.me/ip https://2ip.io}"
CHECK_COUNTER=0
CURRENT_IP=""
CURRENT_DOMAIN=""

RED=${RED:-'\033[0;31m'}
GREEN=${GREEN:-'\033[0;32m'}
YELLOW=${YELLOW:-'\033[0;33m'}
BLUE=${BLUE:-'\033[0;34m'}
NC=${NC:-'\033[0m'}

get_random_url() {
    set -- $CHECK_URLS
    total=$#
    [ "$total" -le 1 ] && echo "$1" && return
    CHECK_COUNTER=$(( CHECK_COUNTER + 1 ))
    rand=${RANDOM:-$(( $(date +%s 2>/dev/null || echo 0) + $$ + CHECK_COUNTER ))}
    idx=$(( (rand % total) + 1 ))
    eval "echo \${$idx}"
}

query_ip() {
    target_url="$1"
    timeout="${2:-5}"
    curl -f -s -m "$timeout" --connect-timeout 4 -x "socks5h://${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT_SOCKS}" "$target_url" 2>/dev/null | tr -d '\r\n[:space:]'
}

is_valid_ip() {
    echo "$1" | grep -q -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'
}

check_proxy() {
    target_url=$(get_random_url)
    raw_ip=$(query_ip "$target_url" 5)

    if [ -n "$raw_ip" ] && is_valid_ip "$raw_ip"; then
        CURRENT_IP="$raw_ip"
        CURRENT_DOMAIN="${target_url#*://}"
        CURRENT_DOMAIN="${CURRENT_DOMAIN%%/*}"
        return 0
    fi

    # Защита от сбоя конкретного внешнего сервиса / rate limit: опрашиваем резервный URL из пула
    for fallback_url in $CHECK_URLS; do
        [ "$fallback_url" = "$target_url" ] && continue
        raw_ip=$(query_ip "$fallback_url" 5)
        if [ -n "$raw_ip" ] && is_valid_ip "$raw_ip"; then
            CURRENT_IP="$raw_ip"
            CURRENT_DOMAIN="${fallback_url#*://}"
            CURRENT_DOMAIN="${CURRENT_DOMAIN%%/*}"
            return 0
        fi
        break
    done

    return 1
}

# Обработка аргументов:
# -q / --quiet / silent - тихий режим для watchdog (только exit code 0 или 1)
# --ip                  - вывод только полученного внешнего IP-адреса
# по умолчанию          - подробный интерактивный отчет для kvas-hysteria test
QUIET=0
IP_ONLY=0

for arg in "$@"; do
    case "$arg" in
        -q|--quiet|silent) QUIET=1 ;;
        --ip) IP_ONLY=1 ;;
    esac
done

if [ "$QUIET" -eq 1 ]; then
    check_proxy
    exit $?
fi

if [ "$IP_ONLY" -eq 1 ]; then
    if check_proxy; then
        echo "$CURRENT_IP"
        exit 0
    fi
    exit 1
fi

echo "Выполняется проверка проксирования через Hysteria 2..."

if check_proxy; then
    printf "${GREEN}Тест успешно пройден!${NC}\n"
    printf "Ваш внешний IP через туннель Hysteria: ${BLUE}%s${NC} (${YELLOW}%s${NC})\n" "$CURRENT_IP" "$CURRENT_DOMAIN"
    exit 0
else
    printf "${RED}Ошибка теста! Прокси-сервер не отвечает или туннель не установил соединение.${NC}\n"
    printf "${YELLOW}Рекомендации:${NC}\n"
    echo " 1. Проверьте статус службы: kvas-hysteria"
    echo " 2. Убедитесь, что параметры в ссылке (add) были верными."
    echo " 3. Проверьте журнал: cat /var/log/hysteria.log"
    exit 1
fi