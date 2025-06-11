#!/bin/zsh

# Проверка входного аргумента
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 input.mp4"
  exit 1
fi

input="$1"
if [[ ! -f "$input" ]]; then
  echo "❌ File not found: $input"
  exit 2
fi

# Выходной файл
ext="${input##*.}"
basename="${input:h}/${input:t:r}_modern.${ext}"

echo "🔧 Converting $input → $basename ..."
ffmpeg -hide_banner -loglevel error -y \
  -i "$input" \
  -c:v libx264 -preset veryslow -crf 23 \
  -c:a aac -b:a 192k \
  -movflags +faststart \
  "$basename"

# Проверка результата
if [[ $? -eq 0 ]]; then
  echo "✅ Conversion successful. Sending original to system Trash..."
  trash "$input" || {
    echo "⚠️ 'trash' utility not found. Install it with: brew install trash"
    exit 3
  }
else
  echo "❌ Conversion failed. Original file not removed."
  exit 4
fi