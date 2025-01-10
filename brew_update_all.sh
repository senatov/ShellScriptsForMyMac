#!/bin/zsh

# Log file setup
LOG_FILE="$HOME/brew_update.log"
if [[ -f $LOG_FILE && $(du -m "$LOG_FILE" | cut -f1) -gt 100 ]]; then
    mv "$LOG_FILE" "${LOG_FILE}_$(date +%F-%H%M%S).log"
fi
exec > >(tee -i "$LOG_FILE") 2>&1

echo "Starting full system maintenance with Homebrew under zsh..."

# Ensure Homebrew is installed
if ! command -v brew &>/dev/null; then
    echo "Error: Homebrew is not installed. Please install it first."
    exit 1
fi

# Function to update and upgrade Homebrew packages
update_brew() {
    echo "Updating Homebrew..."
    brew update || echo "Error updating Homebrew."

    echo "Upgrading outdated packages..."
    outdated_packages=$(brew outdated)
    if [[ -n $outdated_packages ]]; then
        brew upgrade || echo "Error upgrading packages."
    else
        echo "No outdated packages found."
    fi

    echo "Cleaning up old versions..."
    brew cleanup -s || echo "Error during cleanup."
}

# Function to inspect and clean caches
clean_caches() {
    echo "Cleaning user caches..."
    user_cache=$(find ~/Library/Caches -type f -size +50M)
    if [[ -n $user_cache ]]; then
        echo "$user_cache" | xargs rm -f || echo "Error cleaning user cache."
    else
        echo "No large files in user cache."
    fi

    echo "Cleaning system caches..."
    sudo find /Library/Caches -type f -size +50M -exec rm -f {} + || echo "Error cleaning system cache."
}

# Function to inspect and remove temporary files
clean_temp_files() {
    echo "Cleaning temporary files..."
    temp_files=$(find /tmp -type f -mtime +7)
    if [[ -n $temp_files ]]; then
        echo "$temp_files" | xargs rm -f || echo "Error removing temporary files."
    else
        echo "No old temporary files found."
    fi
}

# Function to find and optionally delete large files
inspect_large_files() {
    echo "Inspecting large files (>150MB)..."
    large_files=$(find ~/ -type f -size +150M -exec du -h {} + | sort -hr | head -n 10)
    if [[ -n $large_files ]]; then
        echo "Large files found:"
        echo "$large_files"
        echo "Requesting confirmation for deletion..."
        echo "$large_files" | awk '{print $2}' | while read -r file; do
            read -p "Delete $file? (y/n): " confirm
            if [[ $confirm == "y" || $confirm == "Y" ]]; then
                rm -f "$file" || echo "Error deleting $file."
            else
                echo "$file not deleted."
            fi
        done
    else
        echo "No large files found."
    fi
}

# Function to remove broken symlinks
remove_broken_symlinks() {
    echo "Searching for broken symbolic links..."
    broken_symlinks=$(find / -type l ! -exec test -e {} \; -print 2>/dev/null)
    if [[ -n $broken_symlinks ]]; then
        echo "Broken symbolic links found. Removing..."
        echo "$broken_symlinks" | xargs rm -f || echo "Error removing broken symlinks."
    else
        echo "No broken symbolic links found."
    fi
}

# Function to update system tools
update_system_tools() {
    echo "Updating system tools..."
    sudo softwareupdate --install --all || echo "Error updating system tools."
}

# Perform all maintenance tasks
update_brew
clean_caches
clean_temp_files
inspect_large_files
remove_broken_symlinks
update_system_tools

# Calculate freed disk space
freed_space=$(df -h | grep "/$" | awk '{print $4}')
echo "System maintenance completed! Freed disk space: $freed_space."
echo "Log saved to $LOG_FILE."