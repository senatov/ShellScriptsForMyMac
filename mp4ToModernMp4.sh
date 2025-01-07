#!/bin/bash

# Проверяем наличие FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "FFmpeg не установлен. Установите его через 'brew install ffmpeg'."
    exit 1
fi

# Создаём директорию для выходных файлов
output_dir="./converted_videos"
mkdir -p "$output_dir"

# Список расширений для обработки
extensions=("*.avi" "*.mpg" "*.wmv" "*.mov" "*.flv" "*.mkv" "*.mp4")

# Обрабатываем файлы
for ext in "${extensions[@]}"; do
    find . -type f -iname "$ext" | while read -r input_file; do
        base_name=$(basename "$input_file")
        output_file="$output_dir/${base_name%.*}.mp4"

        echo "Обработка файла: $input_file -> $output_file"

        # Улучшение видео
        if ffmpeg -i "$input_file" -vf "eq=brightness=0.05:contrast=1.3:saturation=1.5,unsharp" \
            -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k "$output_file" -y; then
            echo "Успешно обработан: $output_file"
        else
            echo "Ошибка обработки файла: $input_file, пропускаем"
        fi
    done
done

echo "Обработка завершена. Все файлы сохранены в $output_dir"