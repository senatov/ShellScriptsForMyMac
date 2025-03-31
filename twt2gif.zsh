#!/bin/zsh

setopt NO_HIST_IGNORE_SPACE
setopt HIST_NO_STORE

# === Проверка зависимостей ===
for cmd in yt-dlp ffmpeg gifsicle; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Ошибка: $cmd не установлен. Установите его и повторите попытку."
        exit 1
    fi
done

# === Проверка аргументов ===
if [ -z "$1" ]; then
    echo "Использование: $0 <URL> [текст для GIF]"
    exit 1
fi

URL="$1"
TEXT="${2:-''}"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TEMP_DIR=$(mktemp -d)
VIDEO_FILE="$TEMP_DIR/video.mp4"
TRIMMED_VIDEO="$TEMP_DIR/trimmed_video.mp4"
PALETTE_FILE="$TEMP_DIR/palette.png"
OUTPUT_GIF="./${TIMESTAMP}.gif"

# === Параметры для GIF ===
FPS=10
SCALE_WIDTH=360
MAX_COLORS=128
FONT_PATH="/Library/Fonts/Arial.ttf" # macOS
[[ ! -f "$FONT_PATH" ]] && FONT_PATH="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" # Linux fallback

# === Загрузка видео ===
echo "🔽 Загрузка видео с $URL..."
yt-dlp -f 'mp4[height<=720]+bestaudio/best[height<=720]' -o "$VIDEO_FILE" "$URL"

if [ ! -s "$VIDEO_FILE" ]; then
    echo "❌ Ошибка: видео не было загружено."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# === Обрезка видео (первые 5 сек, без звука) ===
echo "✂️  Обрезаем видео до 5 сек..."
ffmpeg -hide_banner -loglevel error -y \
    -i "$VIDEO_FILE" \
    -ss 0 -t 5 -an \
    -c:v libx264 -preset ultrafast -crf 23 \
    "$TRIMMED_VIDEO"

if [ ! -s "$TRIMMED_VIDEO" ]; then
    echo "❌ Ошибка: обрезанное видео не получено."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# === Генерация палитры ===
echo "🎨 Генерация палитры ($MAX_COLORS цветов)..."
ffmpeg -hide_banner -loglevel error -y \
    -i "$TRIMMED_VIDEO" \
    -vf "fps=$FPS,scale=$SCALE_WIDTH:-1:flags=lanczos,palettegen=max_colors=$MAX_COLORS" \
    "$PALETTE_FILE"

if [ ! -s "$PALETTE_FILE" ]; then
    echo "❌ Ошибка: палитра не создана."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# === Генерация GIF с текстом ===
echo "🖼  Генерация GIF с текстом..."
ffmpeg -hide_banner -loglevel error -y \
    -i "$TRIMMED_VIDEO" -i "$PALETTE_FILE" \
    -lavfi "[0:v]fps=$FPS,scale=$SCALE_WIDTH:-1:flags=lanczos,drawtext=fontfile='$FONT_PATH':text='$TEXT':fontcolor=white:fontsize=24:box=1:boxcolor=black@0.5:boxborderw=5:x=(w-text_w)/2:y=h-(text_h*2)[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
    "$OUTPUT_GIF"

if [ ! -s "$OUTPUT_GIF" ]; then
    echo "❌ Ошибка: не удалось создать GIF."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# === Оптимизация GIF ===
echo "✨ Оптимизация GIF через gifsicle..."
gifsicle --optimize=3 --colors="$MAX_COLORS" "$OUTPUT_GIF" -o "$OUTPUT_GIF"

echo "✅ GIF успешно создан: $OUTPUT_GIF"

# === Очистка ===
rm -rf "$TEMP_DIR"