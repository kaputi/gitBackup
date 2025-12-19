#!/bin/bash

# Git Repository Backup Script with Rotation
# Optimized for systemd service with journald logging

set -euo pipefail

# Default config file location (can be overridden)
CONFIG_FILE="${1:-/etc/git-backup/backup-config.conf}"

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Configuration file not found: $CONFIG_FILE"
  echo "Usage: $0 [config-file]"
  exit 1
fi

# Load configuration
source "$CONFIG_FILE"

# Validate required variables
if [[ -z "${SOURCE_PATH:-}" ]] || [[ -z "${BACKUP_PATH:-}" ]] || [[ -z "${KEEP_COPIES:-}" ]]; then
  echo "Error: Missing required configuration variables"
  echo "Required: SOURCE_PATH, BACKUP_PATH, KEEP_COPIES"
  exit 1
fi

# Check if source directory exists
if [[ ! -d "$SOURCE_PATH" ]]; then
  echo "Error: Source directory does not exist: $SOURCE_PATH"
  exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_PATH"

# Generate timestamp for this backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup_${TIMESTAMP}"
CURRENT_BACKUP="${BACKUP_PATH}/${BACKUP_NAME}"

echo "=========================================="
echo "Git Repository Backup"
echo "=========================================="
echo "Started at: $(date)"
echo "Source: $SOURCE_PATH"
echo "Destination: $CURRENT_BACKUP"
echo "Keeping: $KEEP_COPIES copies"
echo ""

# Perform the backup using rsync
echo "Running rsync..."
echo "rsync -avz --delete --stats $SOURCE_PATH/ $CURRENT_BACKUP/"
rsync -avz --delete \
  --stats \
  "$SOURCE_PATH/" \
  "$CURRENT_BACKUP/"

RSYNC_EXIT_CODE=$?

if [[ $RSYNC_EXIT_CODE -eq 0 ]]; then
  echo ""
  echo "✓ Backup completed successfully"
else
  echo ""
  echo "✗ Backup failed with exit code: $RSYNC_EXIT_CODE"
  exit $RSYNC_EXIT_CODE
fi

# Compress old backups (if enabled)
if [[ -n "${KEEP_UNCOMPRESSED:-}" ]] && [[ "${KEEP_UNCOMPRESSED}" -gt 0 ]]; then
  echo ""
  echo "Compressing old backups (keeping $KEEP_UNCOMPRESSED most recent uncompressed)..."

  cd "$BACKUP_PATH"

  # Get list of uncompressed backup directories sorted by timestamp (newest first)
  mapfile -t UNCOMPRESSED_BACKUPS < <(find . -maxdepth 1 -type d -name "backup_*" -printf '%T+ %p\n' | sort -r | cut -d' ' -f2)

  UNCOMPRESSED_COUNT=${#UNCOMPRESSED_BACKUPS[@]}
  echo "Found $UNCOMPRESSED_COUNT uncompressed backup(s)"

  if [[ $UNCOMPRESSED_COUNT -gt $KEEP_UNCOMPRESSED ]]; then
    BACKUPS_TO_COMPRESS=$((UNCOMPRESSED_COUNT - KEEP_UNCOMPRESSED))
    echo "Compressing $BACKUPS_TO_COMPRESS old backup(s)..."

    # Compress backups older than the N most recent
    for ((i=KEEP_UNCOMPRESSED; i<UNCOMPRESSED_COUNT; i++)); do
      BACKUP_DIR="${UNCOMPRESSED_BACKUPS[$i]}"
      BACKUP_NAME="${BACKUP_DIR#./}"
      ARCHIVE_NAME="${BACKUP_NAME}.tar.gz"

      # Skip if already compressed
      if [[ -f "$ARCHIVE_NAME" ]]; then
        echo "  Skipping $BACKUP_NAME (archive already exists)"
        continue
      fi

      echo "  Compressing: $BACKUP_NAME -> $ARCHIVE_NAME"
      tar -czf "$ARCHIVE_NAME" -C . "$BACKUP_NAME" 2>&1

      if [[ $? -eq 0 ]]; then
        echo "  Removing uncompressed: $BACKUP_NAME"
        rm -rf "$BACKUP_DIR"
      else
        echo "  Warning: Compression failed for $BACKUP_NAME, keeping uncompressed"
      fi
    done
  else
    echo "No compression needed (only $UNCOMPRESSED_COUNT uncompressed backup(s))"
  fi
else
  echo ""
  echo "Compression disabled (KEEP_UNCOMPRESSED not set or is 0)"
fi

# Rotate old backups - keep only the N most recent (including compressed)
echo ""
echo "Rotating old backups (keeping $KEEP_COPIES most recent)..."

# Get list of all backups (directories and archives) sorted by modification time (oldest first)
cd "$BACKUP_PATH"
BACKUP_COUNT=$(find . -maxdepth 1 \( -type d -name "backup_*" -o -type f -name "backup_*.tar.gz" \) | wc -l)

echo "Total backups found: $BACKUP_COUNT (compressed + uncompressed)"

if [[ $BACKUP_COUNT -gt $KEEP_COPIES ]]; then
  BACKUPS_TO_DELETE=$((BACKUP_COUNT - KEEP_COPIES))
  echo "Removing $BACKUPS_TO_DELETE old backup(s)..."

  # Find and delete oldest backups (both directories and archives)
  find . -maxdepth 1 \( -type d -name "backup_*" -o -type f -name "backup_*.tar.gz" \) -printf '%T+ %p\n' |
    sort |
    head -n $BACKUPS_TO_DELETE |
    cut -d' ' -f2 |
    while read -r old_backup; do
      echo "  Deleting: $old_backup"
      if [[ -d "$old_backup" ]]; then
        rm -rf "$old_backup"
      else
        rm -f "$old_backup"
      fi
    done
else
  echo "No rotation needed (only $BACKUP_COUNT backup(s) exist)"
fi

echo ""
echo "=========================================="
echo "Backup completed at: $(date)"
echo "=========================================="

exit 0
