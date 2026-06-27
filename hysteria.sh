#!/bin/sh

# Пути
BIN_PATH="/opt/bin/hysteria"
CONFIG_DIR="/opt/etc/hysteria"
CONFIG_PATH="${CONFIG_DIR}/config.yaml"
INIT_PATH="/opt/etc/init.d/S99hysteria"

# Цвета для вывода в терминал
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;0m' # No Color

show_status() {
    echo "=== Менеджер Hysteria 2 ==="
    if [ -f "$BIN_PATH" ]; then
        VERSION=$($BIN_PATH -v 2>/dev/null | head -n 1)
        echo -e "Статус: ${GREEN}Установлен${NC} ($VERSION)"
    else
        echo -e "Статус: ${RED}Не установлен${NC}"
    fi

    PIDFILE="/var/run/hysteria.pid"
    if [ -f "$PIDFILE" ] && kill -0 $(cat $PIDFILE) 2>/dev/null; then
        echo -e "Служба: ${GREEN}Запущена${NC} (PID: $(cat $PIDFILE))"
    else
        echo -e "Служба: ${RED}Остановлена${NC}"
    fi

    if [ -f "$CONFIG_PATH" ]; then
        echo -e "Конфигурация: ${GREEN}Присутствует${NC} ($CONFIG_PATH)"
        SERVER=$(grep '^server:' "$CONFIG_PATH" | awk '{print $2}')
        SNI=$(grep 'sni:' "$CONFIG_PATH" -A 1 | grep 'sni:' | awk '{print $2}')
        echo " -> Сервер: $SERVER"
        [ -n "$SNI" ] && echo " -> SNI: $SNI"
    else
        echo -e "Конфигурация: ${YELLOW}Отсутствует${NC}"
    fi
    echo "----------------------------------------"
    echo "Использование:"
    echo "  $0 install          - Установка Hysteria 2"
    echo "  $0 uninstall        - Полное удаление"
    echo "  $0 add \"link\"       - Импорт конфигурации из ссылки"
    echo "  $0 start            - Запуск прокси"
    echo "  $0 stop             - Остановка прокси"
    echo "  $0 restart          - Перезапуск прокси"
}

install_hysteria() {
    echo "Определение архитектуры процессора..."
    ARCH=$(uname -m)
    case "$ARCH" in
        armv7l|aarch64) BINARY_ARCH="linux-arm" ;;
        mips|mipsel)
            if opkg print-architecture | grep -q "mipsel"; then
                BINARY_ARCH="linux-mipsle"
            elif [ -f /proc/cpuinfo ] && grep -q -i "little endian" /proc/cpuinfo; then
                BINARY_ARCH="linux-mipsle"
            else
                BINARY_ARCH="linux-mipsle"
            fi
            ;;
        *)
            echo -e "${RED}Ошибка: Неподдерживаемая архитектура: $ARCH${NC}"
            exit 1
            ;;
    esac

    # Динамическое получение последней версии БЕЗ использования GitHub API
    echo "Запрос актуальной версии Hysteria с GitHub (через редирект)..."
    LATEST_VERSION=$(curl -sI https://github.com/apernet/hysteria/releases/latest | grep -i 'location:' | sed -E 's/.*\/tag\/app\/([^[:space:]\r\n]+).*/\1/')

    # Если вдруг и это не сработало (например, curl без поддержки SSL или опечатка), ставим базовый фолбек
    if [ -z "$LATEST_VERSION" ] || echo "$LATEST_VERSION" | grep -q "{" ; then
        echo -e "${YELLOW}Предупреждение: Не удалось определить версию по редиректу. Ставим проверенную v2.6.0${NC}"
        LATEST_VERSION="v2.6.0"
    fi

    # Вывод красивого лога с точной версией (например, v2.6.0)
    echo -e "Скачиваем ${BLUE}Hysteria $LATEST_VERSION${NC} для ${YELLOW}$BINARY_ARCH${NC}..."
    mkdir -p /opt/bin
    
    # Подставляем версию и правильный префикс /app/
    curl -L -o "$BIN_PATH" "https://github.com/apernet/hysteria/releases/download/app/${LATEST_VERSION}/hysteria-${BINARY_ARCH}"
    
    if [ ! -s "$BIN_PATH" ]; then
        echo -e "${RED}Ошибка: Не удалось скачать бинарный файл или диск переполнен.${NC}"
        rm -f "$BIN_PATH"
        exit 1
    fi
    
    chmod +x "$BIN_PATH"
    echo -e "${GREEN}Бинарный файл успешно установлен.${NC}"

    echo "Создаем скрипт автозапуска..."
    cat << 'SERVICE' > "$INIT_PATH"
#!/bin/sh
ENABLED=yes
PROG=/opt/bin/hysteria
ARGS="client -c /opt/etc/hysteria/config.yaml"
PIDFILE=/var/run/hysteria.pid

case "$1" in
    start)
        [ "$ENABLED" != "yes" ] && exit 0
        if [ -f $PIDFILE ] && kill -0 $(cat $PIDFILE) 2>/dev/null; then
            echo "Hysteria уже запущена."
        else
            $PROG $ARGS >/dev/null 2>&1 &
            echo $! > $PIDFILE
            echo "Hysteria успешно запущена."
        fi
        ;;
    stop)
        if [ -f $PIDFILE ]; then
            kill $(cat $PIDFILE) 2>/dev/null
            rm -f $PIDFILE
            echo "Hysteria остановлена."
        else
            echo "Hysteria не запущена."
        fi
        ;;
    restart)
        $0 stop && sleep 2 && $0 start
        ;;
    *)
        echo "Использование: $0 {start|stop|restart}"
        exit 1
        ;;
