#!/bin/sh
set -e

REPO="jobgomel/kvas-hysteria"
APPS_DIR="/opt/apps/kvas-hysteria"
TMP_DIR="/tmp/kvas-hysteria-install-$$"
TMP_ARCHIVE="${TMP_DIR}/package.tar.gz"
TMP_ENV="/tmp/kvas_env_backup_$$.sh"
trap 'rm -rf "$TMP_DIR" "$TMP_ENV"' EXIT INT TERM
DIR="$(cd "$(dirname "$0")" && pwd)"
FORCE="${FORCE:-0}"
TARGET_VER=""
for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=1 ;;
        list|-l|--list) TARGET_VER="list" ;;
        *) [ -z "$TARGET_VER" ] && TARGET_VER="$arg" ;;
    esac
done

# 1. Вывод всех доступных тегов через GitHub API
list_versions() {
    echo "Запрос списка версий из репозитория ${REPO}..."
    TAGS=$(curl -4 -sL --connect-timeout 10 "https://api.github.com/repos/${REPO}/tags" | \
           grep -oE '"name": *"[^"]+"' | cut -d'"' -f4)

    if [ -z "$TAGS" ]; then
        echo "Ошибка: Не удалось получить список тегов через GitHub API."
        exit 1
    fi

    echo "Доступные версии для установки:"
    echo "$TAGS" | sed 's/^/  * /'
}

if [ "$TARGET_VER" = "list" ] || [ "$TARGET_VER" = "-l" ] || [ "$TARGET_VER" = "--list" ]; then
    list_versions
    exit 0
fi

echo "=== Установка пакета kvas-hysteria (Hysteria 2) ==="

# 2. Создание структуры папок
mkdir -p "${APPS_DIR}/bin" "${APPS_DIR}/etc/conf" "${APPS_DIR}/etc/init.d" "${APPS_DIR}/etc/ndm" "/opt/etc/hysteria"

# Сохраняем существующий env.sh при обновлении
PRESERVED_ENV=0
if [ -f "${APPS_DIR}/etc/conf/env.sh" ]; then
    PRESERVED_ENV=1
    cp -f "${APPS_DIR}/etc/conf/env.sh" "$TMP_ENV"
fi

# Проверяем, была ли служба запущена до обновления
WAS_RUNNING=0
if [ -f "/var/run/hysteria.pid" ] && kill -0 "$(cat /var/run/hysteria.pid 2>/dev/null)" 2>/dev/null; then
    WAS_RUNNING=1
fi

# 3. Установка из локального каталога или загрузка из GitHub
if [ -d "$DIR/src" ]; then
    echo "Установка компонентов из локального каталога..."
    cp -rf "$DIR/src/"* "${APPS_DIR}/"
    if [ -d "$DIR/.git" ]; then
        GIT_VER=$(git -C "$DIR" describe --tags --always 2>/dev/null)
        [ -n "$GIT_VER" ] && echo "$GIT_VER" > "${APPS_DIR}/version"
    fi
