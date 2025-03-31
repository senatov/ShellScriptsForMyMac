#!/bin/zsh

setopt NO_HIST_IGNORE_SPACE
setopt HIST_NO_STORE

# 🧰 Зависимости: yt-dlp, ffmpeg
# Установка (если не установлены):
#   brew install ffmpeg
#   brew install yt-dlp

# === Проверка аргументов ===
if [ -z "$1" ]; then
    echo "❌ Использование: $0 <URL Twitter/X>"
    exit 1
fi

TWITTER_URL="$1"

# === Проверка наличия yt-dlp и ffmpeg ===
if ! command -v yt-dlp >/dev/null 2>&1; then
    echo "❌ yt-dlp не установлен. Установите его через brew: brew install yt-dlp"
    exit 2
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "❌ ffmpeg не установлен. Установите его через brew: brew install ffmpeg"
    exit 3
fi

# === Генерация временных имён файлов ===
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TEMP_FILE="temp_${TIMESTAMP}.mp4"
OUTPUT_FILE="${TIMESTAMP}.mp4"

echo "🌐 Скачивание видео с X (Twitter): $TWITTER_URL"

# === Загрузка видео с помощью yt-dlp ===
yt-dlp \
    --output "${TEMP_FILE}" \
    --no-mtime \
    --restrict-filenames \
    --merge-output-format mp4 \
    --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
    "$TWITTER_URL"

# === Проверка успешности загрузки ===
if [ ! -f "${TEMP_FILE}" ]; then
    echo "❌ Ошибка: Видео не удалось скачать."
    exit 4
fi

echo "✅ Видео успешно скачано: ${TEMP_FILE}"

# === Перекодирование с помощью ffmpeg (при необходимости) ===
ffmpeg -hide_banner -loglevel error -y \
    -i "${TEMP_FILE}" \
    -c:v libx264 -preset fast -crf 23 \
    -c:a aac -b:a 128k \
    "${OUTPUT_FILE}"

if [ $? -ne 0 ]; then
    echo "❌ Ошибка при конвертации видео."
    rm -f "${TEMP_FILE}"
    exit 5
fi

# === Очистка временных файлов ===
rm -f "${TEMP_FILE}"

echo "🎉 Готово! Итоговый файл: ${OUTPUT_FILE}"