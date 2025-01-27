#!/bin/zsh

# Проверка аргументов
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 input.mp4 output.gif"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"
TMP_DIR=$(mktemp -d)
PALETTE_FILE="$TMP_DIR/palette.png"
TMP_GIF="$TMP_DIR/tmp.gif"
MAX_SIZE_MB=17
REDUCE_STEP=25
FPS=10
WIDTH=480

# Проверка наличия входного файла
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found!"
    exit 1
fi

# Функция для проверки размера файла
check_size_mb() {
    FILE_SIZE=$(du -m "$1" | cut -f1)
    echo $FILE_SIZE
}

# Основная функция конвертации
convert_to_gif() {
    echo "Generating palette..."
    ffmpeg -y -i "$INPUT_FILE" -vf "fps=$FPS,scale=$WIDTH:-1:flags=lanczos,palettegen" "$PALETTE_FILE" > /dev/null 2>&1

    echo "Creating GIF..."
    ffmpeg -y -i "$INPUT_FILE" -i "$PALETTE_FILE" -lavfi "fps=$FPS,scale=$WIDTH:-1:flags=lanczos [x]; [x][1:v] paletteuse" -loop 0 "$TMP_GIF" > /dev/null 2>&1
}

# Основной процесс
echo "Step 1: Initial GIF creation with FPS=$FPS, WIDTH=$WIDTH..."
convert_to_gif
CURRENT_SIZE=$(check_size_mb "$TMP_GIF")
echo "Current GIF size: ${CURRENT_SIZE} MB"

# Постепенное уменьшение размера, если файл больше MAX_SIZE_MB
STEP=1
while [ "$CURRENT_SIZE" -gt "$MAX_SIZE_MB" ]; do
    echo "Step $((STEP + 1)): Reducing size by $REDUCE_STEP%..."
    FPS=$(echo "$FPS * (100 - $REDUCE_STEP) / 100" | bc)
    WIDTH=$(echo "$WIDTH * (100 - $REDUCE_STEP) / 100" | bc)
    FPS=${FPS%.*}
    WIDTH=${WIDTH%.*}

    if [ "$FPS" -lt 5 ] || [ "$WIDTH" -lt 240 ]; then
        echo "Error: Cannot reduce further without significant quality loss."
        break
    fi

    echo "New parameters: FPS=$FPS, WIDTH=$WIDTH"
    convert_to_gif
    CURRENT_SIZE=$(check_size_mb "$TMP_GIF")
    echo "Current GIF size: ${CURRENT_SIZE} MB"
    STEP=$((STEP + 1))
done

# Перенос конечного GIF
if [ "$CURRENT_SIZE" -le "$MAX_SIZE_MB" ]; then
    mv "$TMP_GIF" "$OUTPUT_FILE"
    echo "GIF successfully created: $OUTPUT_FILE (Size: ${CURRENT_SIZE} MB)"
else
    echo "Failed to reduce GIF size below ${MAX_SIZE_MB} MB."
fi

# Удаляем временные файлы
rm -rf "$TMP_DIR"