#!/bin/zsh

echo "Starting full system maintenance with Homebrew under zsh..."

# Check if Homebrew is installed
if ! command -v brew &>/dev/null; then
    echo "[ERROR] Homebrew is not installed. Please install it first."
    exit 1
fi

# Update Homebrew
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

# Clean user and system caches
clean_caches() {
    echo "[INFO] Cleaning user caches..."
    find ~/Library/Caches -type f -size +50M -print0 | xargs -0 rm -f || echo "[ERROR] Error cleaning user cache."

    echo "[INFO] Cleaning system caches..."
    sudo find /Library/Caches -type f -size +50M -exec rm -f {} + 2>/dev/null || echo "[ERROR] Error cleaning system cache."
}

# Clean temporary files
clean_temp_files() {
    echo "[INFO] Cleaning temporary files..."
    find /tmp -type f -mtime +7 -print0 | xargs -0 rm -f || echo "[ERROR] Error removing temporary files."
}

# Inspect large files
inspect_large_files() {
    echo "[INFO] Inspecting large files (>150MB)..."
    find / -type f -size +150M \
        \( ! -path "*mac_backup*" \
           ! -path "/System/Volumes/*" \
           ! -path "/Library/Developer/CoreSimulator/*" ! -path "/System/Volumes/Data/Library/Developer/CoreSimulator/*" \
        \) \
        -exec du -h {} + 2>/dev/null | sort -hr | head -n 10
    echo "[INFO] Done inspecting large files."
}

# Remove broken symbolic links
remove_broken_symlinks() {
    echo "[INFO] Searching for broken symbolic links..."
    find / -type l \
        \( ! -path "/Volumes/*" \
           ! -path "*mac_backup*" \
           ! -path "/System/Volumes/*" \
           ! -path "/Library/Developer/CoreSimulator/*" ! -path "/System/Volumes/Data/Library/Developer/CoreSimulator/*" \
        \) \
        ! -exec test -e {} \; -print 2>/dev/null | while IFS= read -r link; do
        rm -f "$link" || echo "[ERROR] Error removing broken symlink: $link"
    done
    echo "[INFO] Done searching broken symbolic links."
}

# Update system tools
update_system_tools() {
    echo "[INFO] Updating system tools..."
    sudo softwareupdate --install --all || echo "[ERROR] Error updating system tools."
}

# Verify and repair disk
verify_and_repair_disk() {
    echo "[INFO] Verifying disk volume..."
    diskutil verifyVolume / || echo "[ERROR] Disk verification failed."

    echo "[INFO] Repairing disk volume..."
    diskutil repairVolume / || echo "[ERROR] Disk repair failed."
}

# Analyze disk usage with ncdu
analyze_disk_usage() {
    echo "[INFO] Analyzing disk usage with ncdu..."
    if ! command -v ncdu &>/dev/null; then
        echo "[INFO] Installing ncdu..."
        brew install ncdu || echo "[ERROR] Failed to install ncdu."
    fi
    ncdu /
}

# Display disk usage summary with duf
display_disk_summary() {
    echo "[INFO] Displaying disk usage summary with duf..."
    if ! command -v duf &>/dev/null; then
        echo "[INFO] Installing duf..."
        brew install duf || echo "[ERROR] Failed to install duf."
    fi
    duf
}

# Execute tasks
update_brew
clean_caches
clean_temp_files
inspect_large_files
remove_broken_symlinks
update_system_tools
verify_and_repair_disk
analyze_disk_usage
display_disk_summary

# Final summary
freed_space=$(df -h | grep "/$" | awk '{print $4}')
echo "[INFO] System maintenance completed! Freed disk space: $freed_space."
