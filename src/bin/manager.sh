#!/bin/sh

# Изолированные пути приложения
APP_NAME="kvas-hysteria"
APP_BASE="/opt/apps/${APP_NAME}"
BIN_PATH="${APP_BASE}/bin/hysteria"
TEMPLATE_CONFIG="${APP_BASE}/etc/conf/config.yaml"
TEMPLATE_INIT="${APP_BASE}/etc/init.d/S99hysteria"
CHECK_SPACE_SCRIPT="${APP_BASE}/etc/ndm/check_space.sh"
TEST_SCRIPT="${APP_BASE}/etc/ndm/test_connection.sh" # <-- Скрипт теста

# Глобальные системные пути Entware
FINAL_CONFIG_DIR="/opt/etc/hysteria"
FINAL_CONFIG_PATH="${FINAL_CONFIG_DIR}/config.yaml"
SYSTEM_INIT_PATH="/opt/etc/init.d/S99hysteria"

# Параметры Keenetic RCI API
KEENETIC_PROXY_NAME="Proxy41"
KEENETIC_PROXY_DESC="Kvas-proxy-hysteria"
PROXY_LOCAL_IP="127.0.0.1"
PROXY_LOCAL_PORT=10808
PROXY_PROTO="socks5"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;0m'

show_status() {
    echo "=== Менеджер Kvas-Hysteria ==="
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

    if [ -f "$FINAL_CONFIG_PATH" ]; then
        echo -e "Конфигурация: ${GREEN}Активна${NC} ($FINAL_CONFIG_PATH)"
        SERVER=$(grep '^server:' "$FINAL_CONFIG_PATH" | awk '{print $2}')
        echo " -> Сервер: $SERVER"
    else
        echo -e "Конфигурация: ${YELLOW}Ожидает импорта ссылки (add)${NC}"
    fi
    echo "----------------------------------------"
    echo "Использование:"
    echo "  ${APP_NAME} install          - Скачать/обновить бинарный файл Hysteria"
    echo "  ${APP_NAME} uninstall        - Полное удаление пакета и интеграции"
    echo -e "  ${APP_NAME} add ${BLUE}\"link\"${NC}       - Парсинг ссылки (кавычки ${RED}\"\"${NC} обязательны для экранирования!)"
    echo "  ${APP_NAME} test             - Экспресс-тест проксирования туннеля"
    echo "  ${APP_NAME} start | stop | restart"
}

run_test() {
    if [ -f "$TEST_SCRIPT" ]; then
        "$TEST_SCRIPT"
    else
        echo -e "${RED}Ошибка: Компонент тестирования не найден.${NC}"
        exit 1
    fi
}

