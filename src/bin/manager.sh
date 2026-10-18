#!/bin/sh

# Изолированные базовые пути приложения
REPO="jobgomel/kvas-hysteria"
APP_NAME="kvas-hysteria"
APP_BASE="/opt/apps/${APP_NAME}"
ENV_CONFIG="${APP_BASE}/etc/conf/env.sh" # <-- Путь к общему конфигу переменных
VERSION_FILE="${APP_BASE}/version"

# Определение текущей версии пакета
APP_VER="1.2.0"
if [ -f "$VERSION_FILE" ]; then
    APP_VER=$(cat "$VERSION_FILE" 2>/dev/null | tr -d '\r\n')
elif [ -f "$(dirname "$0")/../version" ]; then
    APP_VER=$(cat "$(dirname "$0")/../version" 2>/dev/null | tr -d '\r\n')
fi

# Импортируем глобальные переменные проекта
if [ -f "$ENV_CONFIG" ]; then
    . "$ENV_CONFIG"
elif [ "$1" = "-v" ] || [ "$1" = "--version" ] || [ "$1" = "-V" ] || [ "$1" = "version" ]; then
    : # Разрешаем вывод версии даже без основного файла конфигурации окружения
else
    echo "Критическая ошибка: Файл конфигурации среды $ENV_CONFIG не найден!"
    exit 1
fi

# Цвета по умолчанию (если env.sh не был загружен)
RED=${RED:-'\033[0;31m'}
GREEN=${GREEN:-'\033[0;32m'}
YELLOW=${YELLOW:-'\033[0;33m'}
BLUE=${BLUE:-'\033[0;34m'}
NC=${NC:-'\033[0m'}

# Пути к компонентам приложения (уже используют APP_BASE)
BIN_PATH="${APP_BASE}/bin/hysteria"
TEMPLATE_CONFIG="${APP_BASE}/etc/conf/config.yaml"
TEMPLATE_INIT="${APP_BASE}/etc/init.d/S99hysteria"
CHECK_SPACE_SCRIPT="${APP_BASE}/etc/ndm/check_space.sh"
TEST_SCRIPT="${APP_BASE}/etc/ndm/test_connection.sh"
WATCHDOG_SCRIPT="${APP_BASE}/etc/ndm/watchdog.sh"

# Глобальные системные пути Entware
FINAL_CONFIG_DIR="/opt/etc/hysteria"
FINAL_CONFIG_PATH="${FINAL_CONFIG_DIR}/config.yaml"
SYSTEM_INIT_PATH="/opt/etc/init.d/S99hysteria"
PIDFILE="/var/run/hysteria.pid"
WATCHDOG_PID="/var/run/hysteria-watchdog.pid"
LOGFILE="/var/log/hysteria.log"

show_status() {
    echo "=== Менеджер Kvas-Hysteria (v${APP_VER}) ==="
    if [ -f "$BIN_PATH" ]; then
        VERSION=$($BIN_PATH -v 2>/dev/null | head -n 1)
        echo -e "Статус: ${GREEN}Установлен${NC} ($VERSION)"
    else
        echo -e "Статус: ${RED}Не установлен${NC}"
    fi

    if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
        echo -e "Служба: ${GREEN}Запущена${NC} (PID: $(cat "$PIDFILE"))"
        if [ -f "$WATCHDOG_PID" ] && kill -0 "$(cat "$WATCHDOG_PID")" 2>/dev/null; then
            echo -e "Мониторинг: ${GREEN}Активен${NC} (PID: $(cat "$WATCHDOG_PID"))"
        else
            echo -e "Мониторинг: ${RED}Не активен${NC}"
        fi
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
    echo "  ${APP_NAME} update [версия]  - Обновить пакет kvas-hysteria (latest/версия/ветка)"
    echo "  ${APP_NAME} install          - Скачать/обновить бинарный файл Hysteria"
    echo "  ${APP_NAME} uninstall        - Полное удаление пакета и интеграции"
    echo "  ${APP_NAME} -v | --version   - Показать текущую версию пакета"
    echo -e "  ${APP_NAME} add [\"link\"]     - Импорт ссылки (без аргументов запросит интерактивный ввод)"
    echo "  ${APP_NAME} test             - Экспресс-тест проксирования туннеля"
    echo "  ${APP_NAME} log              - Просмотр последних строк журнала"
    echo "  ${APP_NAME} start | stop | restart | status"
}

