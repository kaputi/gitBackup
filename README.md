# Git Repository Backup System (systemd)

A simple, configurable backup solution for git repositories using rsync with automatic rotation, managed by systemd with journald logging.

## Features

- ✓ Incremental backups using rsync
- ✓ Timestamped backup directories
- ✓ Automatic rotation (keeps N most recent backups)
- ✓ Automatic compression of old backups (keep recent ones uncompressed for fast restoration)
- ✓ Configuration file for all settings
- ✓ systemd service and timer for reliable scheduling
- ✓ Centralized logging via journald
- ✓ Easy monitoring with systemctl and journalctl

## Installation

### Quick Install

```bash
sudo ./install.sh
```

### Manual Install

```bash
# Copy script to system
sudo cp git-backup.sh /usr/local/bin/git-backup
sudo chmod +x /usr/local/bin/git-backup

# Create config directory
sudo mkdir -p /etc/git-backup
sudo cp backup-config.conf /etc/git-backup/

# Install systemd units
sudo cp git-backup.service /etc/systemd/system/
sudo cp git-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
```

## Configuration

Edit `/etc/git-backup/backup-config.conf`:

```bash
# Source directory containing git repositories
SOURCE_PATH="/srv/git/repos"

# Destination directory for backups
BACKUP_PATH="/mnt/backups/git"

# Number of backup copies to keep
KEEP_COPIES=7

# Number of recent backups to keep uncompressed (for fast restoration)
# Older backups will be compressed to .tar.gz to save space
# Set to 0 to disable compression
KEEP_UNCOMPRESSED=2

# Backup interval (documentation only, actual schedule via timer)
BACKUP_INTERVAL_HOURS=24
```

### Configuration Options

| Option | Description | Example |
|--------|-------------|---------|
| `SOURCE_PATH` | Directory containing git repositories to backup | `/srv/git` |
| `BACKUP_PATH` | Where backup directories will be created | `/mnt/backups/git` |
| `KEEP_COPIES` | Number of recent backups to keep (older ones deleted) | `7` (keep 1 week) |
| `KEEP_UNCOMPRESSED` | Number of recent backups to keep uncompressed (older ones compressed to .tar.gz) | `2` (keep 2 newest uncompressed) |
| `BACKUP_INTERVAL_HOURS` | Documentation of intended schedule | `24` (daily) |

## Usage

### Enable Automatic Backups

```bash
# Enable and start the timer
sudo systemctl enable --now git-backup.timer

# Check timer status
sudo systemctl list-timers git-backup.timer
```

### Manual Backup

```bash
# Run backup immediately
sudo systemctl start git-backup.service

# Check if it's running
sudo systemctl status git-backup.service
```

### View Logs

```bash
# Follow live logs
sudo journalctl -u git-backup.service -f

# View last 50 lines
sudo journalctl -u git-backup.service -n 50

# View logs from today
sudo journalctl -u git-backup.service --since today

# View logs from specific date
sudo journalctl -u git-backup.service --since "2024-12-01" --until "2024-12-18"

# Show only errors
sudo journalctl -u git-backup.service -p err
```

### Check Backup Status

```bash
# Check service status
sudo systemctl status git-backup.service

# Check timer status (when next backup will run)
sudo systemctl list-timers git-backup.timer

# Check if timer is enabled
sudo systemctl is-enabled git-backup.timer
```

## Customizing the Schedule

Edit `/etc/systemd/system/git-backup.timer`:

### Default (Daily at Midnight)
```ini
[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=30min
```

### Every 6 Hours
```ini
[Timer]
OnCalendar=*-*-* 00,06,12,18:00:00
Persistent=true
RandomizedDelaySec=30min
```

### Twice Daily (2 AM and 2 PM)
```ini
[Timer]
OnCalendar=*-*-* 02,14:00:00
Persistent=true
RandomizedDelaySec=30min
```