install_hysteria() {
    if [ -f "$CHECK_SPACE_SCRIPT" ]; then
        if ! "$CHECK_SPACE_SCRIPT"; then
            exit 1
        fi
    fi

    echo "Определение архитектуры процессора..."
    ARCH=$(uname -m)
    case "$ARCH" in
        *aarch64*|*arm64*)            BINARY_ARCH="arm64" ;;
        *armv7*|*armv6*|*arm*)        BINARY_ARCH="arm" ;;
        *mipsel*|*mipsle*)            BINARY_ARCH="mipsle" ;;
        *mips64el*)                   BINARY_ARCH="mipsle" ;;
        *mips*)                       BINARY_ARCH="mipsle" ;;
        *x86_64*|*amd64*)             BINARY_ARCH="amd64" ;;
        *i?86*|*x86*)                 BINARY_ARCH="386" ;;
        *)                            BINARY_ARCH="" ;;
    esac

    if [ -z "$ARCH" ]; then
        echo -e "${RED}Ошибка: Неподдерживаемая архитектура: $ARCH${NC}"
        exit 1
    fi

    echo "Запрос актуальной версии Hysteria с GitHub..."
    LATEST_VERSION=$(curl -sI https://github.com/apernet/hysteria/releases/latest | grep -i 'location:' | sed -E 's/.*\/tag\/([^[:space:]\r\n]+).*/\1/')

    if [ -z "$LATEST_VERSION" ] || echo "$LATEST_VERSION" | grep -q "{" ; then
        echo -e "${YELLOW}Предупреждение: Переход на базовый релиз v2.6.0${NC}"
        LATEST_VERSION="app/v2.6.0"
    fi

    # Инициализируем путь к временному файлу
    TMP_BIN_PATH="${BIN_PATH}.tmp"
    rm -f "$TMP_BIN_PATH"

    echo -e "Скачиваем ${BLUE}Hysteria $LATEST_VERSION${NC} для ${YELLOW}$BINARY_ARCH${NC} во временный файл..."
    curl -L -o "$TMP_BIN_PATH" "https://github.com/apernet/hysteria/releases/download/${LATEST_VERSION}/hysteria-linux-${BINARY_ARCH}"

    if [ ! -s "$TMP_BIN_PATH" ]; then
        echo -e "${RED}Ошибка записи временного файла. Возможно, закончилось место.${NC}"
        rm -f "$TMP_BIN_PATH"
        exit 1
    fi

    chmod +x "$TMP_BIN_PATH"

    # Шаг проверки временного файла на работоспособность
    if "$TMP_BIN_PATH" version >/dev/null 2>&1; then
        echo -e "${GREEN}Временный файл успешно проверен (${BINARY_ARCH})${NC}"
    else
        # На MIPS без FPU помогает softfloat-вариант
        if [ "$BINARY_ARCH" = "mipsle" ] || [ "$BINARY_ARCH" = "mips" ]; then
            echo -e "${RED}Стандартная сборка не запустилась. Пробую softfloat-вариант hysteria...${NC}"
            rm -f "$TMP_BIN_PATH"
            curl -L -o "$TMP_BIN_PATH" "https://github.com/apernet/hysteria/releases/download/${LATEST_VERSION}/hysteria-linux-${BINARY_ARCH}-sf"
        fi

        chmod +x "$TMP_BIN_PATH"
        if "$TMP_BIN_PATH" version >/dev/null 2>&1; then
            echo -e "${GREEN}Временный файл успешно проверен (mipsle-sf)${NC}"
        else
            echo -e "${RED}Ошибка: Скачанный бинарник Hysteria не поддерживается этим устройством.${NC}"
            rm -f "$TMP_BIN_PATH"
            exit 1
        fi
    fi

    # Проверяем, запущена ли служба прямо сейчас
    WAS_RUNNING=0
    PIDFILE="/var/run/hysteria.pid"
    if [ -f "$SYSTEM_INIT_PATH" ] && [ -f "$PIDFILE" ] && kill -0 $(cat $PIDFILE) 2>/dev/null; then
        WAS_RUNNING=1
        echo "Останавливаем текущую службу для быстрой замены бинарного файла..."
        "$SYSTEM_INIT_PATH" stop
    fi

    # Производим атомарную замену бинарника
    mv "$TMP_BIN_PATH" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    ln -sf "$BIN_PATH" /opt/bin/hysteria

    echo -e "${GREEN}Бинарный файл успешно развернут!${NC}"

    # Если служба до этого работала — запускаем её обратно на новом бинарнике
    if [ "$WAS_RUNNING" -eq 1 ]; then
        echo "Перезапускаем службу..."
        "$SYSTEM_INIT_PATH" start
        sleep 2
        run_test # Авто-тест после обновления «на лету»
    fi

    echo -e "${YELLOW}Чтобы настроить подключение, выполните команду:${NC}"
    echo -e "  ${BLUE}kvas-hysteria add \"hysteria2://...\"${NC}"
    echo -e "${RED}Важно:${NC} Кавычки ${GREEN}\"\"${NC} обязательны, чтобы ссылка не ломала терминал!"
}

