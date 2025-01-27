#!/bin/zsh

###############################################################################
# Скрипт «прокачанного» перекодировщика видео с базовой автонастройкой:
#
#  1. Устанавливает ffmpeg и mediainfo (только для Debian/Ubuntu).
#  2. Анализирует входной файл (разрешение, FPS).
#  3. Если разрешение выше 1920×1080, то уменьшает до 1080p.
#  4. Применяет фильтры:
#       - hqdn3d (для сглаживания шумов в видео),
#       - eq (для лёгкой коррекции цвета/яркости/контраста),
#       - afftdn (для подавления шума в аудио),
#       - acompressor (для сглаживания перепадов громкости).
#  5. Кодирует в MP4 (H.264 + AAC).
#
# Использование:
#   ./enhance_video.sh input_file [output_file]
#
# Пример:
#   ./enhance_video.sh MyVideo.avi MyVideoFixed.mp4
#
###############################################################################

# -----------------------------
# Функция для вывода usage
# -----------------------------
usage() {
  echo "Использование: $0 <input_file> [output_file]"
  echo "Пример: $0 MyVideo.avi MyVideoFixed.mp4"
  exit 1
}

# -----------------------------
# 1. Проверка аргументов
# -----------------------------
if [ -z "$1" ]; then
  usage
fi

INPUT_FILE="$1"

# Если задан второй аргумент, используем его как имя выходного файла,
# иначе формируем имя вида "ИсходноеИмя.enhanced.mp4"
if [ -n "$2" ]; then
  OUTPUT_FILE="$2"
else
  BASENAME="$(basename "$INPUT_FILE")"
  BASENAME_NOEXT="${BASENAME%.*}"
  OUTPUT_FILE="${BASENAME_NOEXT}.enhanced.mp4"
fi

# -----------------------------
# 2. Проверка и установка ffmpeg и mediainfo
# -----------------------------
install_if_missing() {
  local pkg="$1"
  if ! command -v "$pkg" &>/dev/null; then
    echo "$pkg не найден. Пытаемся установить..."
    if command -v apt-get &>/dev/null; then
      sudo apt-get update && sudo apt-get install -y "$pkg"
    else
      echo "Неизвестный дистрибутив. Установите $pkg вручную."
      exit 1
    fi
    # Проверяем ещё раз
    if ! command -v "$pkg" &>/dev/null; then
      echo "Установка $pkg не удалась. Завершаем."
      exit 1
    fi
  fi
}

install_if_missing ffmpeg
install_if_missing mediainfo

# -----------------------------
# 3. Анализ входного файла через mediainfo
# -----------------------------
FPS=$(mediainfo --Inform="Video;%FrameRate%" "$INPUT_FILE" 2>/dev/null)
WIDTH=$(mediainfo --Inform="Video;%Width%" "$INPUT_FILE" 2>/dev/null)
HEIGHT=$(mediainfo --Inform="Video;%Height%" "$INPUT_FILE" 2>/dev/null)

# Если вдруг не удалось извлечь, задаём фиктивные значения, чтобы не ломать скрипт.
# (Не все форматы корректно парсятся mediainfo)
if [ -z "$WIDTH" ] || [ -z "$HEIGHT" ]; then
  WIDTH=0
  HEIGHT=0
fi

echo "Определили параметры входного файла: ${WIDTH}x${HEIGHT}, FPS=${FPS}"

# -----------------------------
# 4. Формируем строку видеофильтров
# -----------------------------
# hqdn3d=1.5:1.5:6:6 -> убирает шумы
# eq=brightness=0.02:contrast=1.1:saturation=1.05 -> лёгкая коррекция яркости/контраста/насыщенности
VIDEO_FILTER="hqdn3d=1.5:1.5:6:6,eq=brightness=0.02:contrast=1.1:saturation=1.05"

# Если разрешение больше 1920x1080, то добавляем scale до 1080p
if [ "$WIDTH" -gt 1920 ] || [ "$HEIGHT" -gt 1080 ]; then
  # -2 означает «автоматически подобрать ширину/высоту, чтобы сохранить соотношение сторон»
  # при условии, что итоговое значение будет кратно 2 (требование некоторых кодеков).
  VIDEO_FILTER="scale=-2:1080,${VIDEO_FILTER}"
  echo "Включено масштабирование до 1080p (исходное выше Full HD)."
fi

# -----------------------------
# 5. Формируем строку аудиофильтров
# -----------------------------
# afftdn -> удаление фоновых шумов
# acompressor -> выравнивание громкости (динамический компрессор)
AUDIO_FILTER="afftdn,acompressor"

# -----------------------------
# 6. Сборка команды ffmpeg
# -----------------------------
# -map 0:v:0 -map 0:a:0 можно использовать, если надо брать ТОЛЬКО первую видеодорожку и первую аудiodорожку
# и игнорировать лишние потоки (например, те самые mjpeg-обложки, метаданные и т.п.).
# Однако часто -map по умолчанию тоже сработает хорошо, просто может выдавать ошибки по «лишним» потокам.

FFMPEG_CMD=(
  ffmpeg -y
  -i "$INPUT_FILE"
  # Если хотим убрать «проблемные» mjpeg-потоки (например, обложки), можно явно указать:
  # -map 0:v:0 -map 0:a:0
  -c:v libx264
  -preset medium
  -crf 23
  -vf "$VIDEO_FILTER"
  -c:a aac
  -b:a 128k
  -af "$AUDIO_FILTER"
  "$OUTPUT_FILE"
)

echo
echo "========================================="
echo " Запускаем перекодирование с параметрами:"
echo "   Входной файл:  $INPUT_FILE"
echo "   Выходной файл: $OUTPUT_FILE"
echo "   Видеофильтры:  $VIDEO_FILTER"
echo "   Аудиофильтры:  $AUDIO_FILTER"
echo "========================================="
echo

# -----------------------------
# 7. Запуск ffmpeg
# -----------------------------
"${FFMPEG_CMD[@]}"

# -----------------------------
# 8. Проверяем результат
# -----------------------------
if [ $? -eq 0 ]; then
  echo "Перекодирование успешно завершено!"
  echo "Выходной файл: $OUTPUT_FILE"
else
  echo "Произошла ошибка при перекодировании."
  exit 1
fi
