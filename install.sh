#!/bin/sh

SCRIPT_URL="https://raw.githubusercontent.com/jobgomel/kvas-hysteria/main/hysteria.sh"

echo "Загрузка менеджера Hysteria 2..."
mkdir -p /opt/etc/hysteria

curl -L -o /opt/etc/hysteria/hysteria.sh "$SCRIPT_URL"

if [ ! -s "/opt/etc/hysteria/hysteria.sh" ]; then
    echo "Ошибка: Не удалось скачать управляющий скрипт."
    exit 1
fi

chmod +x /opt/etc/hysteria/hysteria.sh
ln -sf /opt/etc/hysteria/hysteria.sh /opt/bin/hysteria.sh

# Запускаем внутреннюю установку бинарников
/opt/bin/hysteria.sh install
