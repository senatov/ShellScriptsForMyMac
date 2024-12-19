#!/bin/bash

LOG_FILE=~/brew_update.log
exec > >(tee -i $LOG_FILE)
exec 2>&1

echo "Запуск обновления Homebrew, очистки системы и обновления шрифтов..."

# Запрос root-доступа в начале
if [ "$EUID" -ne 0 ]; then
    echo "Для выполнения скрипта требуются права администратора. Введите пароль:"
    sudo -v || { echo "Ошибка: root-доступ не предоставлен. Скрипт завершён."; exit 1; }
    echo "Root-доступ успешно предоставлен."
fi

# Функция для проверки и удаления файла с подтверждением
check_and_delete() {
    local file=$1
    echo "Проверяем файл $file..."
    if [[ -f $file ]]; then
        read -p "Удалить файл $file? (y/n): " confirm
        if [[ $confirm == "y" || $confirm == "Y" ]]; then
            echo "Удаляем файл $file..."
            rm -f "$file" || echo "Ошибка: не удалось удалить $file."
        else
            echo "Файл $file не удалён."
        fi
    else
        echo "Файл $file не найден или не может быть удалён."
    fi
}

# Функция для автоматического удаления временных или битых временных файлов
delete_temp_or_broken_files() {
    local file=$1
    if [[ -f $file ]]; then
        echo "Удаляем временный или битый файл $file..."
        rm -f "$file" || echo "Ошибка: не удалось удалить $file."
    fi
}

# Git операции в директории Homebrew
cd /opt/homebrew || { echo "Ошибка: не удалось перейти в директорию Homebrew."; exit 1; }
echo "Сохраняем изменения в Git..."
git stash -u && git clean -d -f || { echo "Ошибка в Git при сохранении изменений."; exit 1; }

# Обновление Homebrew
echo "Обновляем Homebrew..."
brew update || { echo "Ошибка: не удалось обновить Homebrew."; exit 1; }
brew doctor || echo "Некоторые проблемы с Homebrew требуют внимания."

# Обновление пакетов
echo "Обновляем пакеты..."
brew upgrade || echo "Ошибка при обновлении пакетов."

# Обновление шрифтов
echo "Проверяем устаревшие шрифты..."
outdated_fonts=$(brew outdated --cask | grep font-)

if [ -n "$outdated_fonts" ]; then
    echo "Устаревшие шрифты найдены. Обновляем..."
    echo "$outdated_fonts" | while read -r font; do
        echo "Обновляем $font..."
        brew upgrade --cask "$font" || echo "Ошибка при обновлении $font."
    done
else
    echo "Все шрифты актуальны. Обновление не требуется."
fi

# Очистка старых версий
echo "Удаляем старые версии пакетов..."
brew cleanup -s || echo "Ошибка очистки пакетов."

# Удаление битых симлинков
echo "Проверяем битые симлинки..."
broken_symlinks=$(find /opt/homebrew -type l ! -exec test -e {} \; -print)
if [ -n "$broken_symlinks" ]; then
    echo "Удаляем битые симлинки..."
    echo "$broken_symlinks" | xargs rm -f || echo "Ошибка при удалении симлинков."
else
    echo "Битых симлинков не найдено."
fi

# Очистка временных файлов и кэша
echo "Очищаем системный кэш и временные файлы..."
find ~/Library/Caches -type f -size +50M -exec rm -f {} + || echo "Ошибка при очистке временных файлов."
sudo find /Library/Caches -type f -size +50M -exec rm -f {} + || echo "Ошибка при очистке временных системных файлов."

# Обновление инструментов Xcode
echo "Обновляем инструменты Xcode..."
sudo softwareupdate --install --all

# Проверка больших файлов и удаление с подтверждением
echo "Ищем большие файлы (>150MB)..."
large_files=$(find ~/ -type f -size +150M -exec du -h {} + | sort -hr | head -n 10)
if [ -n "$large_files" ]; then
    echo "Найдены большие файлы:"
    echo "$large_files"
    echo "Запрашиваем подтверждение для удаления остальных файлов..."
    echo "$large_files" | awk '{print $2}' | while read -r file; do
        check_and_delete "$file"
    done
else
    echo "Больших файлов не найдено."
fi

# Финальные Git-операции
echo "Фиксируем изменения в Git..."
git add -A && git commit -m "Автоматические изменения после обновления и очистки системы" || echo "Ошибка фиксации изменений в Git."

echo "Обновление и очистка системы завершены! Лог: $LOG_FILE"