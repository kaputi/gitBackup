#!/bin/bash

# Installation script for Git Repository Backup System (Go version, systemd)

set -e

echo "Installing Git Repository Backup System"
echo "=============================================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "This script should be run as root (or with sudo)"
  echo "Usage: sudo ./install.sh"
  exit 1
fi

# Check if Go binary exists
if [[ ! -f ./bin/git-backup ]]; then
  echo "Error: ./bin/git-backup not found"
  echo "Please run 'make' to build the binary first"
  exit 1
fi

# Check for required dependencies

echo "Checking dependencies..."
if ! command -v systemctl &>/dev/null; then
  echo "Error: this script requires systemd"
  exit1
fi

MISSING_DEPS=()

if ! command -v rsync &>/dev/null; then
  MISSING_DEPS+=("rsync")
fi

if ! command -v tar &>/dev/null; then
  MISSING_DEPS+=("tar")
fi

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
  echo "Error: Missing required dependencies: ${MISSING_DEPS[*]}"
  echo ""
  echo "Please install them first:"
  echo "  Debian/Ubuntu: sudo apt install rsync tar"
  echo "  Arch Linux:    sudo pacman -S rsync tar"
  echo "  Fedora/RHEL:   sudo dnf install rsync tar"
  exit 1
fi

echo "  All dependencies found"
echo ""

# Create directories
echo "Creating directories..."
mkdir -p /etc/git-backup

# Copy files
echo "Installing binary..."
cp ./bin/git-backup /usr/local/bin/git-backup
chmod +x /usr/local/bin/git-backup

echo "Installing configuration..."
if [[ -f /etc/git-backup/backup-config.conf ]]; then
  echo "  Config file already exists, creating backup..."
  cp /etc/git-backup/backup-config.conf /etc/git-backup/backup-config.conf.bak
fi
cp backup-config.conf /etc/git-backup/backup-config.conf

echo "Installing systemd units..."
cp git-backup.service /etc/systemd/system/
cp git-backup.timer /etc/systemd/system/

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "=========================================="
echo ""
echo "1. Edit the configuration file:"
echo "   sudo nano /etc/git-backup/backup-config.conf"
echo ""
echo "2. Update these settings:"
echo "   - SOURCE_PATH: Path to your git repositories"
echo "   - BACKUP_PATH: Where to store backups"
echo "   - KEEP_COPIES: Number of backups to keep"
echo "   - KEEP_UNCOMPRESSED: number of backups that wont be compressed"
echo "   - BACKUP_INTERVAL_HOURS: time between backups (this is only for reference the actal config is done in  /etc/systemd/system/git-backup.timer)"
echo ""
echo "3. Test the backup manually:"
echo "   sudo systemctl start git-backup.service"
echo ""
echo "4. Check the status and logs:"
echo "   sudo systemctl status git-backup.service"
echo "   sudo journalctl -u git-backup.service -n 50"
echo ""
echo "5. Enable automatic backups:"
echo "   sudo systemctl enable --now git-backup.timer"
echo ""
echo "6. Check timer status:"
echo "   sudo systemctl list-timers git-backup.timer"
echo ""
echo "Useful commands:"
echo "  View logs:        journalctl -u git-backup.service -f"
echo "  Manual backup:    systemctl start git-backup.service"
echo "  Disable timer:    systemctl disable git-backup.timer"
echo "  Check next run:   systemctl list-timers"
echo ""
