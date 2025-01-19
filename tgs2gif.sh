#!/bin/zsh

# Проверка и установка Python-зависимостей
check_and_install_dependencies() {
    echo "Checking Python dependencies..."
    local dependencies=("Pillow" "opencv-python" "lottie" "cairosvg")
    for package in "${dependencies[@]}"; do
        if ! python3 -c "import ${package%%-*}" &> /dev/null; then
            echo "Installing Python package: $package..."
            pip install "$package" || { echo "Failed to install $package. Exiting."; exit 1; }
        else
            echo "$package is already installed."
        fi
    done
}

# Проверка наличия ffmpeg
check_ffmpeg() {
    echo "Checking ffmpeg..."
    if ! command -v ffmpeg &> /dev/null; then
        echo "ffmpeg not found. Installing via Homebrew..."
        brew install ffmpeg || { echo "Failed to install ffmpeg. Exiting."; exit 1; }
    else
        echo "ffmpeg is already installed."
    fi
}

# Генерация имени файла
generate_output_filename() {
    echo "$(date '+%Y%m%d-%H%M%S').gif"
}

# Конвертация файла .tgs в .gif
convert_tgs_to_gif() {
    local input_file="$1"
    local output_file="${2:-$(generate_output_filename)}"

    echo "Converting $input_file to $output_file..."

    # Шаг 1: Конвертация .tgs в .mp4
    lottie_convert.py "$input_file" temp.mp4
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to convert $input_file to temp.mp4"
        exit 1
    fi

    # Шаг 2: Создание палитры для GIF
    ffmpeg -i temp.mp4 -vf "palettegen" -y palette.png

    # Шаг 3: Конвертация .mp4 в .gif
    ffmpeg -i temp.mp4 -i palette.png -lavfi "fps=24,scale=320:-1:flags=lanczos [x]; [x][1:v] paletteuse" "$output_file"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to convert temp.mp4 to $output_file"
        exit 1
    fi

    # Очистка временных файлов
    rm temp.mp4 palette.png
    echo "Conversion completed: $output_file"
}

# Основной процесс
main() {
    check_and_install_dependencies
    check_ffmpeg
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 input.tgs [output.gif]"
        exit 1
    fi
    convert_tgs_to_gif "$@"
}

main "$@"