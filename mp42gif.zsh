#!/bin/zsh

setopt NO_HIST_IGNORE_SPACE
setopt HIST_NO_STORE

# === Настройки ===
MAX_SIZE_MB=18
REDUCE_STEP=20
INITIAL_FPS=12
INITIAL_WIDTH=640

# === Проверка аргументов ===
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 input.mp4"
    exit 1
fi

INPUT_FILE="$1"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    exit 1
fi

# === Генерация имени выходного файла ===
TIMESTAMP=$(date "+%Y-%m-%d-%H-%M-%S")
OUTPUT_FILE="${TIMESTAMP}.gif"

TMP_DIR=$(mktemp -d)
PALETTE_FILE="$TMP_DIR/palette.png"
TMP_GIF="$TMP_DIR/tmp.gif"
FPS=$INITIAL_FPS
WIDTH=$INITIAL_WIDTH

# === Проверка размера файла в MB ===
check_size_mb() {
    du -m "$1" | cut -f1
}

# === Основная функция конвертации ===
convert_to_gif() {
    echo "Generating palette (FPS=$FPS, WIDTH=$WIDTH)..."
    ffmpeg -v error -y -i "$INPUT_FILE" \
        -vf "fps=${FPS},scale=${WIDTH}:-1:flags=lanczos,palettegen=stats_mode=full" \
        "$PALETTE_FILE"

    echo "Creating GIF..."
    ffmpeg -v error -y -i "$INPUT_FILE" -i "$PALETTE_FILE" \
        -lavfi "fps=${FPS},scale=${WIDTH}:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5" \
        -loop 0 "$TMP_GIF"
}

# === Основной процесс ===
STEP=1
echo "Step $STEP: Initial GIF creation..."
convert_to_gif
CURRENT_SIZE=$(check_size_mb "$TMP_GIF")
echo "Current GIF size: ${CURRENT_SIZE} MB"

while [ "$CURRENT_SIZE" -gt "$MAX_SIZE_MB" ]; do
    STEP=$((STEP + 1))
    echo "Step $STEP: Reducing FPS and WIDTH by $REDUCE_STEP%..."

    FPS=$(printf "%.0f" "$(echo "$FPS * (100 - $REDUCE_STEP) / 100" | bc -l)")
    WIDTH=$(printf "%.0f" "$(echo "$WIDTH * (100 - $REDUCE_STEP) / 100" | bc -l)")

    if [ "$FPS" -lt 5 ] || [ "$WIDTH" -lt 240 ]; then
        echo "❌ Error: Cannot reduce further without significant quality loss."
        break
    fi

    echo "Trying with FPS=$FPS, WIDTH=$WIDTH..."
    convert_to_gif
    CURRENT_SIZE=$(check_size_mb "$TMP_GIF")
    echo "Current GIF size: ${CURRENT_SIZE} MB"
done

# === Завершаем ===
if [ "$CURRENT_SIZE" -le "$MAX_SIZE_MB" ]; then
    mv "$TMP_GIF" "$OUTPUT_FILE"
    echo "✅ GIF successfully created: $OUTPUT_FILE (Size: ${CURRENT_SIZE} MB)"
else
    echo "❌ Failed to reduce GIF size below ${MAX_SIZE_MB} MB."
fi

rm -rf "$TMP_DIR"