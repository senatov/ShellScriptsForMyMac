#!/bin/zsh

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 input.tgs"
  exit 1
fi

input="$1"

if [[ "${input:e}" != "tgs" ]]; then
  echo "❌ Input must be a .tgs file"
  exit 2
fi

if [[ ! -f "$input" ]]; then
  echo "❌ File not found: $input"
  exit 3
fi

timestamp=$(date "+%Y%m%d_%H%M%S")
basename="${input:t:r}"
tmpdir="/tmp/tgs2gif_${timestamp}"
mkdir -p "$tmpdir"

echo "🔧 Decompressing $input to animation.json..."
zstd -d < "$input" > "$tmpdir/animation.json" || { echo "❌ Failed to decompress .tgs"; exit 4; }

echo "🎬 Rendering MP4 with lottie_convert.py..."
lottie_convert.py "$tmpdir/animation.json" "$tmpdir/output.mp4" --output-format video --fps 30 || { echo "❌ lottie_convert failed"; exit 5; }

if [[ ! -f "$tmpdir/output.mp4" ]]; then
  echo "❌ MP4 was not created"
  exit 6
fi

outgif="${input:h}/${basename}_${timestamp}.gif"

echo "🎞 Converting MP4 to GIF with ffmpeg..."
ffmpeg -hide_banner -loglevel error -y -i "$tmpdir/output.mp4" -vf "scale=512:-1:flags=lanczos" "$outgif" || { echo "❌ ffmpeg failed"; exit 7; }

echo "🗑 Moving original .tgs to Trash..."
mv "$input" ~/.Trash/

echo "✅ Done: $outgif"

# Путь к текущему скрипту
SCRIPT_NAME="$(basename "$0")"

# Временно отключим автосохранение истории
setopt no_hist_save

# Удалим все строки, содержащие имя скрипта, из zsh_history
sed -i '' "/$SCRIPT_NAME/d" ~/.zsh_history

# Сбросим текущую историю
fc -p

# Перечитаем историю (чтобы очистить её из памяти)
fc -R