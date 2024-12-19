#!/bin/bash

# Лог-файл в правильной директории
LOG_FILE="/var/log/time_machine_cleanup.log"
exec > >(tee -i $LOG_FILE)
exec 2>&1

BACKUP_DRIVE="/Volumes/TimeMachine" # Укажите путь к вашему диску Time Machine

echo "=== Очистка Time Machine начата ==="

# Проверка root-доступа
if [ "$EUID" -ne 0 ]; then
    echo "Для выполнения скрипта требуются права администратора. Запустите с sudo."
    exit 1
fi

# Проверка и создание лог-файла, если его нет
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE" || { echo "Ошибка создания лог-файла: $LOG_FILE. Проверьте права."; exit 1; }
    chmod 640 "$LOG_FILE" || echo "Ошибка изменения прав на лог-файл."
fi

# Получение свободного места на диске
get_free_space() {
    df -h "$1" | awk 'NR==2 {print $4}'
}

# Информация о дисковом пространстве до начала работы
FREE_SPACE_BEFORE=$(get_free_space "$BACKUP_DRIVE")
echo "Свободное место на диске $BACKUP_DRIVE до работы: $FREE_SPACE_BEFORE"

CURRENT_DATE=$(date +%s)
WEEK_SECONDS=$((7 * 24 * 60 * 60))
FIVE_MONTHS_SECONDS=$((5 * 30 * 24 * 60 * 60))

if [ ! -d "$BACKUP_DRIVE" ]; then
    echo "Диск Time Machine не найден по пути $BACKUP_DRIVE. Проверьте подключение."
    exit 1
fi

get_backup_age() {
    local backup_date=$1
    local backup_seconds=$(date -j -f "%Y-%m-%d-%H%M%S" "$backup_date" +%s)
    echo $((CURRENT_DATE - backup_seconds))
}

BACKUP_LIST=$(tmutil listbackups | grep "$BACKUP_DRIVE")

if [ -z "$BACKUP_LIST" ]; then
    echo "Бэкапы Time Machine не найдены. Завершаем скрипт."
    exit 0
fi

for backup in $BACKUP_LIST; do
    BACKUP_NAME=$(basename "$backup")
    BACKUP_DATE=$(echo "$BACKUP_NAME" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}")

    if [ -z "$BACKUP_DATE" ]; then
        echo "Не удалось извлечь дату из имени бэкапа: $BACKUP_NAME. Пропускаем."
        continue
    fi

    BACKUP_AGE=$(get_backup_age "$BACKUP_DATE")

    if [ "$BACKUP_AGE" -lt "$WEEK_SECONDS" ]; then
        echo "Бэкап $BACKUP_NAME младше недели. Пропускаем."
        continue
    fi

    if [ "$BACKUP_AGE" -gt "$FIVE_MONTHS_SECONDS" ]; then
        MONTH=$(date -j -f "%Y-%m-%d-%H%M%S" "$BACKUP_DATE" "+%Y-%m")
        echo "Бэкап $BACKUP_NAME старше 5 месяцев. Помещаем в папку $MONTH."

        if [ ! -d "$BACKUP_DRIVE/$MONTH" ]; then
            mkdir -p "$BACKUP_DRIVE/$MONTH"
            cp -r "$backup" "$BACKUP_DRIVE/$MONTH" || echo "Ошибка копирования $BACKUP_NAME в $MONTH."
        else
            echo "Помесячный бэкап за $MONTH уже существует. Пропускаем."
        fi

        tmutil delete "$backup" || echo "Ошибка удаления бэкапа $BACKUP_NAME."
        continue
    fi

    echo "Бэкап $BACKUP_NAME старше недели, но младше 5 месяцев. Удаляем."
    tmutil delete "$backup" || echo "Ошибка удаления бэкапа $BACKUP_NAME."
done

# Информация о дисковом пространстве после завершения работы
FREE_SPACE_AFTER=$(get_free_space "$BACKUP_DRIVE")

echo -e "\n=== Итоги работы скрипта ==="
echo "Свободное место на диске $BACKUP_DRIVE до работы: $FREE_SPACE_BEFORE"
echo "Свободное место на диске $BACKUP_DRIVE после работы: $FREE_SPACE_AFTER"
echo "================================"