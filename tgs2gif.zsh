#!/bin/zsh

# Проверка и установка Python-зависимостей
check_and_install_dependencies() {
    echo "🔍 Checking Python dependencies..."
    local dependencies=("Pillow" "opencv-python" "lottie" "cairosvg")
    for package in "${dependencies[@]}"; do
        if ! python3 -c "import ${package%%-*}" &>/dev/null; then
            echo "📦 Installing Python package: $package..."
            pip install --upgrade "$package" || { echo "❌ Failed to install $package. Exiting."; exit 1; }
        else
            echo "✅ $package is already installed."
        fi
    done
}

# Проверка наличия ffmpeg
check_ffmpeg() {
    echo "🔍 Checking ffmpeg..."
    if ! command -v ffmpeg &>/dev/null; then
        echo "📦 ffmpeg not found. Installing via Homebrew..."
        brew install ffmpeg || { echo "❌ Failed to install ffmpeg. Exiting."; exit 1; }
    else
        echo "✅ ffmpeg is already installed."
    fi
}

# Генерация уникального имени файла gif
generate_output_filename() {
    echo "$(date '+%Y-%m-%d-%H-%M-%S').gif"
}

# Конвертация .tgs в оптимизированный .gif (до 18 МБ)
convert_tgs_to_gif() {
    local input_file="$1"
    local output_file="$(generate_output_filename)"

    echo "🔄 Converting $input_file → $output_file"

    # ✅ Шаг 1: TGS → MP4 (исправленный вызов!)
    lottie_convert.py "$input_file" temp.mp4 --width 512 --height 512 || {
        echo "❌ Error converting TGS to MP4"
        exit 1
    }

    # Шаг 2: Создание палитры GIF
    ffmpeg -i temp.mp4 -vf fps=24,scale=512:-1:flags=lanczos,palettegen=stats_mode=full -y palette.png || {
        echo "❌ Error generating palette.png"
        rm temp.mp4
        exit 1
    }

    # Шаг 3: MP4 → GIF (оптимизация до 18 МБ)
    ffmpeg -i temp.mp4 -i palette.png -filter_complex "fps=24,scale=512:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer" -fs 18M "$output_file" || {
        echo "❌ Error converting MP4 to GIF (max 18MB)"
        rm temp.mp4 palette.png
        exit 1
    }

    # Очистка временных файлов
    rm temp.mp4 palette.png

    echo "🎉 Conversion completed successfully: $output_file"
}

# Основной процесс
main() {
    check_and_install_dependencies
    check_ffmpeg
    if [[ $# -lt 1 ]]; then
        echo "❌ Usage: $0 input.tgs"
        exit 1
    fi
    convert_tgs_to_gif "$1"
}

main "$@"