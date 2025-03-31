#!/bin/zsh

# Проверяем наличие FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "FFmpeg не установлен. Установите его через 'brew install ffmpeg'."
    exit 1
fi

# Директория для выходных файлов
output_dir="./converted_videos"
mkdir -p "$output_dir"

# Расширения для поиска
extensions=("avi" "mpg" "wmv" "mov" "flv" "mkv" "mp4")

# Функция удаления чёрных рамок (по желанию можно убрать)
remove_borders_filter="crop=in_w-2*10:in_h-2*10:10:10"

# Обработка файлов
for ext in "${extensions[@]}"; do
    find . -type f -iname "*.${ext}" | while IFS= read -r input_file; do
        base_name="$(basename "${input_file%.*}")"
        output_file="${output_dir}/${base_name}.mp4"

        echo "▶️ Обработка файла: $input_file -> $output_file"

        # Обработка с фильтрами: улучшение, удаление рамок, и перекодирование
        if ffmpeg -i "$input_file" \
            -vf "cropdetect=24:16:0,${remove_borders_filter},eq=brightness=0.05:contrast=1.3:saturation=1.5,unsharp" \
            -c:v libx264 -crf 22 -preset slow \
            -c:a aac -b:a 192k \
            -movflags +faststart \
            "$output_file" -y; then
            echo "✅ Успешно обработан: $output_file"
        else
            echo "❌ Ошибка обработки файла: $input_file, пропускаем"
        fi
    done
done

echo "🎉 Обработка завершена. Все файлы сохранены в $output_dir"