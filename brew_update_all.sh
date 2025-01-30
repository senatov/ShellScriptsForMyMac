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

clean_old_temp_in_var_folders() {
    echo "[INFO] Cleaning old files from /var/folders (older than 5 days)..."

    # Удаляем файлы старше 5 дней
    sudo find /var/folders -type f -mtime +5 -exec rm -v {} \; 2>/dev/null

    # Удаляем пустые директории (старше 5 дней)
    sudo find /var/folders -mindepth 1 -type d -mtime +5 -empty -exec rmdir -v {} \; 2>/dev/null

    echo "[INFO] Finished cleaning old files from /var/folders."
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
    echo "[INFO] Attempting to verify/repair disk in normal mode..."

    # 1. Проверяем, доступна ли вообще команда diskutil
    if ! command -v diskutil &>/dev/null; then
        echo "[WARNING] 'diskutil' not found. Skipping disk verification."
        return 1
    fi

    # 2. Пытаемся проверить корневой том (обычно '/')
    echo "[INFO] Verifying root volume '/'..."
    if sudo diskutil verifyVolume /; then
        echo "[INFO] Root volume: verification complete."
        echo "[INFO] Trying to repair root volume '/' (if possible)..."
        if ! sudo diskutil repairVolume /; then
            echo "[WARNING] Repair on '/' may be not fully supported (APFS or read-only system)."
        fi
    else
        echo "[WARNING] Failed to verify '/' or it's not fully supported."
    fi

    # 3. На APFS системах есть Data-том (например, 'Macintosh HD - Data').
    #    Попробуем найти его через diskutil list и проверить/починить.
    #    Это «best effort» — в зависимости от именования тома.
    echo "[INFO] Checking if there's a separate Data volume..."
    data_volume=$(diskutil list | awk '/Container/ { c=$NF } /Data$/ { print $NF " " c }' | awk '{ print $1 }')
    # Логика:
    #  - /Container/ (строка) даёт идентификатор контейнера, запоминаем в c.
    #  - /Data$/ ищет строку, оканчивающуюся на "Data", берёт идентификатор тома.
    #  - Далее awk печатает том и контейнер, но нам нужен только том, т.е. $1.

    # Если найти конкретный Data-том не получается, можно попытаться проверить все «- Data»:
    if [[ -z "$data_volume" ]]; then
        echo "[INFO] Data volume not automatically detected. Trying fallback approach..."
        # Просто найдём все тома с именем "Data" в конце и проверим/починим их
        all_data_volumes=$(diskutil list | grep "Data" | awk '{print $NF}')
        if [[ -n "$all_data_volumes" ]]; then
            for vol in $all_data_volumes; do
                echo "[INFO] Trying to verify '$vol'..."
                sudo diskutil verifyVolume "$vol" || echo "[WARNING] Cannot verify volume $vol"
                echo "[INFO] Trying to repair '$vol'..."
                sudo diskutil repairVolume "$vol" || echo "[WARNING] Cannot repair volume $vol"
            done
        else
            echo "[WARNING] No Data volume found by name."
        fi
    else
        echo "[INFO] Found Data volume: $data_volume"
        echo "[INFO] Verifying Data volume..."
        sudo diskutil verifyVolume "$data_volume" || echo "[WARNING] Verification of '$data_volume' failed."
        echo "[INFO] Repairing Data volume..."
        sudo diskutil repairVolume "$data_volume" || echo "[WARNING] Repair of '$data_volume' not fully possible."
    fi

    echo "[INFO] Disk verify/repair attempts finished."
    echo "[INFO] NOTE: For a full system repair on APFS, Apple recommends using Recovery Mode."
}

update_brew
clean_brew_caches
clean_temp_logs_and_caches
remove_broken_symlinks
clean_old_temp_in_var_folders
verify_and_repair_disk