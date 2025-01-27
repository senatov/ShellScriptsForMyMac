#!/bin/zsh

# Лог-файл
LOG_FILE="/var/log/time_machine_cleanup.log"

# Проверка root-доступа
if [ "$EUID" -ne 0 ]; then
    echo "Скрипт требует прав администратора. Перезапуск с sudo..."
    exec sudo "$0" "$@"
fi

exec > >(sudo tee -i $LOG_FILE)
exec 2>&1

BACKUP_DRIVE="/Volumes/MAC_BACKUP" # Укажите путь к вашему диску
CURRENT_DATE=$(date +%s)
WEEK_SECONDS=$((7 * 24 * 60 * 60))
FIVE_MONTHS_SECONDS=$((5 * 30 * 24 * 60 * 60))

echo "=== Очистка резервных копий начата ==="

# Проверка наличия диска
if [ ! -d "$BACKUP_DRIVE" ]; then
    echo "Диск $BACKUP_DRIVE не найден. Завершаем скрипт."
    exit 1
fi

# Получение свободного места
get_free_space() {
    df -h "$1" | awk 'NR==2 {print $4}'
}

# Информация о свободном месте
FREE_SPACE_BEFORE=$(get_free_space "$BACKUP_DRIVE")
echo "Свободное место на диске $BACKUP_DRIVE до работы: $FREE_SPACE_BEFORE"

# Перебор директорий вручную
echo "Ищем резервные копии на $BACKUP_DRIVE..."
for backup_dir in "$BACKUP_DRIVE"/*; do
    if [ -d "$backup_dir" ]; then
        BACKUP_NAME=$(basename "$backup_dir")
        echo "Обрабатываем $BACKUP_NAME..."

        # Извлечение даты из имени директории
        BACKUP_DATE=$(echo "$BACKUP_NAME" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}")
        if [ -z "$BACKUP_DATE" ]; then
            echo "Дата не найдена в имени директории. Пропускаем."
            continue
        fi

        # Вычисление возраста
        BACKUP_SECONDS=$(date -j -f "%Y-%m-%d" "$BACKUP_DATE" +%s)
        BACKUP_AGE=$((CURRENT_DATE - BACKUP_SECONDS))

        # Удаление или перенос
        if [ "$BACKUP_AGE" -gt "$FIVE_MONTHS_SECONDS" ]; then
            echo "Директория $BACKUP_NAME старше 5 месяцев. Удаляем."
            sudo rm -rf "$backup_dir" || echo "Ошибка при удалении $BACKUP_NAME."
        elif [ "$BACKUP_AGE" -gt "$WEEK_SECONDS" ]; then
            echo "Директория $BACKUP_NAME старше недели, но младше 5 месяцев. Пропускаем."
        else
            echo "Директория $BACKUP_NAME младше недели. Пропускаем."
        fi
    fi
done

# Информация о свободном месте после работы
FREE_SPACE_AFTER=$(get_free_space "$BACKUP_DRIVE")
echo "Свободное место на диске $BACKUP_DRIVE до работы: $FREE_SPACE_BEFORE"
echo "Свободное место на диске $BACKUP_DRIVE после работы: $FREE_SPACE_AFTER"
echo "=================================="