run_test() {
    if [ -f "$TEST_SCRIPT" ]; then "$TEST_SCRIPT"; else return 1; fi
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
        *mips*)
            # Проверяем порядок байтов (ELF header: 5-й байт 01 = LSB/little-endian, 02 = MSB/big-endian)
            ENDIAN_BYTE=$(dd if=/bin/sh bs=1 count=1 skip=5 2>/dev/null | od -b 2>/dev/null | awk 'NR==1 {print $2}')
            if [ "$ENDIAN_BYTE" = "002" ] || [ "$ENDIAN_BYTE" = "2" ]; then
                echo -e "${RED}Ошибка: Архитектура MIPS Big-Endian не поддерживается официальными сборками Hysteria.${NC}"
                exit 1
            else
                BINARY_ARCH="mipsle"
            fi
            ;;
        *x86_64*|*amd64*)             BINARY_ARCH="amd64" ;;
        *i?86*|*x86*)                 BINARY_ARCH="386" ;;
        *)                            BINARY_ARCH="" ;;
    esac

    if [ -z "$BINARY_ARCH" ]; then
        echo -e "${RED}Ошибка: Не удалось определить архитектуру устройства ($ARCH).${NC}"
        exit 1
    fi

    echo "Запрос актуальной версии Hysteria с GitHub..."
    LATEST_VERSION=$(curl -4 -sI --connect-timeout 10 https://github.com/apernet/hysteria/releases/latest | grep -i 'location:' | sed -E 's/.*\/tag\/([^[:space:]\r\n]+).*/\1/')

    if [ -z "$LATEST_VERSION" ] || echo "$LATEST_VERSION" | grep -q "{" ; then
        echo -e "${YELLOW}Предупреждение: Переход на базовый релиз v2.6.0${NC}"
        LATEST_VERSION="app/v2.6.0"
    fi

    # Инициализируем путь к временному файлу
    TMP_BIN_PATH="${BIN_PATH}.tmp"
    rm -f "$TMP_BIN_PATH"

    echo -e "Скачиваем ${BLUE}Hysteria $LATEST_VERSION${NC} для ${YELLOW}$BINARY_ARCH${NC} во временный файл..."
    curl -4 -L --connect-timeout 20 -o "$TMP_BIN_PATH" "https://github.com/apernet/hysteria/releases/download/${LATEST_VERSION}/hysteria-linux-${BINARY_ARCH}"

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
            curl -4 -L --connect-timeout 20 -o "$TMP_BIN_PATH" "https://github.com/apernet/hysteria/releases/download/${LATEST_VERSION}/hysteria-linux-${BINARY_ARCH}-sf"
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

        # Запускаем тест. Если он НЕ прошел (! run_test), то покажем подсказку
        if ! run_test; then
            echo ""
            echo -e "${YELLOW}Возможно, конфигурация устарела или неверна.${NC}"
            echo -e "${YELLOW}Чтобы обновить подключение, выполните команду:${NC}"
            echo -e "  ${BLUE}kvas-hysteria add${NC}"
            echo -e "  или: ${BLUE}kvas-hysteria add \"hysteria2://...\"${NC}"
            echo -e "${RED}Важно:${NC} При передаче аргументом кавычки ${GREEN}\"\"${NC} обязательны!"
        fi
    else
        # Если служба НЕ работала (это первая чистая установка, конфига еще нет)
        echo ""
        echo -e "${YELLOW}Чтобы настроить подключение, выполните команду:${NC}"
        echo -e "  ${BLUE}kvas-hysteria add${NC}"
        echo -e "  или: ${BLUE}kvas-hysteria add \"hysteria2://...\"${NC}"
        echo -e "${RED}Важно:${NC} При передаче аргументом кавычки ${GREEN}\"\"${NC} обязательны!"
    fi
}

