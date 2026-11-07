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
  echo "   [--cookies-from-browser Safari|Chrome|Brave|Firefox]" >&2
}

# === Args ===
INPUT_ARG=""
CROP_ENABLED="no"
COOKIES_ARGS=()
TRIM_START=""
TRIM_DURATION=""
MUTE_AUDIO="no"
while (( $# )); do
  case "$1" in
    --crop) CROP_ENABLED="yes"; shift ;;
    --mute) MUTE_AUDIO="yes"; shift ;;
    --start|--duration|--cookies-from-browser)
      [ $# -ge 2 ] || { echo "❌ Missing value after $1" >&2; fc -P; exit 64; }
      option="$1"; value="$2"; shift 2
      case "$option" in
        --start) TRIM_START="$value" ;;
        --duration) TRIM_DURATION="$value" ;;
        --cookies-from-browser) COOKIES_ARGS=(--cookies-from-browser "$value") ;;
      esac ;;
    -h|--help) usage; fc -P; exit 0 ;;
    -*) echo "❌ Unknown option: $1" >&2; fc -P; exit 64 ;;
    *) [ -z "$INPUT_ARG" ] || { echo "❌ Please pass exactly ONE input." >&2; fc -P; exit 64; }; INPUT_ARG="$1"; shift ;;
  esac
done
[ -n "$INPUT_ARG" ] || { usage; fc -P; exit 64; }

# === Tools check ===
for bin in ffmpeg; do
  if ! command -v $bin >/dev/null 2>&1; then
    echo "❌ Missing $bin. Install via Homebrew: brew install $bin"
    fc -P; exit 2
  fi
done

# === Filenames / workspace ===
TS=$(date +"%Y%m%d-%H%M%S")
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/twt2webm.XXXXXX") || { echo "❌ Cannot create workdir"; fc -P; exit 3; }
RAW_MP4="$WORKDIR/raw.mp4"
TRIMMED_MP4="$WORKDIR/trimmed.mkv"
CROPPED_MP4="$WORKDIR/cropped.mp4"
OUT_WEBM="${PWD}/${TS}.webm"
[ ! -e "$OUT_WEBM" ] || { echo "❌ Output already exists: $OUT_WEBM" >&2; rm -rf "$WORKDIR"; fc -P; exit 73; }
cleanup() { [ -d "$WORKDIR" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM HUP

# === Determine input mode (URL vs local file) ===
IS_URL=0
printf '%s' "$INPUT_ARG" | grep -qiE '^(https?|http)://|^x\.com/|^twitter\.com/' && IS_URL=1

INPUT_FOR_ENC=""

if [ $IS_URL -eq 1 ]; then
  command -v yt-dlp >/dev/null || { echo "❌ yt-dlp is required for URL downloads." >&2; exit 69; }
  echo "📥 Downloading video from Twitter/X..."
  yt-dlp     --no-mtime     --restrict-filenames     --merge-output-format mp4     -S "ext"     -o "$RAW_MP4"     "${COOKIES_ARGS[@]}"     --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"     "$INPUT_ARG" 2>&1 | tee "$WORKDIR/yt.log"

  if [ ! -s "$RAW_MP4" ]; then
    if grep -q "You are not authorized to view this protected tweet" "$WORKDIR/yt.log" 2>/dev/null; then
  echo "🔐 Protected tweet. Try adding: --cookies-from-browser Safari (or Chrome/Brave/Firefox)" >&2
    fi
    echo "⚠️  Primary download didn't produce MP4. Trying explicit format selection..."
    FMT=$(yt-dlp -F "$INPUT_ARG" "${COOKIES_ARGS[@]}" 2>/dev/null | awk '/mp4/ {print $1}' | tail -n1)
    if [ -n "$FMT" ]; then
  yt-dlp -f "$FMT" -o "$RAW_MP4" "${COOKIES_ARGS[@]}" "$INPUT_ARG" || true
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
  TRIM_ARGS=()
  [ -z "$TRIM_START" ] || TRIM_ARGS+=(-ss "$TRIM_START")
  TRIM_ARGS+=(-i "$INPUT_FOR_ENC")
  [ -z "$TRIM_DURATION" ] || TRIM_ARGS+=(-t "$TRIM_DURATION")
  if [[ "$MUTE_AUDIO" == "yes" ]]; then
    ffmpeg -hide_banner -loglevel error -nostdin -y "${TRIM_ARGS[@]}" -c:v libx264 -preset veryfast -crf 18 -an "$TRIMMED_MP4"
  else
    ffmpeg -hide_banner -loglevel error -nostdin -y "${TRIM_ARGS[@]}" -c:v libx264 -preset veryfast -crf 18 -c:a aac -b:a 128k "$TRIMMED_MP4"
  fi
  INPUT_FOR_ENC="$TRIMMED_MP4"
fi

# === Optional crop ===
if [[ "$CROP_ENABLED" == "yes" ]]; then
  echo "✂️  Detecting crop..."
  CROP_FILTER=$(ffmpeg -i "$INPUT_FOR_ENC" -vf cropdetect -frames:v 120 -f null - 2>&1 |  grep -o 'crop=[^ ]*' | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}')
  if [ -n "$CROP_FILTER" ]; then
    echo "🔧 Applying crop: $CROP_FILTER"
    ffmpeg -hide_banner -loglevel error -y -i "$INPUT_FOR_ENC" -vf "$CROP_FILTER" -c:v libx264 -preset fast -crf 20 -an "$CROPPED_MP4" &&   INPUT_FOR_ENC="$CROPPED_MP4"
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
CRF=32     # start quality for VP9
MAX_CRF=46
AUDIO_K=64     # Opus kbps
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
