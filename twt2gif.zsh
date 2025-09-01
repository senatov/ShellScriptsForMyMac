#!/bin/zsh

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
  echo "  $0 <URL> [--crop] [--cookies-from-browser Safari|Chrome|Brave|Firefox]" >&2
  echo "  $0 <local.mp4> [--crop]    # skip download, convert existing MP4 to GIF" >&2
}

# === Args ===
if [ -z "$1" ]; then usage; fc -P; exit 1; fi

INPUT_ARG="$1"; shift
CROP_ENABLED="no"
COOKIES_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --crop) CROP_ENABLED="yes" ;;
    --cookies-from-browser)
      shift
      [ -n "$1" ] || { echo "❌ Missing browser name after --cookies-from-browser"; fc -P; exit 1; }
      COOKIES_ARG="--cookies-from-browser=$1" ;;
    -h|--help) usage; fc -P; exit 0 ;;
    *) echo "⚠️ Unknown arg: $1" ;;
  esac
  shift
done

# === Tools ===
for bin in yt-dlp ffmpeg; do
  if ! command -v $bin >/dev/null 2>&1; then
    echo "❌ Missing $bin. Install via Homebrew: brew install $bin"
    fc -P; exit 2
  fi
done

# === Filenames / workspace ===
TS=$(date +"%Y%m%d-%H%M%S")
WORKDIR="${TMPDIR%/}/twt2gif_${TS}"
mkdir -p "$WORKDIR" || { echo "❌ Cannot create workdir"; fc -P; exit 3; }
RAW_MP4="$WORKDIR/raw.mp4"
CROPPED_MP4="$WORKDIR/cropped.mp4"
PALETTE="$WORKDIR/palette.png"
OUT_GIF="${PWD}/${TS}.gif"

# === Determine input mode (URL vs local file) ===
IS_URL=0
print -r -- "$INPUT_ARG" | grep -qiE '^(https?|http)://|^x\\.com/|^twitter\\.com/' && IS_URL=1

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
    echo "⚠️ Primary download didn't produce MP4. Trying explicit format selection..."
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
  # Local MP4 path
  if [ ! -f "$INPUT_ARG" ]; then
    echo "❌ File not found: $INPUT_ARG" >&2
    fc -P; exit 1
  fi
  case "$INPUT_ARG" in
    *.mp4|*.MP4) : ;;
    *) echo "ℹ️ Input is not .mp4; attempting anyway" ;;
  esac
  INPUT_FOR_GIF="$INPUT_ARG"
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
WIDTH=720
MIN_WIDTH=240

make_gif() {
  local in="$1" width="$2" fps="$3" out="$4" pal="$5"
  rm -f "$pal" "$out"
  ffmpeg -hide_banner -loglevel error -y -i "$in" \
         -vf "fps=$fps,scale=$width:-1:flags=lanczos,palettegen=stats_mode=diff" "$pal" && \
  ffmpeg -hide_banner -loglevel error -y -i "$in" -i "$pal" \
         -lavfi "fps=$fps,scale=$width:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
         -gifflags -offsetting "$out"
}

while : ; do
  echo "🎨 Generating GIF (fps=$FPS, width=$WIDTH)..."
  make_gif "$INPUT_FOR_GIF" "$WIDTH" "$FPS" "$OUT_GIF" "$PALETTE"
  if [ ! -s "$OUT_GIF" ]; then
    echo "❌ GIF was not created" >&2
    fc -P; exit 5
  fi
  BYTES=$(stat -f%z "$OUT_GIF" 2>/dev/null || wc -c < "$OUT_GIF")
  echo "📦 GIF size: $((BYTES)) bytes"
  if [ "$BYTES" -le "$MAX_BYTES" ]; then
    break
  fi
  if [ "$WIDTH" -gt "$MIN_WIDTH" ]; then
    WIDTH=$(( WIDTH * 9 / 10 ))
    [ "$WIDTH" -lt "$MIN_WIDTH" ] && WIDTH=$MIN_WIDTH
  elif [ "$FPS" -gt 10 ]; then
    FPS=$(( FPS - 2 ))
  else
    echo "⚠️ Cannot compress below limit without ruining quality; keeping current best"
    break
  fi
done

# === Cleanup workspace ===
rm -f "$PALETTE" "$CROPPED_MP4" "$RAW_MP4" 2>/dev/null
rmdir "$WORKDIR" 2>/dev/null || true

echo "🎉 Done! -> $OUT_GIF"

# --- restore zsh history context ---
fc -P