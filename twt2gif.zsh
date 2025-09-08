#!/usr/bin/env -S zsh -f
# -*- coding: utf-8 -*-
# twt2gif.zsh — download Twitter/X video (or use local .mp4) and convert to size-capped GIF.
# All comments are in English. This script runs under zsh (shebang enforces zsh -f).
# Changelog: adds --start/--duration trim, mpdecimate, adaptive palette, optional gifsicle pass,
# and more robust size fitting to 19.5 MB.

# --- zsh history isolation: do not persist commands from this script ---
unsetopt APPEND_HISTORY
unsetopt INC_APPEND_HISTORY
unsetopt SHARE_HISTORY
setopt HIST_IGNORE_SPACE
HISTFILE=/dev/null
HISTSIZE=0
SAVEHIST=0
fc -p /dev/null

usage() {
  echo "Usage:" >&2
  echo "  $0 <URL|local.mp4> [--crop] [--start HH:MM:SS] [--duration SS] [--cookies-from-browser Safari|Chrome|Brave|Firefox]" >&2
  echo "Options:" >&2
  echo "  --crop                 Auto-crop black borders using cropdetect" >&2
  echo "  --start HH:MM:SS       Trim start time" >&2
  echo "  --duration SS          Trim duration in seconds" >&2
  echo "  --cookies-from-browser Use cookies for protected tweets" >&2
  echo "  --no-gifsicle          Disable final gifsicle optimization pass" >&2
}

# === Args ===
if [ -z "$1" ]; then usage; fc -P; exit 1; fi

INPUT_ARG="$1"; shift
CROP_ENABLED="no"
COOKIES_ARG=""
TRIM_START=""
TRIM_DURATION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --crop) CROP_ENABLED="yes" ;;
    --start) shift; TRIM_START="$1" ;;
    --duration) shift; TRIM_DURATION="$1" ;;
    --cookies-from-browser)
      shift
      [ -n "$1" ] || { echo "❌ Missing browser name after --cookies-from-browser"; fc -P; exit 1; }
      COOKIES_ARG="--cookies-from-browser=$1" ;;
    --no-gifsicle) export DISABLE_GIFSICLE=1 ;;
    -h|--help) usage; fc -P; exit 0 ;;
    *) echo "⚠️  Unknown arg: $1" ;;
  esac
  shift
done

