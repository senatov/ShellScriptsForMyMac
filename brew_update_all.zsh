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

clean_brew_caches() {
    echo "[INFO] Cleaning Brew-related caches..."
    if ! command -v brew &>/dev/null; then
        echo "[ERROR] Homebrew is not installed or not in PATH."
        return 1
    fi
    brew cleanup || echo "[ERROR] Failed to clean Brew caches."
}

clean_old_temp_in_var_folders() {
    echo "[INFO] Cleaning old files from /var/folders (older than 4 days)..."
    sudo find /var/folders -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
    sudo find /var/folders -mindepth 1 -type d -mtime +4 -empty -exec rmdir -v {} \; 2>/dev/null
}

clean_additional_caches() {
    echo "[INFO] Cleaning additional caches and temporary files older than 4 days..."

    find ~/Library/Application\ Support/Caches/ -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
    find ~/Library/Containers/*/Data/Library/Caches/ -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
    find ~/Library/Logs/DiagnosticReports/ -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
    find ~/Library/Caches/com.apple.Safari/ -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
    find ~/Library/Application\ Support/Google/Chrome/Default/Cache/ -type f -mtime +4 -exec rm -v {} \; 2>/dev/null
    find ~/Library/Application\ Support/Firefox/Profiles/*.default-release/cache2/ -type f -mtime +4 -exec rm -v {} \; 2>/dev/null

    echo "[INFO] Additional caches cleaned."
}

verify_disk() {
    echo "[INFO] Attempting to verify/repair disk in normal mode..."
    if ! command -v /usr/sbin/diskutil &>/dev/null; then
        echo "[ERROR] '/usr/sbin/diskutil' not found. Skipping disk verification."
        return 1
    fi
    if ! sudo /usr/sbin/diskutil verifyVolume /; then
        echo "[ERROR] Disk verification failed. Check manually."
    else
        echo "[INFO] Disk verification completed successfully."
    fi
}

main() {
    update_brew
    clean_brew_caches
    clean_old_temp_in_var_folders
    clean_additional_caches
    verify_disk
    echo "[INFO] Maintenance tasks completed."
}

main