add_config() {
    URL="$1"

    # Безопасные права доступа (0600) при создании конфигурации с паролями/ключами
    OLD_UMASK=$(umask)
    umask 077

    # 1. Если аргумент не передан или передан '-' — читаем через read / stdin
    # Это полностью обходит 512-байтный лимит интерактивной строки ash
    if [ -z "$URL" ] || [ "$URL" = "-" ]; then
        echo -e "${YELLOW}Вставьте ссылку (hysteria2://...) или путь к файлу и нажмите Enter:${NC}"
        read -r URL
    fi

    if [ -z "$URL" ]; then
        echo -e "${RED}Ошибка: Не указана ссылка!${NC}"
        exit 1
    fi

    if [ ! -f "$TEMPLATE_CONFIG" ]; then
        echo -e "${RED}Ошибка: Базовый шаблон конфигурации не найден в $TEMPLATE_CONFIG${NC}"
        exit 1
    fi

    # 2. Если передан путь к локальному файлу
    if [ -f "$URL" ]; then
        echo "Чтение из файла $URL..."
        URL=$(cat "$URL")
    fi

    echo "Разбираем конфигурацию пира..."
    URL=$(echo "$URL" | tr -d '[:space:]')
    MAIN_PART=$(echo "$URL" | sed -E 's|h2://||;s|hysteria2://||;s|\?.*||;s|#.*||')
    if ! echo "$MAIN_PART" | grep -q '@'; then
        echo -e "${RED}Ошибка парсинга ссылки (отсутствует разделитель '@').${NC}"
        exit 1
    fi
    AUTH=$(echo "$MAIN_PART" | cut -d'@' -f1)
    SERVER=$(echo "$MAIN_PART" | cut -d'@' -f2 | sed 's|/*$||')
    SNI=$(echo "$URL" | sed -n -E 's/.*([?&])sni=([^&#]*).*/\2/p')
    FP=$(echo "$URL" | sed -n -E 's/.*([?&])fp=([^&#]*).*/\2/p')
    OBFS_TYPE=$(echo "$URL" | sed -n -E 's/.*([?&])obfs=([^&#]*).*/\2/p')
    OBFS_PASS=$(echo "$URL" | sed -n -E 's/.*([?&])obfs-password=([^&#]*).*/\2/p')
    [ -z "$SNI" ] && SNI=$(echo "$SERVER" | cut -d':' -f1)

    if [ -z "$AUTH" ] || [ -z "$SERVER" ]; then
        echo -e "${RED}Ошибка парсинга ссылки.${NC}"
        exit 1
    fi

    mkdir -p "$(dirname "$FINAL_CONFIG_PATH")"
    touch "$FINAL_CONFIG_PATH"
    chmod 600 "$FINAL_CONFIG_PATH"

    # Генерируем верхнюю (динамическую) часть конфига
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

    # ЭЛЕГАНТНОЕ РЕШЕНИЕ: Обрабатываем шаблон через sed, заменяя @ПЛЕЙСХОЛДЕРЫ на переменные,
    # и дописываем результат в рабочий config.yaml
    sed -e "s|@PROXY_LOCAL_IP|${PROXY_LOCAL_IP}|g" \
        -e "s|@PROXY_LOCAL_PORT_SOCKS|${PROXY_LOCAL_PORT_SOCKS}|g" \
        -e "s|@PROXY_LOCAL_PORT_HTTP|${PROXY_LOCAL_PORT_HTTP}|g" \
        "$TEMPLATE_CONFIG" >> "$FINAL_CONFIG_PATH"

    chmod 600 "$FINAL_CONFIG_PATH"
    umask "$OLD_UMASK" 2>/dev/null || true
    echo -e "${GREEN}Конфигурация успешно сгенерирована: $FINAL_CONFIG_PATH${NC}"

    echo "Активация службы автозапуска..."
    ln -sf "$TEMPLATE_INIT" "$SYSTEM_INIT_PATH"

    "$SYSTEM_INIT_PATH" restart
    sleep 2

    # === ИНТЕГРАЦИЯ С KEENETIC RCI API ===
    IFACE_INFO=$(curl -4 -s "http://127.0.0.1:79/rci/show/interface/${KEENETIC_PROXY_NAME}" 2>/dev/null)
    if echo "$IFACE_INFO" | grep -q "\"id\": \"${KEENETIC_PROXY_NAME}\""; then
        echo -e "${GREEN}Интерфейс '${KEENETIC_PROXY_DESC}' (${KEENETIC_PROXY_NAME}) уже существует в KeeneticOS (создание пропущено, маршруты сохранены).${NC}"
        # Убеждаемся, что интерфейс включен (up)
        curl -4 -s -d '[{"interface": {"name": "'${KEENETIC_PROXY_NAME}'", "up": true}}]' "http://127.0.0.1:79/rci/" > /dev/null 2>&1
    else
        echo "Интеграция с KeeneticOS API (регистрация интерфейса)..."
        # В JSON подставляем порт из env.sh (PROXY_LOCAL_PORT_SOCKS вместо старого PROXY_LOCAL_PORT)
        API_DATA='[{
            "interface": {
                "name": "'${KEENETIC_PROXY_NAME}'",
                "description": "'${KEENETIC_PROXY_DESC}'",
                "proxy": {
                    "protocol": { "proto": "'${PROXY_PROTO}'" },
                    "upstream": { "host": "'${PROXY_LOCAL_IP}'", "port": "'${PROXY_LOCAL_PORT_SOCKS}'" },
                    "socks5-udp": true
                }
            },
            "system": { "configuration": { "save": true } }
        }]'

        curl -4 -s -d "${API_DATA}" "http://127.0.0.1:79/rci/" > /dev/null 2>&1
        curl -4 -s -d '[{"interface": {"name": "'${KEENETIC_PROXY_NAME}'", "up": true}}]' "http://127.0.0.1:79/rci/" > /dev/null 2>&1

        echo -e "${GREEN}Интерфейс '${KEENETIC_PROXY_DESC}' (${KEENETIC_PROXY_NAME}) успешно зарегистрирован в KeeneticOS!${NC}"
        echo -e "${YELLOW}Чтобы переключить маршруты Kvas на этот туннель, выполните:${NC}"
        echo -e "  ${BLUE}kvas vpn set${NC}"
        echo ""
    fi
    run_test
}