# === Sanity: enforce single input (one URL or one local file) ===
if [ $# -gt 0 ]; then
  for extra in "$@"; do
    if printf '%s' "$extra" | grep -qiE '^(https?|http)://|^x\.com/|^twitter\.com/'; then
      echo "❌ Please pass exactly ONE input (URL or local .mp4)." >&2
      fc -P; exit 1
    fi
  done
fi

# === Tools ===
for bin in yt-dlp ffmpeg; do
  if ! command -v $bin >/dev/null 2>&1; then
    echo "❌ Missing $bin. Install via Homebrew: brew install $bin"
    fc -P; exit 2
  fi
done
if command -v gifsicle >/dev/null 2>&1; then HAVE_GIFSICLE=1; else HAVE_GIFSICLE=0; fi
if [ -n "$DISABLE_GIFSICLE" ]; then HAVE_GIFSICLE=0; fi

# === Filenames / workspace ===
TS=$(date +"%Y%m%d-%H%M%S")
WORKDIR="${TMPDIR%/}/twt2gif_${TS}"
mkdir -p "$WORKDIR" || { echo "❌ Cannot create workdir"; fc -P; exit 3; }
RAW_MP4="$WORKDIR/raw.mp4"
TRIMMED_MP4="$WORKDIR/trimmed.mp4"
CROPPED_MP4="$WORKDIR/cropped.mp4"
PALETTE="$WORKDIR/palette.png"
OUT_GIF="${PWD}/${TS}.gif"

# === Determine input mode (URL vs local file) ===
IS_URL=0
printf '%s' "$INPUT_ARG" | grep -qiE '^(https?|http)://|^x\\.com/|^twitter\\.com/' && IS_URL=1

INPUT_FOR_GIF=""

if [ $IS_URL -eq 1 ]; then
  echo "📥 Downloading video from Twitter/X..."
  yt-dlp \
    --no-mtime \
    --restrict-filenames \
    --merge-output-format mp4 \
    -S "ext" \
    -o "$RAW_MP4" \
    ${COOKIES_ARG:+$COOKIES_ARG} \
    --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
    "$INPUT_ARG" 2>&1 | tee "$WORKDIR/yt.log"

  if [ ! -s "$RAW_MP4" ]; then
    if grep -q "You are not authorized to view this protected tweet" "$WORKDIR/yt.log" 2>/dev/null; then
      echo "🔐 Protected tweet. Try adding: --cookies-from-browser Safari (or Chrome/Brave/Firefox)" >&2
    fi
    echo "⚠️  Primary download didn't produce MP4. Trying explicit format selection..."
    FMT=$(yt-dlp -F "$INPUT_ARG" ${COOKIES_ARG:+$COOKIES_ARG} 2>/dev/null | awk '/mp4/ {print $1}' | tail -n1)
    if [ -n "$FMT" ]; then
      yt-dlp -f "$FMT" -o "$RAW_MP4" ${COOKIES_ARG:+$COOKIES_ARG} "$INPUT_ARG" || true
    fi
  fi

  if [ ! -s "$RAW_MP4" ]; then
    echo "❌ Could not download a playable MP4. See $WORKDIR/yt.log" >&2
    fc -P; exit 4
  fi
  echo "✅ Downloaded: $RAW_MP4"
  INPUT_FOR_GIF="$RAW_MP4"
else
  # Local file mode
  if [ ! -f "$INPUT_ARG" ]; then
    echo "❌ File not found: $INPUT_ARG" >&2
    fc -P; exit 1
  fi
  INPUT_FOR_GIF="$INPUT_ARG"
fi

# === Duration-aware initial width to avoid massive first GIF ===
DUR_S=0
if command -v ffprobe >/dev/null 2>&1; then
  DUR_S=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 "$INPUT_FOR_GIF" 2>/dev/null | awk 'NR==1 {printf("%d", ($1>0)?$1:0)}')
fi
# If duration is long, start with smaller width to avoid huge intermediate GIFs
if [ "$DUR_S" -gt 0 ]; then
  if   [ "$DUR_S" -gt 12 ]; then WIDTH=320
  elif [ "$DUR_S" -gt 8 ];  then WIDTH=360
  elif [ "$DUR_S" -gt 5 ];  then WIDTH=420
  fi
fi

# === Optional trim ===
if [[ -n "$TRIM_START" || -n "$TRIM_DURATION" ]]; then
  echo "✂️  Trimming input..."
  ffmpeg -hide_banner -loglevel error -y \
    ${TRIM_START:+-ss "$TRIM_START"} -i "$INPUT_FOR_GIF" \
    ${TRIM_DURATION:+-t "$TRIM_DURATION"} \
    -c:v libx264 -preset veryfast -crf 18 -an "$TRIMMED_MP4" && INPUT_FOR_GIF="$TRIMMED_MP4"
fi

# === Optional crop ===
if [[ "$CROP_ENABLED" == "yes" ]]; then
  echo "✂️  Detecting crop..."
  CROP_FILTER=$(ffmpeg -i "$INPUT_FOR_GIF" -vf cropdetect -frames:v 120 -f null - 2>&1 | \
                 grep -o 'crop=[^ ]*' | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}')
  if [ -n "$CROP_FILTER" ]; then
    echo "🔧 Applying crop: $CROP_FILTER"
    ffmpeg -hide_banner -loglevel error -y -i "$INPUT_FOR_GIF" -vf "$CROP_FILTER" -c:v libx264 -preset fast -crf 23 -an "$CROPPED_MP4" && \
      INPUT_FOR_GIF="$CROPPED_MP4"
  else
    echo "ℹ️  cropdetect produced no filter; skipping crop"
  fi
fi

# === GIF constraints ===
MAX_BYTES=20447232   # 19.5 MB
FPS=18
MIN_FPS=8
WIDTH=${WIDTH:-720}
MIN_WIDTH=240
# Adaptive palette bounds
MAX_COLORS=128
MIN_COLORS=32
GIFSICLE_MAX_BYTES=$((40 * 1024 * 1024))   # only run gifsicle if current GIF <= 40MB
AGGRESSIVE_BYTES=$((100 * 1024 * 1024))    # if over 100MB, downscale aggressively

