package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	SourcePath       string
	BackupPath       string
	KeepCopies       int
	KeepUncompressed int
}

func main() {
	// Default config file location
	configFile := "/etc/git-backup/backup-config.conf"
	if len(os.Args) > 1 {
		configFile = os.Args[1]
	}

	// Check if config file exists
	if _, err := os.Stat(configFile); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "Error: Configuration file not found: %s\n", configFile)
		fmt.Fprintf(os.Stderr, "Usage: %s [config-file]\n", os.Args[0])
		os.Exit(1)
	}

	// Load configuration
	config, err := loadConfig(configFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading config: %v\n", err)
		os.Exit(1)
	}

	// Validate required variables
	if config.SourcePath == "" || config.BackupPath == "" || config.KeepCopies == 0 {
		fmt.Fprintln(os.Stderr, "Error: Missing required configuration variables")
		fmt.Fprintln(os.Stderr, "Required: SOURCE_PATH, BACKUP_PATH, KEEP_COPIES")
		os.Exit(1)
	}

	// Check if source directory exists
	if _, err := os.Stat(config.SourcePath); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "Error: Source directory does not exist: %s\n", config.SourcePath)
		os.Exit(1)
	}

	// Create backup directory if it doesn't exist
	if err := os.MkdirAll(config.BackupPath, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating backup directory: %v\n", err)
		os.Exit(1)
	}

	// Generate timestamp for this backup
	timestamp := time.Now().Format("20060102_150405")
	backupName := fmt.Sprintf("backup_%s", timestamp)
	currentBackup := filepath.Join(config.BackupPath, backupName)

	fmt.Println("==========================================")
	fmt.Println("Git Repository Backup")
	fmt.Println("==========================================")
	fmt.Printf("Started at: %s\n", time.Now().Format("2006-01-02 15:04:05"))
	fmt.Printf("Source: %s\n", config.SourcePath)
	fmt.Printf("Destination: %s\n", currentBackup)
	fmt.Printf("Keeping: %d copies\n", config.KeepCopies)
	fmt.Println()

	// Perform the backup using rsync
	fmt.Println("Running rsync...")
	rsyncCmd := fmt.Sprintf("rsync -avz --delete --stats %s/ %s/", config.SourcePath, currentBackup)
	fmt.Println(rsyncCmd)

	cmd := exec.Command("rsync", "-avz", "--delete", "--stats",
		config.SourcePath+"/", currentBackup+"/")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	rsyncErr := cmd.Run()
	rsyncExitCode := 0
	if rsyncErr != nil {
		if exitErr, ok := rsyncErr.(*exec.ExitError); ok {
			rsyncExitCode = exitErr.ExitCode()
		} else {
			rsyncExitCode = 1
		}
	}

	fmt.Println()
	if rsyncExitCode == 0 {
		fmt.Println("✓ Backup completed successfully")
	} else {
		fmt.Printf("✗ Backup failed with exit code: %d\n", rsyncExitCode)
		os.Exit(rsyncExitCode)
	}

	// Compress old backups (if enabled)
	if config.KeepUncompressed > 0 {
		if err := compressOldBackups(config); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: Compression error: %v\n", err)
		}
	} else {
		fmt.Println()
		fmt.Println("Compression disabled (KEEP_UNCOMPRESSED not set or is 0)")
	}

	// Rotate old backups
	if err := rotateBackups(config); err != nil {
		fmt.Fprintf(os.Stderr, "Error rotating backups: %v\n", err)
		os.Exit(1)
	}

	fmt.Println()
	fmt.Println("==========================================")
	fmt.Printf("Backup completed at: %s\n", time.Now().Format("2006-01-02 15:04:05"))
	fmt.Println("==========================================")
}

func loadConfig(filename string) (*Config, error) {
	file, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	config := &Config{}
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip comments and empty lines
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Parse KEY=VALUE
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.Trim(strings.TrimSpace(parts[1]), "\"")

		switch key {
		case "SOURCE_PATH":
			config.SourcePath = value
		case "BACKUP_PATH":
			config.BackupPath = value
		case "KEEP_COPIES":
			if v, err := strconv.Atoi(value); err == nil {
				config.KeepCopies = v
			}
		case "KEEP_UNCOMPRESSED":
			if v, err := strconv.Atoi(value); err == nil {
				config.KeepUncompressed = v
			}
		}
	}

	return config, scanner.Err()
}

type backupEntry struct {
	path    string
	modTime time.Time
	isDir   bool
}

