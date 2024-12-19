#!/bin/bash

# Проверка наличия необходимых утилит
for cmd in yt-dlp ffmpeg gifsicle; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Ошибка: $cmd не установлен. Установите его и повторите попытку."
        exit 1
    fi
done

# Автоматическое обновление yt-dlp
echo "Проверяем актуальность yt-dlp..."
pip install --upgrade yt-dlp >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "yt-dlp обновлён до последней версии."
else
    echo "Ошибка: не удалось обновить yt-dlp. Проверьте подключение к интернету."
    exit 1
fi

# Проверка URL
if [ -z "$1" ]; then
    echo "Использование: $0 <URL> [текст для GIF]"
    exit 1
fi

URL="$1"
TEXT="${2:-''}" # Текст по умолчанию
TEMP_DIR=$(mktemp -d)
VIDEO_FILE="$TEMP_DIR/video.mp4"
TRIMMED_VIDEO="$TEMP_DIR/trimmed_video.mp4"
EXTENDED_VIDEO="$TEMP_DIR/extended_video.mp4"
PALETTE_FILE="$TEMP_DIR/palette.png"
OUTPUT_GIF="./$(uuidgen | head -c 8).gif"

# Загрузка видео
echo "Загружаем видео из $URL..."
yt-dlp -o "$VIDEO_FILE" "$URL"
if [ ! -s "$VIDEO_FILE" ]; then
    echo "Ошибка: не удалось загрузить видео."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Обрезка видео
echo "Обрезаем видео..."
ffmpeg -y -i "$VIDEO_FILE" -ss 00:00:00 -to 00:00:05 -c:v libx264 -preset ultrafast "$TRIMMED_VIDEO"
if [ ! -s "$TRIMMED_VIDEO" ]; then
    echo "Ошибка: обрезанное видео пустое."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Проверка длины видео
DURATION=$(ffprobe -i "$TRIMMED_VIDEO" -show_entries format=duration -v quiet -of csv="p=0")
if (( $(echo "$DURATION < 1.0" | bc -l) )); then
    echo "Видео слишком короткое ($DURATION сек). Увеличиваем длину..."
    ffmpeg -y -stream_loop 4 -i "$TRIMMED_VIDEO" -t 2 -c:v libx264 -preset ultrafast "$EXTENDED_VIDEO"
    TRIMMED_VIDEO="$EXTENDED_VIDEO"
fi

# Генерация палитры
echo "Генерируем палитру..."
ffmpeg -y -i "$TRIMMED_VIDEO" -vf "fps=15,scale=480:-1:flags=lanczos,palettegen" "$PALETTE_FILE"
if [ ! -s "$PALETTE_FILE" ]; then
    echo "Ошибка: не удалось создать палитру."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Создание GIF с текстом
echo "Создаём GIF с текстом..."
ffmpeg -y -i "$TRIMMED_VIDEO" -i "$PALETTE_FILE" -lavfi "fps=15,scale=480:-1:flags=lanczos,drawtext=text='$TEXT':fontcolor=white:fontsize=24:box=1:boxcolor=black@0.5:boxborderw=5:x=(w-text_w)/2:y=h-(text_h*2):fontfile=/Library/Fonts/Arial.ttf [x];[x][1:v]paletteuse" "$OUTPUT_GIF"
if [ ! -s "$OUTPUT_GIF" ]; then
    echo "Ошибка: не удалось создать GIF."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Оптимизация GIF
echo "Оптимизируем GIF..."
gifsicle --optimize=3 "$OUTPUT_GIF" -o "$OUTPUT_GIF"

echo "GIF успешно создан: $OUTPUT_GIF"

# Очистка временных файлов
rm -rf "$TEMP_DIR"