uninstall_packet() {
    echo "Деактивация и остановка служб..."
    [ -f "$SYSTEM_INIT_PATH" ] && "$SYSTEM_INIT_PATH" stop

    echo "Удаление прокси-интерфейса из KeeneticOS..."
    curl -4 -s -d '[{"interface": { "name": "'${KEENETIC_PROXY_NAME}'","no": true },"system": {"configuration": {"save": true}}}]' "http://127.0.0.1:79/rci/" > /dev/null 2>&1

    echo "Удаление симлинков и файлов пакета..."
    rm -f /opt/bin/kvas-hysteria /opt/bin/hysteria "$SYSTEM_INIT_PATH" "$PIDFILE" "$WATCHDOG_PID" /var/run/hysteria.active "$LOGFILE"
    rm -rf "$FINAL_CONFIG_DIR" "$APP_BASE"
    echo -e "${GREEN}Пакет kvas-hysteria успешно удален.${NC}"
}

update_packet() {
    TARGET="$1"
    FORCE=0

    # Проверка флагов принудительного обновления (--force / -f)
    if [ "$TARGET" = "-f" ] || [ "$TARGET" = "--force" ]; then
        FORCE=1
        TARGET=""
    elif [ "$2" = "-f" ] || [ "$2" = "--force" ]; then
        FORCE=1
    fi

    # Если запрошено обновление бинарника Hysteria
    if [ "$TARGET" = "hysteria" ] || [ "$TARGET" = "bin" ]; then
        install_hysteria
        return $?
    fi

    echo "=== Обновление пакета kvas-hysteria ==="

    # Проверка актуальности версии перед обновлением
    if [ "$FORCE" -eq 0 ]; then
        if [ -z "$TARGET" ] || [ "$TARGET" = "latest" ]; then
            echo "Проверка наличия обновлений на GitHub..."
            LATEST_TAG=$(curl -4 -sI --connect-timeout 10 "https://github.com/${REPO}/releases/latest" 2>/dev/null | \
                        tr -d '\r' | sed -n -E 's/^[Ll]ocation:.*\/tag\/([^[:space:]]+).*/\1/p' | head -n 1)

            if [ -z "$LATEST_TAG" ]; then
                LATEST_TAG=$(curl -4 -sL --connect-timeout 10 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
                            grep -oE '"tag_name": *"[^"]+"' | head -n 1 | cut -d'"' -f4)
            fi

            CURRENT_CLEAN="${APP_VER#v}"
            LATEST_CLEAN="${LATEST_TAG#v}"

            if [ -n "$LATEST_CLEAN" ] && [ "$CURRENT_CLEAN" = "$LATEST_CLEAN" ]; then
                echo -e "${GREEN}У вас уже установлена актуальная версия: ${APP_VER} (latest).${NC}"
                echo "Обновление не требуется."
                echo -e "Для принудительной переустановки выполните: ${BLUE}kvas-hysteria update --force${NC}"
                return 0
            fi

            if [ -n "$LATEST_TAG" ]; then
                echo -e "Доступно обновление: ${YELLOW}${APP_VER}${NC} -> ${GREEN}${LATEST_TAG}${NC}"
            fi
        elif [ "${APP_VER#v}" = "${TARGET#v}" ]; then
            echo -e "${GREEN}Версия ${APP_VER} уже установлена.${NC}"
            echo -e "Для принудительной переустановки выполните: ${BLUE}kvas-hysteria update ${TARGET} --force${NC}"
            return 0
        fi
    fi

    REF="${TARGET:-main}"
    [ "$REF" = "latest" ] && REF="main"

    INSTALL_URL="https://raw.githubusercontent.com/${REPO}/${REF}/install.sh"
    API_URL="https://api.github.com/repos/${REPO}/contents/install.sh?ref=${REF}"
    TMP_INSTALLER="/tmp/kvas_install_$$.sh"

    echo "Загрузка актуального скрипта установки с GitHub (${REF})..."
    DOWNLOADED=0

    # 1. Прямая загрузка через IPv4 (для целевой ветки/релиза)
    if curl -4 -sL -f --connect-timeout 10 -o "$TMP_INSTALLER" "$INSTALL_URL" 2>/dev/null; then
        DOWNLOADED=1
    # 2. Резервный источник через GitHub API (raw-заголовок)
    elif curl -4 -sL -f --connect-timeout 10 -H "Accept: application/vnd.github.raw" -o "$TMP_INSTALLER" "$API_URL" 2>/dev/null; then
        DOWNLOADED=1
    # 3. Fallback на ветку main (если запрошенный тег/ветка не содержит отдельный install.sh)
    elif [ "$REF" != "main" ] && curl -4 -sL -f --connect-timeout 10 -o "$TMP_INSTALLER" "https://raw.githubusercontent.com/${REPO}/main/install.sh" 2>/dev/null; then
        DOWNLOADED=1
    # 4. Резерв через локальный туннель socks5 (если служба активна)
    elif [ -n "${PROXY_LOCAL_PORT_SOCKS}" ] && curl -sL -f --connect-timeout 10 -x "socks5h://${PROXY_LOCAL_IP:-127.0.0.1}:${PROXY_LOCAL_PORT_SOCKS:-10808}" -o "$TMP_INSTALLER" "$INSTALL_URL" 2>/dev/null; then
        DOWNLOADED=1
    fi

    if [ "$DOWNLOADED" -eq 0 ] || [ ! -s "$TMP_INSTALLER" ]; then
        echo -e "${RED}Ошибка: Не удалось скачать скрипт установки с ${INSTALL_URL}${NC}"
        echo "Проверьте доступность интернета."
        rm -f "$TMP_INSTALLER"
        return 1
    fi

    chmod +x "$TMP_INSTALLER"

    INSTALL_TARGET="${TARGET:-${LATEST_TAG:-latest}}"
    ARGS="$INSTALL_TARGET"
    [ "$FORCE" -eq 1 ] && ARGS="$ARGS --force"

    # shellcheck disable=SC2086
    FORCE="$FORCE" sh "$TMP_INSTALLER" $ARGS
    RET=$?

    rm -f "$TMP_INSTALLER"
    return "$RET"
}