else
    # Определение версии для загрузки
    if [ -z "$TARGET_VER" ] || [ "$TARGET_VER" = "latest" ]; then
        echo "Поиск последнего релиза (latest)..."
        TARGET_TAG=$(curl -4 -sI --connect-timeout 10 "https://github.com/${REPO}/releases/latest" 2>/dev/null | \
                    tr -d '\r' | sed -n -E 's/^[Ll]ocation:.*\/tag\/([^[:space:]]+).*/\1/p' | head -n 1)

        if [ -z "$TARGET_TAG" ]; then
            # Резервный запрос через API, если редирект не сработал
            TARGET_TAG=$(curl -4 -sL --connect-timeout 10 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
                        grep -oE '"tag_name": *"[^"]+"' | head -n 1 | cut -d'"' -f4)
        fi

        if [ -z "$TARGET_TAG" ]; then
            echo "Ошибка: Не удалось определить последний тег."
            exit 1
        fi
        echo "Выбрана последняя стабильная версия: ${TARGET_TAG}"
    else
        TARGET_TAG="$TARGET_VER"
        echo "Запрошена установка версии: ${TARGET_TAG}"
    fi

    # Проверка текущей установленной версии
    CURRENT_VER=""
    if [ -f "${APPS_DIR}/version" ]; then
        CURRENT_VER=$(cat "${APPS_DIR}/version" 2>/dev/null | tr -d '\r\n')
    fi

    if [ "$FORCE" -eq 0 ] && [ -n "$CURRENT_VER" ] && [ "${CURRENT_VER#v}" = "${TARGET_TAG#v}" ]; then
        echo "У вас уже установлена актуальная версия: ${CURRENT_VER}."
        echo "Обновление не требуется. Для принудительной переустановки укажите флаг --force."
        exit 0
    fi

    ARCHIVE_URL="https://github.com/${REPO}/archive/refs/tags/${TARGET_TAG}.tar.gz"
    mkdir -p "$TMP_DIR"

    # Загрузка архива (с проверкой наличия префикса 'v')
    if ! curl -4 -sL -f --connect-timeout 20 -o "$TMP_ARCHIVE" "$ARCHIVE_URL" 2>/dev/null; then
        if [ "${TARGET_TAG#v}" = "$TARGET_TAG" ]; then
            ALT_TAG="v${TARGET_TAG}"
            ALT_URL="https://github.com/${REPO}/archive/refs/tags/${ALT_TAG}.tar.gz"
            if curl -4 -sL -f --connect-timeout 20 -o "$TMP_ARCHIVE" "$ALT_URL" 2>/dev/null; then
                TARGET_TAG="$ALT_TAG"
                ARCHIVE_URL="$ALT_URL"
            fi
        fi
    fi

    # Если по тегу архив не найден, пробуем загрузить ветку (например: main или dev)
    if [ ! -s "$TMP_ARCHIVE" ]; then
        BRANCH_URL="https://github.com/${REPO}/archive/refs/heads/${TARGET_TAG}.tar.gz"
        if curl -4 -sL -f --connect-timeout 20 -o "$TMP_ARCHIVE" "$BRANCH_URL" 2>/dev/null; then
            ARCHIVE_URL="$BRANCH_URL"
        fi
    fi

    if [ ! -s "$TMP_ARCHIVE" ]; then
        echo "Ошибка: Не удалось скачать релиз/ветку '${TARGET_TAG}' (${ARCHIVE_URL})."
        echo "Для просмотра доступных версий выполните команду: install.sh list"
        rm -rf "$TMP_DIR"
        exit 1
    fi

    echo "Распаковка архива версии ${TARGET_TAG}..."
    tar -xzf "$TMP_ARCHIVE" -C "$TMP_DIR"

    SRC_PATH=$(find "$TMP_DIR" -type d -name "src" | head -n 1)
    if [ -n "$SRC_PATH" ] && [ -d "$SRC_PATH" ]; then
        cp -rf "$SRC_PATH/"* "${APPS_DIR}/"
    else
        echo "Ошибка: В архиве не найдена директория src."
        rm -rf "$TMP_DIR"
        exit 1
    fi

    echo "$TARGET_TAG" > "${APPS_DIR}/version"

    rm -rf "$TMP_DIR"
fi

# 4. Передача управления скрипту пост-установки пакета
if [ -f "${APPS_DIR}/bin/setup.sh" ]; then
    chmod +x "${APPS_DIR}/bin/setup.sh"
    sh "${APPS_DIR}/bin/setup.sh" \
        --preserved-env "$PRESERVED_ENV" \
        --env-backup "$TMP_ENV" \
        --was-running "$WAS_RUNNING"
else
    echo "Предупреждение: ${APPS_DIR}/bin/setup.sh не найден."
    chmod +x "${APPS_DIR}/bin/manager.sh" 2>/dev/null || true
    ln -sf "${APPS_DIR}/bin/manager.sh" /opt/bin/kvas-hysteria 2>/dev/null || true
fi