### Weekly (Sunday at 3:00 AM)
```ini
[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true
RandomizedDelaySec=30min
```

### Specific Days (Monday, Wednesday, Friday at 1 AM)
```ini
[Timer]
OnCalendar=Mon,Wed,Fri *-*-* 01:00:00
Persistent=true
RandomizedDelaySec=30min
```

After editing the timer:
```bash
sudo systemctl daemon-reload
sudo systemctl restart git-backup.timer
```

## Backup Structure

Backups are stored with timestamps. Recent backups remain as directories, older ones are compressed:

```
/mnt/backups/git/
├── backup_20241218_020000/          (newest - uncompressed directory)
├── backup_20241217_020000/          (recent - uncompressed directory)
├── backup_20241216_020000.tar.gz    (older - compressed)
├── backup_20241215_020000.tar.gz    (older - compressed)
└── ...
```

## How Rotation Works

1. Script creates new backup with timestamp: `backup_YYYYMMDD_HHMMSS`
2. After backup completes, script counts existing backups
3. If count > `KEEP_COPIES`, oldest backups are deleted
4. Only the N most recent backups are kept

**Example with KEEP_COPIES=3:**
- Before: 3 backups exist
- Run backup → creates 4th backup
- Rotation → deletes oldest, keeps 3 newest

## How Compression Works

Old backups are automatically compressed to save disk space while keeping recent backups as directories for fast restoration.

**Process:**
1. After successful backup and before rotation
2. Script identifies backups older than the N most recent (where N = `KEEP_UNCOMPRESSED`)
3. Compresses them to `.tar.gz` using gzip
4. Removes original directory after successful compression
5. Rotation then considers both compressed and uncompressed backups

**Example with KEEP_UNCOMPRESSED=2, KEEP_COPIES=7:**
- Latest 2 backups: uncompressed directories (fast access)
- Next 5 oldest: compressed `.tar.gz` files (space efficient)
- Anything older: deleted

**Disable compression:** Set `KEEP_UNCOMPRESSED=0` in config file

## Monitoring

### Check Recent Backups

```bash
ls -lh /mnt/backups/git/
```

### View Last Backup Run

```bash
sudo journalctl -u git-backup.service -n 100 --no-pager
```

### Check Backup Size

```bash
du -sh /mnt/backups/git/backup_*
```

### List All Backups

```bash
find /mnt/backups/git -maxdepth 1 -type d -name "backup_*" | sort
```

### Service Management Commands

```bash
# Start backup immediately
sudo systemctl start git-backup.service

# Stop a running backup
sudo systemctl stop git-backup.service

# Restart the timer
sudo systemctl restart git-backup.timer

# Disable automatic backups (but don't stop current)
sudo systemctl disable git-backup.timer

# Enable automatic backups
sudo systemctl enable git-backup.timer

# Check service status
sudo systemctl status git-backup.service

# Check timer status
sudo systemctl status git-backup.timer
```

## Restoring from Backup

### Restore from Uncompressed Backup

```bash
# Restore specific repository
rsync -av /mnt/backups/git/backup_20241218_020000/myrepo.git/ /srv/git/myrepo.git/

# Restore all repositories
rsync -av /mnt/backups/git/backup_20241218_020000/ /srv/git/
```

### Restore from Compressed Backup

```bash
# Extract first, then restore
cd /mnt/backups/git
tar -xzf backup_20241218_020000.tar.gz
rsync -av backup_20241218_020000/ /srv/git/

# Or extract and restore specific repository
tar -xzf /mnt/backups/git/backup_20241218_020000.tar.gz -C /tmp
rsync -av /tmp/backup_20241218_020000/myrepo.git/ /srv/git/myrepo.git/
rm -rf /tmp/backup_20241218_020000
```

## Troubleshooting

### Check Service Logs for Errors

```bash
sudo journalctl -u git-backup.service -p err --since today
```

### Test Backup Manually

