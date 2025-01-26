#!/bin/zsh

# Устанавливаем корректный PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

# Запрашиваем root-пароль
echo "Please enter your password to proceed with maintenance tasks:"
sudo -v
# Поддерживаем активность sudo
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

update_brew() {
    echo "[INFO] Updating Homebrew..."
    brew update || echo "[ERROR] Error updating Homebrew."

    echo "[INFO] Upgrading outdated packages..."
    outdated_packages=$(brew outdated)
    if [[ -n $outdated_packages ]]; then
        brew upgrade || echo "[ERROR] Error upgrading packages."
    else
        echo "[INFO] No outdated packages found."
    fi

    echo "[INFO] Cleaning up old versions..."
    brew cleanup -s || echo "[ERROR] Error during cleanup."
}


# Очистка кешей Homebrew
clean_brew_caches() {
    echo "[INFO] Cleaning Brew-related caches..."

    # Проверяем, доступна ли brew
    if ! command -v brew &>/dev/null; then
        echo "[ERROR] Homebrew is not installed or not in PATH."
        return 1
    fi

    # Выполняем очистку кешей
    brew cleanup || echo "[ERROR] Failed to clean Brew caches."
}


clean_temp_logs_and_caches() {
    echo "[INFO] Cleaning temporary files, logs, and caches older than 3 days..."

    # Обновлённый список директорий для очистки
    local directories=(
        "/tmp"
        "/private/tmp"
        "/Users/$USER/Library/Caches"  # Пользовательский кеш
        "/Users/$USER/Library/Logs"   # Пользовательские логи
   )

    for dir in "${directories[@]}"; do
        if [ -d "$dir" ]; then
            echo "[INFO] Cleaning directory: $dir"
            sudo find "$dir" -type f -mtime +3 -exec rm -v {} \; 2>/dev/null || echo "[WARNING] Failed to clean: $dir"
        else
            echo "[WARNING] Directory not found: $dir"
        fi
    done
    echo "[INFO] Finished cleaning temporary files, logs, and caches."
}


remove_broken_symlinks() {
    echo "[INFO] Searching for broken symbolic links..."

    # Исключаем директории, которые не нужно проверять
    local exclude_paths=(
        "/Volumes/*"
        "/System/*"
        "/Library/*"
        "/private/var/*"
    )

    # Генерация аргументов для исключения
    local exclude_args=""
    for path in "${exclude_paths[@]}"; do
        exclude_args="$exclude_args ! -path '$path'"
    done

    # Поиск и удаление сломанных ссылок
    eval "find / -type l $exclude_args ! -exec test -e {} \; -exec sudo rm -v {} \; 2>/dev/null" || {
        echo "[ERROR] Issues removing broken symlinks."
        return 1
    }

    echo "[INFO] Finished removing broken symlinks."
}

verify_and_repair_disk() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "[INFO] Verifying disk volume..."
        sudo diskutil verifyVolume / || echo "[ERROR] Disk verification failed."

        echo "[INFO] Repairing disk volume..."
        sudo diskutil repairVolume / || echo "[ERROR] Disk repair failed."
    else
        echo "[WARNING] Disk maintenance commands are only available on macOS."
    fi
}

update_brew
clean_brew_caches
clean_temp_logs_and_caches
remove_broken_symlinks
verify_and_repair_disk