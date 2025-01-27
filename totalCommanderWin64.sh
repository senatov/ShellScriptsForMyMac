#!/bin/zsh

# Проверка, установлен ли Wine
if ! command -v wine &> /dev/null; then
    echo "Wine не установлен. Пожалуйста, установите его перед запуском скрипта."
    exit 1
fi

# Путь к исполняемому файлу Total Commander
TOTALCMD_PATH="c:\\Program Files\\totalcmd\\TOTALCMD64.EXE"

# Запуск Total Commander через Wine
echo "Запуск Total Commander через Wine..."
wine "$TOTALCMD_PATH"

# Проверка, успешно ли выполнена команда
if [ $? -eq 0 ]; then
    echo "Total Commander успешно запущен!"
else
    echo "Ошибка при запуске Total Commander."
    exit 1
fi