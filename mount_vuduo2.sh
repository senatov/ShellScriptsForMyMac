#!/bin/bash

# Переменные
SERVER="smb://root:aaa@http://192.168.178.30/share"  # Замените "share" на имя папки на сервере
MOUNT_POINT="/Volumes/Vuduo2"        # Точка монтирования

# Создаём папку для монтирования, если её нет
if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT"
fi

# Монтируем SMB-ресурс
mount_smbfs "$SERVER" "$MOUNT_POINT" || echo "Ошибка монтирования ресурса $SERVER"