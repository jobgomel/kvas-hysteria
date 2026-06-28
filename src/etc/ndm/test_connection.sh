#!/bin/sh

# Параметры прокси (должны совпадать с manager.sh)
PROXY_LOCAL_IP="127.0.0.1"
PROXY_LOCAL_PORT=10808

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;0m'

echo "Выполняется проверка проксирования через Hysteria 2..."
#echo "Запрос к ipinfo.io через socks5://${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT}..."

# Делаем запрос с таймаутом в 6 секунд, скрывая прогресс-бар curl
# Используем ipinfo.io, так как он отдает более стабильный и чистый JSON/текст
IP_RESPONSE=$(curl -s --connect-timeout 6 -x "socks5://${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT}" "https://ipinfo.io/ip")

if [ -n "$IP_RESPONSE" ] && ! echo "$IP_RESPONSE" | grep -q -E "(Failed|Error|404)"; then
    echo -e "${GREEN}Тест успешно пройден!${NC}"
    echo -e "Ваш внешний IP через туннель: ${BLUE}${IP_RESPONSE}${NC}"
    exit 0
else
    echo -e "${RED}Ошибка теста! Прокси-сервер не отвечает или соединение разорвано.${NC}"
    echo -e "${YELLOW}Рекомендации:${NC}"
    echo " 1. Проверьте статус службы: kvas-hysteria"
    echo " 2. Убедитесь, что параметры в ссылке (add) были верными."
    echo " 3. Проверьте системный лог роутера (logread)."
    exit 1
fi