show_version() {
    echo "kvas-hysteria version ${APP_VER}"
    if [ -f "$BIN_PATH" ]; then
        BIN_VER=$($BIN_PATH -v 2>/dev/null | head -n 1)
        [ -n "$BIN_VER" ] && echo "$BIN_VER"
    fi
}

show_log() {
    if [ -f "$LOGFILE" ]; then
        echo "=== Журнал $LOGFILE (последние 40 строк) ==="
        tail -n 40 "$LOGFILE"
    else
        echo "Журнал $LOGFILE пуст или не создан."
    fi
}

case "$1" in
    -v|--version|-V|version) show_version ;;
    update|upgrade) update_packet "$2" "$3" ;;
    install)    install_hysteria ;;
    uninstall)  uninstall_packet ;;
    add)        add_config "$2" ;;
    test)       run_test ;;
    log)        show_log ;;
    status)
        if [ -f "$SYSTEM_INIT_PATH" ]; then
            "$SYSTEM_INIT_PATH" status
        else
            show_status
        fi
        ;;
    start|restart)
        if [ -f "$SYSTEM_INIT_PATH" ]; then
            "$SYSTEM_INIT_PATH" "$1"
            sleep 2
            run_test
        else
            echo -e "${RED}Ошибка: Конфигурация не инициализирована. Сначала вызовите add${NC}"
        fi
        ;;
    stop)
        if [ -f "$SYSTEM_INIT_PATH" ]; then
            "$SYSTEM_INIT_PATH" "stop"
        else
            echo -e "${RED}Ошибка: Конфигурация не инициализирована.${NC}"
        fi
        ;;
    *)
        show_status
        ;;
esac
