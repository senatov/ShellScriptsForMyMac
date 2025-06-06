#!/bin/zsh

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 input.webp"
  exit 1
fi

input="$1"
if [[ ! -f "$input" ]]; then
  echo "❌ File not found: $input"
  exit 2
fi

timestamp=$(date "+%Y%m%d_%H%M%S")
output="./${timestamp}.gif"

echo "🎨 Converting $input → $output with ImageMagick..."
magick "$input" -coalesce -background none -alpha on "$output"

echo "🗑 Moving original file to Trash..."
trash "$input" || mv "$input" ~/.Trash/

echo "✅ Done! Output saved to: $output"