```bash
# Run directly (not via systemd)
sudo /usr/local/bin/git-backup
```

### Permission Issues

```bash
# Ensure backup script can read source
sudo chmod +r /path/to/repos

# Ensure backup destination is writable
sudo chown root:root /mnt/backups/git
```

### Timer Not Running

```bash
# Check if timer is active
sudo systemctl is-active git-backup.timer

# Check if timer is enabled
sudo systemctl is-enabled git-backup.timer

# Enable and start if needed
sudo systemctl enable --now git-backup.timer
```

### Disk Space

```bash
# Check available space
df -h /mnt/backups/git

# See backup sizes
du -sh /mnt/backups/git/backup_*

# Consider reducing KEEP_COPIES if space is tight
```

### View Systemd Timer Details

```bash
# List all timers
sudo systemctl list-timers --all

# Show timer details
sudo systemctl show git-backup.timer
```

### Verify Backup Integrity

```bash
# Compare file counts
find /srv/git -type f | wc -l
find /mnt/backups/git/backup_20241218_020000 -type f | wc -l

# Check specific git repository
cd /mnt/backups/git/backup_20241218_020000/myrepo.git
git fsck
```

## Advanced Options

### Exclude Certain Directories

Edit `/usr/local/bin/git-backup` and modify rsync command:

```bash
rsync -avz --delete \
    --exclude='*.tmp' \
    --exclude='cache/' \
    --stats \
    "$SOURCE_PATH/" \
    "$CURRENT_BACKUP/"
```

Then reload:
```bash
sudo systemctl daemon-reload
```

### Email Notifications on Failure

Create `/etc/systemd/system/git-backup-notify@.service`:

```ini
[Unit]
Description=Backup notification for %i

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'echo "Backup %i failed" | mail -s "Backup Alert" admin@example.com'
```

Edit `/etc/systemd/system/git-backup.service` and add:

```ini
[Unit]
OnFailure=git-backup-notify@%n.service
```

### Remote Backup

Update `BACKUP_PATH` in config to use SSH:

```bash
BACKUP_PATH="user@backup-server:/backups/git"
```

Ensure SSH key authentication is set up for passwordless access.

### Priority and Resource Limits

Edit `/etc/systemd/system/git-backup.service`:

```ini
[Service]
# Run with lower priority
Nice=19
IOSchedulingClass=idle

# Limit CPU usage
CPUQuota=50%

# Memory limit
MemoryMax=1G
```

## Security Considerations

- Service runs as root by default (needed for file access)
- Uses `NoNewPrivileges=yes` and `PrivateTmp=yes` for security hardening
- Consider running as dedicated backup user with appropriate permissions
- Secure backup destination (proper filesystem permissions)
- Consider encrypting backup destination
- For remote backups, use SSH key authentication
- Regularly test restore procedures

## Understanding systemd Benefits

### Why systemd over cron?

1. **Better logging**: All output goes to journald (structured logging)
2. **Status monitoring**: `systemctl status` shows current state
3. **Dependency handling**: Service can depend on network, mounts, etc.
4. **Failure recovery**: Built-in retry on failure
5. **Persistent timers**: Missed backups run on next boot
6. **Resource control**: Easy CPU/memory limits
7. **Notification**: Built-in failure notifications

### Persistent Timers

The `Persistent=true` option means:
- If server was off when backup should have run
- Backup runs immediately after boot
- Ensures you don't miss backups due to downtime

## Uninstallation

```bash
# Stop and disable timer
sudo systemctl disable --now git-backup.timer

# Remove systemd units
sudo rm /etc/systemd/system/git-backup.{service,timer}
sudo systemctl daemon-reload

# Remove script and config
sudo rm /usr/local/bin/git-backup
sudo rm -rf /etc/git-backup

# Optionally remove backups
# sudo rm -rf /mnt/backups/git
```

## License

Free to use and modify for your needs.
