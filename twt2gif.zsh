#!/bin/zsh

setopt NO_HIST_IGNORE_SPACE
setopt HIST_NO_STORE

# === Проверка зависимостей ===
for cmd in yt-dlp ffmpeg magick gifsicle; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Error: $cmd is not installed."
        exit 1
    fi
done

# === Входные параметры ===
if [ -z "$1" ]; then
    echo "Usage: $0 <URL>"
    exit 1
fi

URL="$1"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TEMP_DIR=$(mktemp -d)
VIDEO_ORIG="$TEMP_DIR/video.mp4"
VIDEO_TRIM="$TEMP_DIR/video_trim.mp4"
FRAME_DIR="$TEMP_DIR/frames"
mkdir -p "$FRAME_DIR"
RAW_GIF="$TEMP_DIR/output.gif"
FINAL_GIF="${HOME}/Downloads/Hahly/${TIMESTAMP}_final.gif"

# === Настройки GIF ===
FPS=10
WIDTH=480
MAX_BYTES=20480000  # 19.5 MB
ESTIMATED_KBPS=700
LOW=1
HIGH=$((MAX_BYTES / (ESTIMATED_KBPS * 1024)))
BEST_DURATION=0
GIF_SIZE_BYTES=0

echo "📥 Downloading video..."
yt-dlp -f 'mp4[height<=720]+bestaudio/best[height<=720]' -o "$VIDEO_ORIG" "$URL" || exit 1

generate_gif() {
    local duration="$1"

    rm -f "$VIDEO_TRIM" "$RAW_GIF" "$FINAL_GIF"
    rm -rf "$FRAME_DIR"/*

    echo "⚡ Cutting video with GPU: $duration sec"
    ffmpeg -hwaccel videotoolbox -ss 0 -t "$duration" -i "$VIDEO_ORIG" -c:v copy -an "$VIDEO_TRIM" -y

    echo "🎞️ Extracting frames..."
    ffmpeg -hwaccel videotoolbox -i "$VIDEO_TRIM" -vf "fps=${FPS},scale=${WIDTH}:-1" "$FRAME_DIR/frame_%04d.png" -y

    if ls "$FRAME_DIR"/*.png >/dev/null 2>&1; then
        echo "🧩 Assembling GIF with magick..."
        magick -delay 10 -loop 0 "$FRAME_DIR"/frame_*.png "$RAW_GIF"
    else
        echo "❌ No frames created"
        return 1
    fi

    if [[ ! -s "$RAW_GIF" ]]; then
        echo "❌ magick failed"
        return 1
    fi

    echo "🧼 Optimizing..."
    gifsicle -O3 "$RAW_GIF" -o "$FINAL_GIF"

    GIF_SIZE_BYTES=$(stat -f%z "$FINAL_GIF")
    echo "📦 Result size: ${GIF_SIZE_BYTES} bytes"
    return 0
}

# === Бинарный поиск ===
while (( LOW <= HIGH )); do
    MID=$(((LOW + HIGH) / 2))
    echo "🔎 Trying duration: ${MID}s..."
    generate_gif "$MID"
    if [[ $? -ne 0 ]]; then
        echo "⚠️ Generation failed. Trying shorter..."
        HIGH=$((MID - 1))
        continue
    fi

    if (( GIF_SIZE_BYTES > MAX_BYTES )); then
        HIGH=$((MID - 1))
        echo "🔻 Too big. Trying shorter..."
    else
        BEST_DURATION=$MID
        LOW=$((MID + 1))
        echo "✅ Fits! Trying longer..."
    fi
done

if (( BEST_DURATION > 0 )); then
    echo "🏁 Generating final GIF with $BEST_DURATION sec..."
    generate_gif "$BEST_DURATION" > /dev/null
    echo "✅ Saved to: $FINAL_GIF"
else
    echo "❌ Could not find acceptable duration."
    rm -rf "$TEMP_DIR"
    exit 1
fi

rm -rf "$TEMP_DIR"
