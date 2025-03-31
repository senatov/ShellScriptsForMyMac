#!/bin/zsh

setopt NO_HIST_IGNORE_SPACE  # Отключает запись в историю
setopt HIST_NO_STORE   

# Проверяем наличие FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "Ошибка: FFmpeg не установлен. Установите его через пакетный менеджер (например, brew install ffmpeg)."
    exit 1
fi

# Проверяем аргументы
if [ "$#" -lt 1 ]; then
    echo "Использование: $0 input.webm [output.gif]"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-output.gif}" # Если второй аргумент не задан, сохраняем как output.gif

# Конвертация webm в GIF
echo "Конвертация $INPUT_FILE в $OUTPUT_FILE..."
ffmpeg -i "$INPUT_FILE" -vf "fps=30,scale=512:-1:flags=lanczos" -y "$OUTPUT_FILE"
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось создать GIF файл."
    exit 1
fi

echo "Готово! GIF файл сохранён как $OUTPUT_FILE."