#!/bin/zsh

# Устанавливаем корректный PATH
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

# Поддерживаем sudo-сессию без повторного запроса пароля
keep_sudo_alive() {
    while ps -p $$ > /dev/null; do
        sudo -n true
        sleep 60
    done &
    SUDO_PID=$!
    trap 'kill $SUDO_PID' EXIT
}

echo "Please enter your password to proceed with maintenance tasks:"
sudo -v && keep_sudo_alive

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

cleanup_derived_data() {
    DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData"
    echo "[INFO] Checking DerivedData at: $DERIVED_DATA_DIR"

    if [[ -d "$DERIVED_DATA_DIR" ]]; then
        OLD_DIRS=($(find "$DERIVED_DATA_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +3))

        if [[ ${#OLD_DIRS[@]} -eq 0 ]]; then
            echo "[INFO] No DerivedData directories older than 3 days. Skipping."
        else
            echo "[INFO] Found ${#OLD_DIRS[@]} directories to remove:"
            for dir in "${OLD_DIRS[@]}"; do
                echo "  $dir"
            done

            echo "[INFO] Removing old DerivedData directories..."
            for dir in "${OLD_DIRS[@]}"; do
                rm -rf "$dir" && echo "[INFO] Deleted: $dir" || echo "[ERROR] Failed to delete: $dir"
            done
        fi
    else
        echo "[WARN] DerivedData directory not found: $DERIVED_DATA_DIR"
    fi
}

clean_brew_caches() {
    echo "[INFO] Cleaning Brew-related caches..."
    if command -v brew &>/dev/null; then
        BREW_CACHE=$(brew --cache)
        if [[ -n "$BREW_CACHE" && -e "$BREW_CACHE" ]]; then
            echo "Removing: $BREW_CACHE"
            rm -rf "$BREW_CACHE"
        else
            echo "Skipping: Brew cache ($BREW_CACHE) is empty or not found"
        fi
        echo "[INFO] Homebrew cache cleared."
    else
        echo "[ERROR] Homebrew not found. Skipping cache cleanup."
    fi
}

clean_temp_files() {
    echo "[INFO] Cleaning temporary system files older than 4 days..."
    sudo find /var/folders -mindepth 1 -type d -mtime +4 -empty -exec rmdir -v {} \; 2>/dev/null
}

clean_user_caches() {
    echo "[INFO] Cleaning user cache directories..."

    # 1. Безопасная очистка ~/Library/Caches (без Safari, Spotlight и системных)
    CACHE_DIR="$HOME/Library/Caches"
    if [[ -d "$CACHE_DIR" ]]; then
        echo "[INFO] Cleaning top-level items in: $CACHE_DIR"
        find "$CACHE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name 'com.apple.*' ! -name 'mds' ! -name 'com.apple.Spotlight' -mtime +7 -exec rm -rf {} \; -exec echo "[INFO] Deleted: {}" \;
    fi

    # 2. Firefox
    FIREFOX_DIR="$HOME/Library/Application Support/Firefox/Profiles"
    if [[ -d "$FIREFOX_DIR" ]]; then
        echo "[INFO] Cleaning Firefox cache folders..."
        find "$FIREFOX_DIR" -type d -name 'cache2' -exec rm -rf {} \; -exec echo "[INFO] Deleted: {}" \;
    fi

    # 3. Другие стандартные мусорные директории
    TARGETS=(
        "$HOME/Library/Logs/DiagnosticReports"
        "$HOME/Library/Application Support/CrashReporter"
        "$HOME/Library/Saved Application State"
    )

    for dir in "${TARGETS[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "[INFO] Cleaning: $dir"
            find "$dir" -type f -mtime +7 -exec rm -v {} \; 2>/dev/null
        else
            echo "[WARN] Directory not found: $dir"
        fi
    done
}

clean_simulator_data() {
    echo "[INFO] Cleaning old iOS Simulator data..."
    if command -v xcrun &>/dev/null; then
        SIMULATOR_DIR="$HOME/Library/Developer/CoreSimulator/Devices"
        if [[ -d "$SIMULATOR_DIR" ]]; then
            find "$SIMULATOR_DIR" -type d -name "data" -mtime +10 -exec rm -rf {} \; 2>/dev/null
            echo "[INFO] Old simulator data removed."
        else
            echo "[WARN] Simulator directory not found."
        fi
    else
        echo "[WARN] xcrun not found. Skipping simulator cleanup."
    fi
}

# Запускаем обновление и очистку
update_brew
cleanup_derived_data
clean_brew_caches
clean_temp_files
clean_user_caches
clean_simulator_data

# Готово
echo "[INFO] Maintenance tasks completed."