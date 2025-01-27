#!/bin/zsh

# Установим переменные для выходного файла и директории проекта
OUTPUT_FILE="${1:-~/Downloads/mimi_project.zip}"
PROJECT_DIR="${2:-$(pwd)}"

# Расширим тильду в пути для корректной работы
OUTPUT_FILE=$(eval echo "$OUTPUT_FILE")

# Список исключаемых файлов и директорий
EXCLUDE_PATTERNS=(
    "*.git/*"
    "*DerivedData/*"
    "*xcuserdata/*"
    "*xcarchive/*"
    "*build/*"
    "Packages/*"
    "*.DS_Store"
    ".github/*"
    ".git/*"
    ".idea/*"
    "*.dSYM"
    "*.dSYM.zip"
    "*.hmap"
    "*.ipa"
    "*.mdb"
)


# Генерация строки с исключениями для команды zip
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_ARGS+=("-x" "$pattern")
done

# Уведомление о начале упаковки
echo "Начинается упаковка содержимого директории '$PROJECT_DIR' в '$OUTPUT_FILE'..."
echo "Исключаемые файлы:"
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    echo "  - $pattern"
done

# Убедимся, что целевая директория существует
mkdir -p "$(dirname "$OUTPUT_FILE")"

# Переместимся в директорию проекта для сохранения только содержимого
cd "$PROJECT_DIR" || { echo "Не удалось перейти в директорию $PROJECT_DIR"; exit 1; }

# Выполнение команды zip
zip -r "$OUTPUT_FILE" . "${EXCLUDE_ARGS[@]}"

# Проверка статуса выполнения
if [ $? -eq 0 ]; then
    echo "Проект успешно упакован в: $OUTPUT_FILE"
else
    echo "Ошибка при упаковке проекта!"
    exit 1
fi