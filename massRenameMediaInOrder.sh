#!/bin/bash

# Проверка, установлен ли exiftool
if ! command -v exiftool &>/dev/null; then
    echo "ExifTool не установлен. Установите его через 'brew install exiftool'."
    exit 1
fi

# Устанавливаем шаблон для имени
template="2007.09.DR.Boris"
counter=1

# Переходим в текущую директорию
cd "$(pwd)"

# Перебираем все файлы в текущей директории
for file in *; do
    # Пропускаем каталоги
    if [[ -d "$file" ]]; then
        continue
    fi

    # Извлекаем дату создания файла
    date_created=$(exiftool -s -s -s -CreateDate "$file" 2>/dev/null | tr ':' '-')

    # Если данные недоступны, используем дату изменения файла
    if [[ -z "$date_created" ]]; then
        date_created=$(date -r "$file" +"%Y-%m-%d")
    fi

    # Извлекаем расширение файла
    extension="${file##*.}"

    # Формируем новое имя файла
    new_name=$(printf "%s-%03d.%s" "$template" "$counter" "$extension")

    # Переименовываем файл
    mv -v "$file" "$new_name"

    # Увеличиваем счётчик
    ((counter++))
done

echo "Все файлы успешно переименованы!"