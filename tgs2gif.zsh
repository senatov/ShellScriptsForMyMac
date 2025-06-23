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
  echo "❌ Input must be a .tgs (Telegram Lottie animation)"
  exit 3
fi

# Unique output
timestamp=$(date "+%Y%m%d_%H%M%S")
output="./${timestamp}.gif"
tmpdir="/tmp/tgs2gif_${timestamp}"
mkdir -p "$tmpdir"

echo "🔧 Decompressing $input..."
json_file="$tmpdir/animation.json"
gzip -dc "$input" > "$json_file" || {
  echo "❌ Failed to decompress $input"
  exit 4
}

echo "🔧 Converting Lottie JSON to frames..."
lottie_render_bin=$(which lottie-render || which lottie_convert.py)

if [[ -z "$lottie_render_bin" ]]; then
  echo "❌ No Lottie renderer found (need 'lottie-render' or 'lottie_convert.py')"
  exit 5
fi

$lottie_render_bin "$json_file" "$tmpdir/frame.png" --width 512 --height 512 || {
  echo "❌ Failed to render frames from $json_file"
  exit 6
}

frame_count=$(ls "$tmpdir"/frame*.png 2>/dev/null | wc -l)
if [[ $frame_count -lt 2 ]]; then
  echo "❌ Not enough frames rendered to create an animation ($frame_count frame)"
  exit 7
fi

echo "🎨 Creating GIF from $frame_count frames..."
gifski --fps 30 --quality 100 --output "$output" "$tmpdir"/frame*.png || {
  echo "❌ GIF creation failed"
  exit 8
}

echo "✅ Done: $output"