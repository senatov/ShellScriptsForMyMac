#!/bin/zsh

set -e

# 🎯 Проверка аргумента
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <file.webp|file.webm>"
  exit 1
fi

INPUT="$1"

# Проверка существования файла
if [[ ! -f "$INPUT" ]]; then
  echo "❌ File not found: $INPUT"
  exit 1
fi

# Расширение и базовое имя
ext="${INPUT##*.}"
BASENAME=$(basename "$INPUT" .$ext)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTFILE="./${TIMESTAMP}.gif"

# Проверка расширения
if [[ "$ext" != "webm" && "$ext" != "webp" ]]; then
  echo "❌ Unsupported input format: .$ext"
  exit 1
fi

echo "🎨 Converting $INPUT → $OUTFILE..."

# Конвертация с ffmpeg
ffmpeg -i "$INPUT" -vf "fps=12,scale=512:-1:flags=lanczos" -c:v gif "$OUTFILE"

# Удаление оригинала в корзину (macOS)
echo "🗑 Moving original file to Trash..."
osascript -e "tell application \"Finder\" to delete POSIX file \"$(realpath "$INPUT")\""

echo "✅ Done! Output saved to: $OUTFILE"