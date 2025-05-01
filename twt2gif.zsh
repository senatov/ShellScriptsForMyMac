#!/bin/zsh

setopt NO_HIST_IGNORE_SPACE
setopt HIST_NO_STORE

# === Dependencies Check ===
for cmd in yt-dlp ffmpeg gifsicle; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# === Arguments Check ===
if [ -z "$1" ]; then
    echo "Usage: $0 <URL> [optional text for GIF]"
    exit 1
fi

URL="$1"
TEXT="${2:-''}"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TEMP_DIR=$(mktemp -d)
FINAL_GIF="./${TIMESTAMP}_final.gif"

# === GIF Settings ===
FPS=10
MAX_WIDTH=480
MAX_SIZE_BYTES=$((19500000))  # 19.5 MB
FONT_PATH="/Library/Fonts/Arial.ttf"
[[ ! -f "$FONT_PATH" ]] && FONT_PATH="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

VIDEO_FILE="$TEMP_DIR/video.mp4"
PALETTE="$TEMP_DIR/palette.png"
GIF_RAW="$TEMP_DIR/raw.gif"

echo "🔽 Downloading video from: $URL"
yt-dlp -f 'mp4[height<=720]+bestaudio/best[height<=720]' -o "$VIDEO_FILE" "$URL" || exit 1

# === Get Full Video Duration ===
DURATION=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" | cut -d. -f1)

if [[ -z "$DURATION" || "$DURATION" -lt 1 ]]; then
    echo "❌ Error: Could not determine video duration."
    rm -rf "$TEMP_DIR"
    exit 1
fi

CURRENT_DURATION=$DURATION

# === Loop: Reduce duration if needed ===
while (( CURRENT_DURATION >= 1 )); do
    echo "⏱️  Trying duration: $CURRENT_DURATION seconds..."

    # Detect crop (remove borders)
    echo "🧽 Detecting crop area (removing borders)..."
    CROP=$(ffmpeg -hide_banner -loglevel error -t 5 -i "$VIDEO_FILE" \
        -vf "cropdetect=24:16:0" -f null - 2>&1 | \
        grep -o "crop=.*" | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}')
    [[ -z "$CROP" ]] && CROP="crop=in_w:in_h:0:0"
    echo "📐 Using crop filter: $CROP"

    # Generate palette
    echo "🎨 Generating color palette..."
    ffmpeg -hide_banner -loglevel error -y \
        -ss 0 -t "$CURRENT_DURATION" -i "$VIDEO_FILE" \
        -vf "fps=$FPS,$CROP,scale=${MAX_WIDTH}:-1:flags=lanczos,palettegen" \
        "$PALETTE" || break

    # Generate GIF with palette
    echo "🌀 Creating GIF..."
    ffmpeg -hide_banner -loglevel error -y \
        -ss 0 -t "$CURRENT_DURATION" -i "$VIDEO_FILE" -i "$PALETTE" \
        -filter_complex "fps=$FPS,$CROP,scale=${MAX_WIDTH}:-1:flags=lanczos[x];[x][1:v]paletteuse" \
        "$GIF_RAW" || break

    # Optimize GIF
    gifsicle -O3 "$GIF_RAW" -o "$FINAL_GIF"

    # Check file size
    FILE_SIZE=$(stat -f%z "$FINAL_GIF" 2>/dev/null || stat --format="%s" "$FINAL_GIF")
    FILE_MB=$(echo "scale=2; $FILE_SIZE/1048576" | bc)
    echo "📦 GIF size: ${FILE_MB} MB"

    if (( FILE_SIZE <= MAX_SIZE_BYTES )); then
        echo "✅ Success! GIF created: $FINAL_GIF"
        rm -rf "$TEMP_DIR"
        exit 0
    fi

    echo "⚠️ GIF is too large. Reducing duration and retrying..."
    CURRENT_DURATION=$(( CURRENT_DURATION / 2 ))
done

echo "❌ Failed to generate a GIF under 19.5 MB."
rm -rf "$TEMP_DIR"
exit 1