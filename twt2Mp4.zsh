#!/bin/zsh

unsetopt APPEND_HISTORY       # не писать историю в файл во время выполнения
unsetopt INC_APPEND_HISTORY   # не писать историю инкрементально
unsetopt SHARE_HISTORY        # не шарить историю между сессиями
setopt HIST_IGNORE_SPACE      # строки, начинающиеся с пробела, не сохраняются
HISTFILE=/dev/null            # история в никуда
HISTSIZE=0
SAVEHIST=0
fc -p /dev/null               # приватный стек истории (вернём позже fc -P)

# 🧰 Зависимости: yt-dlp, ffmpeg

# === Проверка аргументов ===
if [ -z "$1" ]; then
    echo "❌ Использование: $0 <URL Twitter/X> [--crop]"
    exit 1
fi

TWITTER_URL="$1"
CROP_ENABLED="no"

if [[ "$2" == "--crop" ]]; then
    CROP_ENABLED="yes"
fi

# === Проверка утилит ===
if ! command -v yt-dlp >/dev/null 2>&1; then
    echo "❌ yt-dlp не установлен. Установите: brew install yt-dlp"
    exit 2
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "❌ ffmpeg не установлен. Установите: brew install ffmpeg"
    exit 3
fi

# === Имена файлов ===
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TEMP_FILE="temp_${TIMESTAMP}.mp4"
OUTPUT_FILE="${TIMESTAMP}.mp4"

echo "🌐 Скачивание видео: $TWITTER_URL"

# === Загрузка видео ===
yt-dlp \
    --output "${TEMP_FILE}" \
    --no-mtime \
    --restrict-filenames \
    --merge-output-format mp4 \
    --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
    "$TWITTER_URL"

if [ ! -f "${TEMP_FILE}" ]; then
    echo "❌ Ошибка: Видео не скачано."
    exit 4
fi

echo "✅ Видео скачано: ${TEMP_FILE}"

# === Обрезка (если включена) ===
if [[ "$CROP_ENABLED" == "yes" ]]; then
    echo "✂️  Определение обрезки..."
    CROP_FILTER=$(ffmpeg -i "${TEMP_FILE}" -vf "cropdetect" -frames:v 100 -f null - 2>&1 | \
                  grep -o "crop=[^ ]*" | sort | uniq -c | sort -nr | head -n 1 | cut -d' ' -f2)
    echo "🔧 Применение crop: $CROP_FILTER"

    ffmpeg -hide_banner -loglevel error -y \
        -i "${TEMP_FILE}" \
        -vf "${CROP_FILTER}" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k \
        "${OUTPUT_FILE}"
else
    ffmpeg -hide_banner -loglevel error -y \
        -i "${TEMP_FILE}" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k \
        "${OUTPUT_FILE}"
fi

if [ $? -ne 0 ]; then
    echo "❌ Ошибка при обработке видео."
    rm -f "${TEMP_FILE}"
    exit 5
fi

