#!/bin/sh

REPO_RAW="https://raw.githubusercontent.com/jobgomel/kvas-hysteria/task_1_2"
APPS_DIR="/opt/apps/kvas-hysteria"

echo "=== Установка пакета kvas-hysteria ==="

# 1. Создание изолированной структуры папок
mkdir -p "${APPS_DIR}/bin"
mkdir -p "${APPS_DIR}/etc/conf"
mkdir -p "${APPS_DIR}/etc/init.d"
mkdir -p "${APPS_DIR}/etc/ndm"
mkdir -p "/opt/etc/hysteria"

# 2. Скачивание компонентов из репозитория
echo "Загрузка управляющего скрипта и шаблонов..."
curl -sL -o "${APPS_DIR}/bin/manager.sh" "${REPO_RAW}/src/bin/manager.sh"
curl -sL -o "${APPS_DIR}/etc/conf/config.yaml" "${REPO_RAW}/src/etc/conf/config.yaml"
curl -sL -o "${APPS_DIR}/etc/init.d/S99hysteria" "${REPO_RAW}/src/etc/init.d/S99hysteria"
curl -sL -o "${APPS_DIR}/etc/ndm/check_space.sh" "${REPO_RAW}/src/etc/ndm/check_space.sh"

# Проверка на 404 ошибку GitHub
if [ ! -s "${APPS_DIR}/bin/manager.sh" ] || grep -q "404:" "${APPS_DIR}/bin/manager.sh"; then
    echo "Ошибка: Не удалось скачать файлы из репозитория. Проверьте имя ветки и пути."
    exit 1
fi

chmod +x "${APPS_DIR}/bin/manager.sh"
chmod +x "${APPS_DIR}/etc/init.d/S99hysteria"
chmod +x "${APPS_DIR}/etc/ndm/check_space.sh"

# 3. Создание системного симлинка без расширения .sh
ln -sf "${APPS_DIR}/bin/manager.sh" /opt/bin/kvas-hysteria

# 4. Запуск внутренней установки бинарника Hysteria
/opt/bin/kvas-hysteria install