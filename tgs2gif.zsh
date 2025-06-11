#!/bin/zsh

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 input.tgs"
  exit 1
fi

input="$1"
if [[ ! -f "$input" ]]; then
  echo "❌ File not found: $input"
  exit 2
fi

if [[ "${input:e}" != "tgs" ]]; then
  echo "❌ Input must be a .tgs (Lottie) file"
  exit 3
fi

# Уникальное имя
timestamp=$(date "+%Y%m%d_%H%M%S")
output="./${timestamp}.gif"
tmpdir="/tmp/tgs2gif_${timestamp}"
mkdir -p "$tmpdir"

echo "🔧 Converting $input to frames..."
# Используем lottie-web или rlottie (предполагается установка lottie-render)
lottie_render_bin=$(which lottie-render || which lottie_convert.py)

if [[ -z "$lottie_render_bin" ]]; then
  echo "❌ No Lottie renderer found (need 'lottie-render' or 'lottie_convert.py')"
  echo "ℹ️  You can install lottie-render with: brew install lottie"
  exit 4
fi

# Генерация PNG кадров
$lottie_render_bin "$input" "$tmpdir/frame.png" --width 512 --height 512 || {
  echo "❌ Failed to render frames from $input"
  exit 5
}

echo "🎨 Creating GIF..."
gifski --fps 30 --quality 100 --width 512 -o "$output" "$tmpdir"/frame*.png

if [[ $? -ne 0 ]]; then
  echo "❌ GIF creation failed."
  rm -rf "$tmpdir"
  exit 6
fi

echo "🧹 Cleaning up..."
rm -rf "$tmpdir"

echo "🗑 Sending original .tgs to system Trash..."
trash "$input" || {
  echo "⚠️ 'trash' command not found. Install it with: brew install trash"
  exit 7
}

echo "✅ Done! Output saved to: $output"