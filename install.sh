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
curl -sL -o "${APPS_DIR}/bin/kvas-hysteria" "${REPO_RAW}/src/bin/kvas-hysteria"
curl -sL -o "${APPS_DIR}/etc/conf/config.yaml" "${REPO_RAW}/src/etc/conf/config.yaml"
curl -sL -o "${APPS_DIR}/etc/init.d/S99hysteria" "${REPO_RAW}/src/etc/init.d/S99hysteria"

if [ ! -s "${APPS_DIR}/bin/kvas-hysteria" ]; then
    echo "Ошибка: Не удалось скачать файлы из репозитория."
    exit 1
fi

chmod +x "${APPS_DIR}/bin/kvas-hysteria"
chmod +x "${APPS_DIR}/etc/init.d/S99hysteria"

# 3. Создание системных симлинков для CLI
ln -sf "${APPS_DIR}/bin/kvas-hysteria" /opt/bin/kvas-hysteria

# 4. Запуск внутреннего процесса установки бинарного файла Hysteria
/opt/bin/kvas-hysteria install