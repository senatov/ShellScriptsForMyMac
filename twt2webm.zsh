#!/usr/bin/env zsh
# Re-exec under zsh if started by sh due to a broken shebang/BOM
[ -n "$ZSH_VERSION" ] || exec /usr/bin/env zsh "$0" "$@"

# History isolation
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
  echo "  $0 <URL|local.mp4> [--crop] [--start HH:MM:SS] [--duration SECONDS] [--mute]" >&2
  echo "                       [--cookies-from-browser Safari|Chrome|Brave|Firefox]" >&2
}

# === Args ===
if [ -z "$1" ]; then usage; fc -P; exit 1; fi

INPUT_ARG="$1"; shift
CROP_ENABLED="no"
COOKIES_ARG=""
TRIM_START=""
TRIM_DURATION=""
MUTE_AUDIO="no"

while [ $# -gt 0 ]; do
  case "$1" in
    --crop) CROP_ENABLED="yes" ;;
    --start) shift; TRIM_START="$1" ;;
    --duration) shift; TRIM_DURATION="$1" ;;
    --mute) MUTE_AUDIO="yes" ;;
    --cookies-from-browser)
      shift
      [ -n "$1" ] || { echo "❌ Missing browser name after --cookies-from-browser"; fc -P; exit 1; }
      COOKIES_ARG="--cookies-from-browser=$1" ;;
    -h|--help) usage; fc -P; exit 0 ;;
    *) echo "⚠️  Unknown arg: $1" ;;
  esac
  shift
done

# === Tools check ===
for bin in yt-dlp ffmpeg; do
  if ! command -v $bin >/dev/null 2>&1; then
    echo "❌ Missing $bin. Install via Homebrew: brew install $bin"
    fc -P; exit 2
  fi
done

# === Filenames / workspace ===
TS=$(date +"%Y%m%d-%H%M%S")
WORKDIR="${TMPDIR%/}/twt2webm_${TS}"
mkdir -p "$WORKDIR" || { echo "❌ Cannot create workdir"; fc -P; exit 3; }
RAW_MP4="$WORKDIR/raw.mp4"
TRIMMED_MP4="$WORKDIR/trimmed.mp4"
CROPPED_MP4="$WORKDIR/cropped.mp4"
OUT_WEBM="${PWD}/${TS}.webm"

# === Determine input mode (URL vs local file) ===
IS_URL=0
printf '%s' "$INPUT_ARG" | grep -qiE '^(https?|http)://|^x\.com/|^twitter\.com/' && IS_URL=1

INPUT_FOR_ENC=""

if [ $IS_URL -eq 1 ]; then
  echo "📥 Downloading video from Twitter/X..."
  yt-dlp     --no-mtime     --restrict-filenames     --merge-output-format mp4     -S "ext"     -o "$RAW_MP4"     ${COOKIES_ARG:+$COOKIES_ARG}     --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"     "$INPUT_ARG" 2>&1 | tee "$WORKDIR/yt.log"

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
  INPUT_FOR_ENC="$RAW_MP4"
else
  if [ ! -f "$INPUT_ARG" ]; then
    echo "❌ File not found: $INPUT_ARG" >&2
    fc -P; exit 1
  fi
  INPUT_FOR_ENC="$INPUT_ARG"
fi

# === Optional trim ===
if [[ -n "$TRIM_START" || -n "$TRIM_DURATION" ]]; then
  echo "✂️  Trimming input..."
  ffmpeg -hide_banner -loglevel error -y     ${TRIM_START:+-ss "$TRIM_START"} -i "$INPUT_FOR_ENC"     ${TRIM_DURATION:+-t "$TRIM_DURATION"}     -c:v libx264 -preset veryfast -crf 18 -an "$TRIMMED_MP4" && INPUT_FOR_ENC="$TRIMMED_MP4"
fi

