#!/bin/zsh

# Set variables
SRC_BACKUP_DIR="/Volumes/.timemachine/57BE6DED-4C08-4427-9096-1D087D6BA220"
DEST_DIR="/Users/senat/Library/CloudStorage/ProtonDrive-javaentwickler@gmail.com-folder/Backups"
TIMESTAMP=$(/bin/date "+%Y-%m-%d_%H-%M-%S")
LOG_FILE="$DEST_DIR/backup_log_$TIMESTAMP.txt"

# Create destination folder if it doesn't exist
mkdir -p "$DEST_DIR"

# Logging header
echo "[INFO] Starting Time Machine copy at $TIMESTAMP" >> "$LOG_FILE"

# Get the latest backup path
LATEST_BACKUP=$(tmutil latestbackup)

if [[ -z "$LATEST_BACKUP" ]]; then
  echo "[ERROR] No Time Machine backup found!" >> "$LOG_FILE"
  exit 1
fi

echo "[INFO] Latest backup: $LATEST_BACKUP" >> "$LOG_FILE"

# What to copy
INCLUDE_PATHS=(
  "$LATEST_BACKUP/Users/senat/Documents"
  "$LATEST_BACKUP/Users/senat/Library/Application Support"
  "$LATEST_BACKUP/Users/senat/.config"
)

# Rsync each path
for path in $INCLUDE_PATHS; do
  if [[ -d "$path" ]]; then
    echo "[INFO] Copying: $path" >> "$LOG_FILE"
    rsync -aHAX --progress "$path" "$DEST_DIR" >> "$LOG_FILE" 2>&1
  else
    echo "[WARNING] Path not found: $path" >> "$LOG_FILE"
  fi
done

# Final log
END_TIME=$(/bin/date "+%Y-%m-%d %H:%M:%S")
echo "[SUCCESS] Backup completed at $END_TIME" >> "$LOG_FILE"