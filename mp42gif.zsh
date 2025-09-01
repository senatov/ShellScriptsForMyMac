#!/bin/zsh

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 input.mp4"
  exit 1
fi

input="$1"
if [[ ! -f "$input" ]]; then
  echo "❌ File not found: $input"
  exit 2
fi

# Имя выходного файла по дате/времени
timestamp=$(date "+%Y%m%d_%H%M%S")
output="./${timestamp}.gif"
tmpdir="/tmp/mp42gif_${timestamp}"

mkdir -p "$tmpdir"

echo "🔧 Extracting frames from $input..."
ffmpeg -hide_banner -loglevel error \
  -i "$input" \
  -vf "fps=15,scale=iw:-1:flags=lanczos" \
  -c:v png -pix_fmt rgba "$tmpdir/frame_%04d.png"

if [[ $? -ne 0 ]]; then
  echo "❌ Frame extraction failed."
  rm -rf "$tmpdir"
  exit 3
fi

echo "🎨 Creating GIF..."
gifski --fps 15 --quality 100 --width 800 -o "$output" "$tmpdir"/frame_*.png

if [[ $? -ne 0 ]]; then
  echo "❌ GIF creation failed."
  rm -rf "$tmpdir"
  exit 4
fi

echo "🧹 Cleaning up..."
rm -rf "$tmpdir"

echo "🗑 Sending original file to system Trash..."
trash "$input" || {
  echo "⚠️ 'trash' command not found. Install it with: brew install trash"
  exit 5
}

echo "✅ Done! Output saved to: $output"
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