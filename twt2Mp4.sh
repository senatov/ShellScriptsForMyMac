#!/bin/bash

# Зависимости: yt-dlp, ffmpeg
# Убедитесь, что они установлены:
# sudo apt install ffmpeg
# sudo curl -L https://yt-dlp.org/downloads/latest/yt-dlp -o /usr/local/bin/yt-dlp
# sudo chmod a+rx /usr/local/bin/yt-dlp

# Проверяем наличие URL
if [ -z "$1" ]; then
  echo "Использование: $0 <URL Twitter>"
  exit 1
fi

# URL видео с Twitter
TWITTER_URL="$1"

# Выводим информацию о процессе
echo "Загрузка видео с Twitter: $TWITTER_URL"

# Создаём уникальное имя для временного и выходного файла
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TEMP_FILE="temp_video_${TIMESTAMP}.mp4"
OUTPUT_FILE="${TIMESTAMP}.mp4"

# Загрузка видео с использованием yt-dlp
yt-dlp --output "${TEMP_FILE}" "$TWITTER_URL"

# Проверяем, было ли успешно скачано видео
if [ ! -f "${TEMP_FILE}" ]; then
  echo "Ошибка: Видео не удалось скачать."
  exit 2
fi

echo "Видео успешно скачано: ${TEMP_FILE}"

# Конвертация видео в удобный формат MP4 с использованием ffmpeg
ffmpeg -i "${TEMP_FILE}" -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k "${OUTPUT_FILE}"

# Проверяем, успешно ли конвертировалось видео
if [ $? -eq 0 ]; then
  echo "Видео успешно конвертировано в формат MP4: ${OUTPUT_FILE}"
else
  echo "Ошибка при конвертации видео."
  rm -f "${TEMP_FILE}"
  exit 3
fi

# Убираем временный файл
rm -f "${TEMP_FILE}"

echo "Процесс завершён. Итоговый файл: ${OUTPUT_FILE}"