add_config() {
    URL="$1"
    if [ -z "$URL" ]; then
        echo -e "${RED}Ошибка: Не указана ссылка!${NC}"
        exit 1
    fi

    if [ ! -f "$TEMPLATE_CONFIG" ]; then
        echo -e "${RED}Ошибка: Базовый шаблон конфигурации не найден в $TEMPLATE_CONFIG${NC}"
        exit 1
    fi

    echo "Разбираем конфигурацию пира..."
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
        echo -e "${RED}Ошибка парсинга ссылки.${NC}"
        exit 1
    fi

    cat << EOC > "$FINAL_CONFIG_PATH"
server: $SERVER
auth: $AUTH
tls:
  sni: ${SNI}
  fingerprint: ${FP:-chrome}
EOC

    if [ "$OBFS_TYPE" = "salamander" ] && [ -n "$OBFS_PASS" ]; then
        cat << EOC >> "$FINAL_CONFIG_PATH"
obfs:
  type: salamander
  salamander:
    password: $OBFS_PASS
EOC
    fi

    echo "" >> "$FINAL_CONFIG_PATH"
    cat "$TEMPLATE_CONFIG" >> "$FINAL_CONFIG_PATH"

    echo -e "${GREEN}Конфигурация успешно сгенерирована: $FINAL_CONFIG_PATH${NC}"

    echo "Активация службы автозапуска..."
    ln -sf "$TEMPLATE_INIT" "$SYSTEM_INIT_PATH"

    "$SYSTEM_INIT_PATH" restart
    sleep 2 # Даем 2 секунды на инициализацию перед тестом

    # === ИНТЕГРАЦИЯ С KEENETIC RCI API ===
    echo "Интеграция с KeeneticOS API..."
    curl -s -d '[{"interface": { "name": "'${KEENETIC_PROXY_NAME}'","no": true }}]' "localhost:79/rci/" > /dev/null 2>&1

    API_DATA='[{
        "interface": {
            "name": "'${KEENETIC_PROXY_NAME}'",
            "description": "'${KEENETIC_PROXY_DESC}'",
            "proxy": {
                "protocol": { "proto": "'${PROXY_PROTO}'" },
                "upstream": { "host": "'${PROXY_LOCAL_IP}'", "port": "'${PROXY_LOCAL_PORT}'" },
                "socks5-udp": true
            }
        },
        "system": { "configuration": { "save": true } }
    }]'

    curl -s -d "${API_DATA}" "localhost:79/rci/" > /dev/null 2>&1
    curl -s -d '[{"interface": {"name": "'${KEENETIC_PROXY_NAME}'", "up": true}}]' "localhost:79/rci/" > /dev/null 2>&1

    echo -e "${GREEN}Интерфейс '${KEENETIC_PROXY_DESC}' успешно обновлен в KeeneticOS!${NC}"
    echo -e "${YELLOW}Чтобы изменить VPN интерфейс kvas'а, выполните команду:${NC}"
    echo -e "  ${BLUE}kvas vpn set${NC}"

    echo ""
    run_test # Авто-тест после добавления новой конфигурации
}

uninstall_packet() {
    echo "Деактивация и остановка служб..."
    [ -f "$SYSTEM_INIT_PATH" ] && "$SYSTEM_INIT_PATH" stop

    echo "Удаление прокси-интерфейса из KeeneticOS..."
    curl -s -d '[{"interface": { "name": "'${KEENETIC_PROXY_NAME}'","no": true },"system": {"configuration": {"save": true}}}]' "localhost:79/rci/" > /dev/null 2>&1

    echo "Удаление симлинков и файлов пакета..."
    rm -f /opt/bin/kvas-hysteria /opt/bin/hysteria "$SYSTEM_INIT_PATH" /var/run/hysteria.pid
    rm -rf "$FINAL_CONFIG_DIR" "$APP_BASE"
    echo -e "${GREEN}Пакет kvas-hysteria успешно удален.${NC}"
}

case "$1" in
    install) install_hysteria ;;
    uninstall) uninstall_packet ;;
    add) add_config "$2" ;;
    test) run_test ;; # <-- Вызов ручного теста
    start|restart)
        if [ -f "$SYSTEM_INIT_PATH" ]; then
            "$SYSTEM_INIT_PATH" "$1"
            sleep 2
            run_test # <-- Авто-тест после старта/перезапуска
        else
            echo -e "${RED}Ошибка: Конфигурация не инициализирована. Сначала вызовите add${NC}"
        fi
        ;;
    stop)
        if [ -f "$SYSTEM_INIT_PATH" ]; then "$SYSTEM_INIT_PATH" "stop"; else echo -e "${RED}Ошибка: Конфигурация не инициализирована.${NC}"; fi
        ;;
    *) show_status ;;
esac