make_gif() {
  # Build GIF with mpdecimate (drop near-duplicate frames), adaptive palette, controlled dithering
  local in="$1" width="$2" fps="$3" out="$4" pal="$5" colors="$6"
  rm -f "$pal" "$out"
  # First pass: generate a single-frame PNG palette (no split/map; force one frame)
  ffmpeg -hide_banner -loglevel error -y -i "$in" \
    -vf "fps=${fps},mpdecimate=hi=64*8:lo=64*5:frac=0.33,scale=${width}:-1:flags=lanczos,palettegen=stats_mode=single:max_colors=${colors}" \
    -frames:v 1 "$pal" && \
  # Second pass: apply palette
  ffmpeg -hide_banner -loglevel error -y -i "$in" -i "$pal" -lavfi \
    "fps=${fps},mpdecimate=hi=64*8:lo=64*5:frac=0.33,scale=${width}:-1:flags=lanczos [x]; \
     [x][1:v] paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    -gifflags -offsetting "$out"
}

while : ; do
  echo "🎨 Generating GIF (fps=$FPS, width=$WIDTH, colors=$MAX_COLORS)..."
  make_gif "$INPUT_FOR_GIF" "$WIDTH" "$FPS" "$OUT_GIF" "$PALETTE" "$MAX_COLORS"
  if [ ! -s "$OUT_GIF" ]; then
    echo "❌ GIF was not created" >&2
    fc -P; exit 5
  fi
  BYTES=$(stat -f%z "$OUT_GIF" 2>/dev/null || wc -c < "$OUT_GIF")
  echo "📦 GIF size: $((BYTES)) bytes"

  # Optional gifsicle pass (only for moderately oversized GIFs to avoid hangs on huge files)
  if [ "$BYTES" -gt "$MAX_BYTES" ] && [ "$BYTES" -le "$GIFSICLE_MAX_BYTES" ] && [ $HAVE_GIFSICLE -eq 1 ]; then
    echo "🪄 gifsicle pass..."
    gifsicle -O3 --lossy=60 -o "$OUT_GIF.tmp" "$OUT_GIF" && mv "$OUT_GIF.tmp" "$OUT_GIF"
    BYTES=$(stat -f%z "$OUT_GIF" 2>/dev/null || wc -c < "$OUT_GIF")
    echo "📦 After gifsicle: $((BYTES)) bytes"
  fi

  # If current GIF is extremely large, downscale aggressively before next attempts
  if [ "$BYTES" -gt "$AGGRESSIVE_BYTES" ] && [ "$WIDTH" -gt 360 ]; then
    WIDTH=$(( WIDTH * 7 / 10 ))
    [ "$WIDTH" -lt 360 ] && WIDTH=360
    echo "↘️  Oversized GIF detected (${BYTES} bytes). Aggressively reducing width to $WIDTH and retrying..."
    continue
  fi

  if [ "$BYTES" -le "$MAX_BYTES" ]; then break; fi

  if [ "$WIDTH" -gt "$MIN_WIDTH" ]; then
    WIDTH=$(( WIDTH * 9 / 10 ))
    [ "$WIDTH" -lt "$MIN_WIDTH" ] && WIDTH=$MIN_WIDTH
  elif [ "$FPS" -gt "$MIN_FPS" ]; then
    FPS=$(( FPS - 2 ))
  elif [ "$MAX_COLORS" -gt "$MIN_COLORS" ]; then
    MAX_COLORS=$(( MAX_COLORS - 16 ))
  else
    echo "⚠️  Cannot compress below limit without severe quality loss; keeping current best"
    break
  fi

done

# === Cleanup workspace ===
rm -f "$PALETTE" "$CROPPED_MP4" "$TRIMMED_MP4" "$RAW_MP4" 2>/dev/null
rmdir "$WORKDIR" 2>/dev/null || true

echo "🎉 Done! -> $OUT_GIF"

# --- restore zsh history context ---
fc -P