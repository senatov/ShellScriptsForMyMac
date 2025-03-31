#!/bin/zsh

# Устанавливаем корректный PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

# Запрашиваем root-пароль
echo "Please enter your password to proceed with maintenance tasks:"
sudo -v

# Поддержка активности sudo
keep_sudo_alive() {
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_PID=$!
    trap 'kill $SUDO_PID' EXIT
}
keep_sudo_alive

update_brew() {
    echo "[INFO] Updating Homebrew..."
    if ! command -v brew &>/dev/null; then
        echo "[ERROR] Homebrew not found. Skipping update."
        return
    fi
    brew update || echo "[ERROR] Error updating Homebrew."

    echo "[INFO] Upgrading outdated packages..."
    if [[ -n $(brew outdated) ]]; then
        brew upgrade || echo "[ERROR] Error upgrading packages."
    else
        echo "[INFO] No outdated packages found."
    fi

    echo "[INFO] Cleaning up old versions..."
    brew cleanup || echo "[ERROR] Error during cleanup."
}

clean_brew_caches() {
    echo "[INFO] Cleaning Brew-related caches..."
    if command -v brew &>/dev/null; then
        rm -rf "$(brew --cache)"
        echo "[INFO] Homebrew cache cleared."
    else
        echo "[ERROR] Homebrew not found. Skipping cache cleanup."
    fi
}

clean_temp_files() {
    echo "[INFO] Cleaning temporary system files older than 4 days..."
    sudo find /var/folders -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
    sudo find /var/folders -mindepth 1 -type d -mtime +4 -empty -exec rmdir -v {} \; 2>/dev/null

    find ~/Library/Logs/DiagnosticReports/ -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
}

clean_xcode_data() {
    echo "[INFO] Cleaning Xcode-related directories..."

    # Очистка DerivedData
    if [ -d ~/Library/Developer/Xcode/DerivedData ] && [ "$(ls -A ~/Library/Developer/Xcode/DerivedData)" ]; then
        rm -rf ~/Library/Developer/Xcode/DerivedData/*
        echo "[INFO] Cleared DerivedData."
    else
        echo "[INFO] No files in DerivedData to clean."
    fi

    # Очистка Xcode Previews
    if [ -d ~/Library/Developer/Xcode/UserData/Previews ] && [ "$(ls -A ~/Library/Developer/Xcode/UserData/Previews)" ]; then
        rm -rf ~/Library/Developer/Xcode/UserData/Previews/*
        echo "[INFO] Cleared Xcode Previews."
    else
        echo "[INFO] No files in Xcode Previews to clean."
    fi
}

clean_firefox_temp() {
    echo "[INFO] Cleaning Firefox temporary files..."

    # Определяем пути через переменные окружения
    FIREFOX_PROFILE_DIR="${HOME}/Library/Application Support/Firefox"
    FIREFOX_CRASH_REPORTS="${FIREFOX_PROFILE_DIR}/Crash Reports"

    # Проверяем, существует ли папка и содержит ли она файлы
    if [ -d "$FIREFOX_CRASH_REPORTS" ] && [ "$(ls -A "$FIREFOX_CRASH_REPORTS")" ]; then
        rm -rf "$FIREFOX_CRASH_REPORTS"/*
        echo "[INFO] Cleared Firefox crash reports."
    else
        echo "[INFO] No Firefox crash reports to clean."
    fi
}

clean_user_caches() {
    echo "[INFO] Cleaning general user caches..."

    find ~/Library/Containers/*/Data/Library/Caches/ -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
    find ~/Library/Caches/ -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
}

# Выполнение задач
update_brew
clean_brew_caches
clean_xcode_data
clean_firefox_temp
clean_user_caches
echo "[INFO] System maintenance completed successfully!"
$HOME/.oh-my-zsh/tools/upgrade.sh