func compressOldBackups(config *Config) error {
	fmt.Println()
	fmt.Printf("Compressing old backups (keeping %d most recent uncompressed)...\n", config.KeepUncompressed)

	// Get list of uncompressed backup directories
	entries, err := os.ReadDir(config.BackupPath)
	if err != nil {
		return err
	}

	var uncompressed []backupEntry
	for _, entry := range entries {
		if entry.IsDir() && strings.HasPrefix(entry.Name(), "backup_") {
			info, err := entry.Info()
			if err != nil {
				continue
			}
			uncompressed = append(uncompressed, backupEntry{
				path:    entry.Name(),
				modTime: info.ModTime(),
				isDir:   true,
			})
		}
	}

	// Sort by modification time (newest first)
	sort.Slice(uncompressed, func(i, j int) bool {
		return uncompressed[i].modTime.After(uncompressed[j].modTime)
	})

	fmt.Printf("Found %d uncompressed backup(s)\n", len(uncompressed))

	if len(uncompressed) > config.KeepUncompressed {
		toCompress := len(uncompressed) - config.KeepUncompressed
		fmt.Printf("Compressing %d old backup(s)...\n", toCompress)

		// Compress backups older than the N most recent
		for i := config.KeepUncompressed; i < len(uncompressed); i++ {
			backupDir := uncompressed[i].path
			archiveName := backupDir + ".tar.gz"
			archivePath := filepath.Join(config.BackupPath, archiveName)

			// Skip if already compressed
			if _, err := os.Stat(archivePath); err == nil {
				fmt.Printf("  Skipping %s (archive already exists)\n", backupDir)
				continue
			}

			fmt.Printf("  Compressing: %s -> %s\n", backupDir, archiveName)

			// Run tar command
			cmd := exec.Command("tar", "-czf", archiveName, "-C", config.BackupPath, backupDir)
			cmd.Dir = config.BackupPath
			if output, err := cmd.CombinedOutput(); err != nil {
				fmt.Printf("  Warning: Compression failed for %s: %v\n", backupDir, err)
				if len(output) > 0 {
					fmt.Printf("  %s\n", string(output))
				}
				continue
			}

			// Remove uncompressed directory
			fmt.Printf("  Removing uncompressed: %s\n", backupDir)
			backupPath := filepath.Join(config.BackupPath, backupDir)
			if err := os.RemoveAll(backupPath); err != nil {
				fmt.Printf("  Warning: Failed to remove %s: %v\n", backupDir, err)
			}
		}
	} else {
		fmt.Printf("No compression needed (only %d uncompressed backup(s))\n", len(uncompressed))
	}

	return nil
}

func rotateBackups(config *Config) error {
	fmt.Println()
	fmt.Printf("Rotating old backups (keeping %d most recent)...\n", config.KeepCopies)

	// Get list of all backups (directories and archives)
	entries, err := os.ReadDir(config.BackupPath)
	if err != nil {
		return err
	}

	var backups []backupEntry
	for _, entry := range entries {
		name := entry.Name()
		isBackupDir := entry.IsDir() && strings.HasPrefix(name, "backup_")
		isBackupArchive := !entry.IsDir() && strings.HasPrefix(name, "backup_") && strings.HasSuffix(name, ".tar.gz")

		if isBackupDir || isBackupArchive {
			info, err := entry.Info()
			if err != nil {
				continue
			}
			backups = append(backups, backupEntry{
				path:    name,
				modTime: info.ModTime(),
				isDir:   entry.IsDir(),
			})
		}
	}

	fmt.Printf("Total backups found: %d (compressed + uncompressed)\n", len(backups))

	if len(backups) > config.KeepCopies {
		toDelete := len(backups) - config.KeepCopies
		fmt.Printf("Removing %d old backup(s)...\n", toDelete)

		// Sort by modification time (oldest first)
		sort.Slice(backups, func(i, j int) bool {
			return backups[i].modTime.Before(backups[j].modTime)
		})

		// Delete oldest backups
		// for i := 0; i < toDelete; i++ {
		for i := range toDelete {
			backup := backups[i]
			fmt.Printf("  Deleting: %s\n", backup.path)
			backupPath := filepath.Join(config.BackupPath, backup.path)

			var err error
			if backup.isDir {
				err = os.RemoveAll(backupPath)
			} else {
				err = os.Remove(backupPath)
			}

			if err != nil {
				fmt.Printf("  Warning: Failed to delete %s: %v\n", backup.path, err)
			}
		}
	} else {
		fmt.Printf("No rotation needed (only %d backup(s) exist)\n", len(backups))
	}

	return nil
}
