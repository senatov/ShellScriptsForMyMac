#!/bin/zsh

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

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
        find "$DERIVED_DATA_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +3 -exec rm -rf {} \; -exec echo "[INFO] Deleted DerivedData: {}" \;
    else
        echo "[WARN] DerivedData directory not found: $DERIVED_DATA_DIR"
    fi
}

clean_brew_caches() {
    echo "[INFO] Cleaning Brew-related caches..."
    if command -v brew &>/dev/null; then
        BREW_CACHE=$(brew --cache)
        if [[ -n "$BREW_CACHE" && -e "$BREW_CACHE" ]]; then
            rm -rf "$BREW_CACHE"
            echo "[INFO] Homebrew cache cleared."
        else
            echo "[INFO] Brew cache ($BREW_CACHE) is empty or not found"
        fi
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

    find "$HOME/Library/Caches" -mindepth 1 -maxdepth 1 -type d ! -name 'com.apple.*' ! -name 'mds' ! -name 'com.apple.Spotlight' -mtime +7 -exec rm -rf {} \; -exec echo "[INFO] Deleted cache: {}" \;

    find "$HOME/Library/Application Support/Firefox/Profiles" -type d -name 'cache2' -exec rm -rf {} \; -exec echo "[INFO] Deleted Firefox cache: {}" \;

    TARGETS=(
        "$HOME/Library/Logs/DiagnosticReports"
        "$HOME/Library/Application Support/CrashReporter"
        "$HOME/Library/Saved Application State"
    )

    for dir in "${TARGETS[@]}"; do
        [[ -d "$dir" ]] && find "$dir" -type f -mtime +7 -exec rm -v {} \;
    done
}

clean_simulator_data() {
    echo "[INFO] Cleaning old iOS Simulator data..."
    SIMULATOR_DIR="$HOME/Library/Developer/CoreSimulator/Devices"
    [[ -d "$SIMULATOR_DIR" ]] && find "$SIMULATOR_DIR" -type d -name "data" -mtime +10 -exec rm -rf {} \; && echo "[INFO] Old simulator data removed."
}

extended_cleanup() {
    echo "[INFO] Extended cleanup for macOS 15.4 caches and trash..."

    find "$HOME/.Trash" -mindepth 1 -mtime +3 -exec rm -rf {} \; -exec echo "[INFO] Deleted from Trash: {}" \;

    for CACHE_DIR in "$HOME/Library/Application Support/Google/Chrome" "$HOME/Library/Application Support/Microsoft Edge"; do
        [[ -d "$CACHE_DIR" ]] && find "$CACHE_DIR" -type d -path "*Profile*/Cache" -exec find {} -mindepth 1 -mtime +3 -delete \; -exec echo "[INFO] Cleared cache in: {}" \;
    done

    for LOG_DIR in "/Library/Logs/DiagnosticReports" "/Library/Application Support/CrashReporter"; do
        [[ -d "$LOG_DIR" ]] && find "$LOG_DIR" -mindepth 1 -mtime +3 -exec rm -rf {} + -prune -exec echo "[INFO] Deleted logs/reports older than 3 days in: $LOG_DIR" \;
    done
}

update_brew
cleanup_derived_data
clean_brew_caches
clean_temp_files
clean_user_caches
clean_simulator_data
extended_cleanup

echo "[INFO] Maintenance tasks completed."