esac
SERVICE
    chmod +x "$INIT_PATH"
    echo -e "${GREEN}Установка завершена! Примените конфиг командой: hysteria.sh add \"ссылка\"${NC}"
}

uninstall_hysteria() {
    echo "Останавливаем службу..."
    [ -f "$INIT_PATH" ] && "$INIT_PATH" stop
    rm -f "$BIN_PATH" "$INIT_PATH" /var/run/hysteria.pid /opt/bin/hysteria.sh
    rm -rf "$CONFIG_DIR"
    echo -e "${GREEN}Hysteria успешно удалена!${NC}"
}

add_config() {
    URL="$1"
    if [ -z "$URL" ]; then
        echo -e "${RED}Ошибка: Не указана ссылка!${NC}"
        exit 1
    fi
    echo "Разбираем ссылку..."
    URL=$(echo "$URL" | tr -d '[:space:]')
    MAIN_PART=$(echo "$URL" | sed -E 's|h2://||;s|hysteria2://||;s|\?.*||')
    AUTH=$(echo "$MAIN_PART" | cut -d'@' -f1)
    SERVER=$(echo "$MAIN_PART" | cut -d'@' -f2)
    SNI=$(echo "$URL" | sed -n -E 's/.*([?&])sni=([^&#]*).*/\2/p')
    FP=$(echo "$URL" | sed -n -E 's/.*([?&])fp=([^&#]*).*/\2/p')
    OBFS_TYPE=$(echo "$URL" | sed -n -E 's/.*([?&])obfs=([^&#]*).*/\2/p')
    OBFS_PASS=$(echo "$URL" | sed -n -E 's/.*([?&])obfs-password=([^&#]*).*/\2/p')
    [ -z "$SNI" ] && SNI=$(echo "$SERVER" | cut -d':' -f1)

    if [ -z "$AUTH" ] || [ -z "$SERVER" ]; then
        echo -e "${RED}Ошибка парсинга. Убедитесь, что ссылка взята в кавычки.${NC}"
        exit 1
    fi

    cat << EOC > "$CONFIG_PATH"
server: $SERVER
auth: $AUTH
tls:
  sni: ${SNI}
  fingerprint: ${FP:-chrome}
EOC

    if [ "$OBFS_TYPE" = "salamander" ] && [ -n "$OBFS_PASS" ]; then
        cat << EOC >> "$CONFIG_PATH"
obfs:
  type: salamander
  salamander:
    password: $OBFS_PASS
EOC
    fi

    cat << 'EOC' >> "$CONFIG_PATH"

socks5:
  listen: 127.0.0.1:10808
http:
  listen: 127.0.0.1:10809
quic:
  init_to: 10s
  keepalive_period: 10s
bandwidth:
  up: 50 mbps
  down: 100 mbps
fast_open: true
lazy: true
EOC

    echo -e "${GREEN}Конфигурация обновлена in $CONFIG_PATH${NC}"
    [ -f "$INIT_PATH" ] && "$INIT_PATH" restart
}

case "$1" in
    install) install_hysteria ;;
    uninstall) uninstall_hysteria ;;
    add) add_config "$2" ;;
    start|stop|restart)
        if [ -f "$INIT_PATH" ]; then "$INIT_PATH" "$1"; else echo -e "${RED}Ошибка: Служба не установлена.${NC}"; fi
        ;;
    *) show_status ;;
esac