# === Optional crop ===
if [[ "$CROP_ENABLED" == "yes" ]]; then
  echo "✂️  Detecting crop..."
  CROP_FILTER=$(ffmpeg -i "$INPUT_FOR_ENC" -vf cropdetect -frames:v 120 -f null - 2>&1 |                  grep -o 'crop=[^ ]*' | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}')
  if [ -n "$CROP_FILTER" ]; then
    echo "🔧 Applying crop: $CROP_FILTER"
    ffmpeg -hide_banner -loglevel error -y -i "$INPUT_FOR_ENC" -vf "$CROP_FILTER" -c:v libx264 -preset fast -crf 20 -an "$CROPPED_MP4" &&       INPUT_FOR_ENC="$CROPPED_MP4"
  else
    echo "ℹ️  cropdetect produced no filter; skipping crop"
  fi
fi

# === Constraints & encode settings ===
MAX_BYTES=20447232     # 19.5 MB
WIDTH=720
MIN_WIDTH=320
FPS=30
MIN_FPS=12
CRF=32                 # start quality for VP9
MAX_CRF=46
AUDIO_K=64             # Opus kbps
MIN_AUDIO_K=24

encode_webm() {
  local in="$1" width="$2" fps="$3" crf="$4" audiok="$5" out="$6"
  rm -f "$out"
  local audio_args=()
  if [[ "$MUTE_AUDIO" == "yes" ]]; then
    audio_args=(-an)
  else
    audio_args=(-c:a libopus -b:a "${audiok}k" -ac 2 -application audio)
  fi

  ffmpeg -hide_banner -loglevel error -y -i "$in"     -vf "scale=${width}:-2:flags=lanczos,fps=${fps}"     -c:v libvpx-vp9 -b:v 0 -crf $crf -row-mt 1 -tile-columns 2 -tile-rows 1 -threads 4 -speed 2     "${audio_args[@]}"     -movflags +faststart     "$out"
}

while : ; do
  AUDIO_TXT=$AUDIO_K
  [[ "$MUTE_AUDIO" == "yes" ]] && AUDIO_TXT=0
  echo "🎬 Encoding WebM (crf=$CRF, width=$WIDTH, fps=$FPS, audio=${AUDIO_TXT}kbps)..."
  encode_webm "$INPUT_FOR_ENC" "$WIDTH" "$FPS" "$CRF" "$AUDIO_K" "$OUT_WEBM"
  if [ ! -s "$OUT_WEBM" ]; then
    echo "❌ WebM was not created" >&2
    fc -P; exit 5
  fi
  BYTES=$(stat -f%z "$OUT_WEBM" 2>/dev/null || wc -c < "$OUT_WEBM")
  echo "📦 WebM size: $((BYTES)) bytes"
  if [ "$BYTES" -le "$MAX_BYTES" ]; then
    break
  fi

  if [ "$CRF" -lt "$MAX_CRF" ]; then
    CRF=$(( CRF + 2 ))
    continue
  fi
  if [ "$WIDTH" -gt "$MIN_WIDTH" ]; then
    WIDTH=$(( WIDTH * 9 / 10 ))
    [ "$WIDTH" -lt "$MIN_WIDTH" ] && WIDTH=$MIN_WIDTH
    CRF=32
    continue
  fi
  if [ "$FPS" -gt "$MIN_FPS" ]; then
    FPS=$(( FPS - 2 ))
    CRF=32
    continue
  fi
  if [[ "$MUTE_AUDIO" != "yes" && "$AUDIO_K" -gt "$MIN_AUDIO_K" ]]; then
    AUDIO_K=$(( AUDIO_K - 8 ))
    [ "$AUDIO_K" -lt "$MIN_AUDIO_K" ] && AUDIO_K=$MIN_AUDIO_K
    CRF=32
    continue
  fi

  echo "⚠️  Cannot compress below limit without severe quality loss; keeping current best"
  break
done

# Cleanup
rm -f "$CROPPED_MP4" "$TRIMMED_MP4" "$RAW_MP4" 2>/dev/null
rmdir "$WORKDIR" 2>/dev/null || true

echo "🎉 Done! -> $OUT_WEBM"

fc -P
