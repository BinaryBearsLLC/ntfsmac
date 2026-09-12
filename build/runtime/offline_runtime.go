package main

import (
	"crypto/sha256"
	_ "embed"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// The build verifies this manifest against sources.lock before embedding it.
// An installed SHA256SUMS is checked for consistency, never used as a trust anchor.
//
//go:embed offline-runtime.sha256
var offlineRuntimeManifest string

func offlinePayloadError(err error) error {
	return fmt.Errorf("ntfsmac offline runtime is missing or corrupt; reinstall ntfsmac: %w", err)
}

func offlinePayloadRoot(cfg *Config) string {
	return filepath.Join(cfg.PrefixDir, "lib", "ntfsmac-runtime")
}

func offlineManifestEntries() (map[string]string, error) {
	entries := make(map[string]string)
	if offlineRuntimeManifest == "" || !strings.HasSuffix(offlineRuntimeManifest, "\n") {
		return nil, fmt.Errorf("invalid embedded manifest")
	}
	for _, line := range strings.Split(strings.TrimSuffix(offlineRuntimeManifest, "\n"), "\n") {
		if len(line) < 67 || line[64:66] != "  " {
			return nil, fmt.Errorf("invalid manifest record")
		}
		sum, name := line[:64], line[66:]
		digest, err := hex.DecodeString(sum)
		if err != nil || len(digest) != sha256.Size || strings.ToLower(sum) != sum {
			return nil, fmt.Errorf("invalid checksum for %q", name)
		}
		if name == "." || name == ".." || name == "SHA256SUMS" || path.IsAbs(name) || path.Clean(name) != name || strings.HasPrefix(name, "../") {
			return nil, fmt.Errorf("unsafe manifest path %q", name)
		}
		for _, c := range name {
			if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || strings.ContainsRune("/._-+", c)) {
				return nil, fmt.Errorf("unsafe manifest path %q", name)
			}
		}
		if _, exists := entries[name]; exists {
			return nil, fmt.Errorf("duplicate manifest path %q", name)
		}
		entries[name] = sum
	}
	return entries, nil
}

// Check every component, including ancestors of the installation prefix. In
// particular, neither a payload directory nor a payload file may be a symlink.
func offlineRegularPath(filename string, directory bool) error {
	absolute, err := filepath.Abs(filename)
	if err != nil {
		return err
	}
	current := string(filepath.Separator)
	parts := strings.Split(strings.TrimPrefix(absolute, current), string(filepath.Separator))
	for i, part := range parts {
		if part == "" {
			continue
		}
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if err != nil {
			return err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("symlink in runtime path %s", current)
		}
		if i < len(parts)-1 || directory {
			if !info.IsDir() {
				return fmt.Errorf("not a directory: %s", current)
			}
		} else if !info.Mode().IsRegular() {
			return fmt.Errorf("not a regular file: %s", current)
		}
	}
	return nil
}

func verifyOfflineRuntime(cfg *Config) error {
	if cfg.SourceReference != offlineRuntimeReference {
		return offlinePayloadError(fmt.Errorf("unsupported runtime reference %q", cfg.SourceReference))
	}
	return verifyOfflineRuntimeAt(offlinePayloadRoot(cfg))
}

// Standalone verification is also used by the installer before activation. It
// does not derive user paths, create a runtime cache, or initialize a VM.
func verifyOfflineRuntimeAt(root string) error {
	entries, err := offlineManifestEntries()
	if err != nil {
		return offlinePayloadError(err)
	}
	if err := offlineRegularPath(root, true); err != nil {
		return offlinePayloadError(err)
	}
	if err := offlineRegularPath(filepath.Join(root, "SHA256SUMS"), false); err != nil {
		return offlinePayloadError(err)
	}
	installed, err := os.ReadFile(filepath.Join(root, "SHA256SUMS"))
	if err != nil {
		return offlinePayloadError(err)
	}
	if string(installed) != offlineRuntimeManifest {
		return offlinePayloadError(fmt.Errorf("installed manifest differs from embedded manifest"))
	}
	for name, sum := range entries {
		if _, err := readOfflineFile(root, name, sum); err != nil {
			return offlinePayloadError(err)
		}
	}
	// Reject unlisted files as well: wildcard APK installation must see exactly
	// the verified closure, including when an installation was incompletely replaced.
	err = filepath.WalkDir(root, func(filename string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("symlink in payload: %s", filename)
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(root, filename)
		if err != nil {
			return err
		}
		if relative == "SHA256SUMS" {
			return nil
		}
		if _, ok := entries[filepath.ToSlash(relative)]; !ok {
			return fmt.Errorf("unlisted payload file: %s", relative)
		}
		return nil
	})
	if err != nil {
		return offlinePayloadError(err)
	}
	return nil
}

func readOfflineFile(root, name, sum string) ([]byte, error) {
	filename := filepath.Join(root, filepath.FromSlash(name))
	if err := offlineRegularPath(filename, false); err != nil {
		return nil, err
	}
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	if fmt.Sprintf("%x", sha256.Sum256(data)) != sum {
		return nil, fmt.Errorf("checksum mismatch: %s", name)
	}
	return data, nil
}

func copyOfflineFile(cfg *Config, name, destination string, mode fs.FileMode) error {
	entries, err := offlineManifestEntries()
	if err != nil {
		return offlinePayloadError(err)
	}
	sum, ok := entries[name]
	if !ok {
		return offlinePayloadError(fmt.Errorf("unlisted source %s", name))
	}
	data, err := readOfflineFile(offlinePayloadRoot(cfg), name, sum)
	if err != nil {
		return offlinePayloadError(err)
	}
	// Build missing directories one component at a time so MkdirAll never follows
	// a pre-existing symlink from the unpacked guest into the host filesystem.
	parent, err := filepath.Abs(filepath.Dir(destination))
	if err != nil {
		return err
	}
	current := string(filepath.Separator)
	for _, part := range strings.Split(strings.TrimPrefix(parent, current), string(filepath.Separator)) {
		if part == "" {
			continue
		}
		current = filepath.Join(current, part)
		if err := os.Mkdir(current, 0755); err != nil && !os.IsExist(err) {
			return err
		}
		if err := offlineRegularPath(current, true); err != nil {
			return err
		}
	}
	if _, err := os.Lstat(destination); err == nil {
		if err := offlineRegularPath(destination, false); err != nil {
			return err
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	// Atomic replacement avoids following an existing destination hard link.
	temporary, err := os.CreateTemp(parent, ".ntfsmac-offline-")
	if err != nil {
		return err
	}
	defer os.Remove(temporary.Name())
	if _, err = temporary.Write(data); err != nil {
		temporary.Close()
		return err
	}
	if err = temporary.Chmod(mode); err != nil {
		temporary.Close()
		return err
	}
	if err = temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporary.Name(), destination)
}

func copyOfflineEntrypoint(cfg *Config) error {
	return copyOfflineFile(cfg, "entrypoint.sh", filepath.Join(cfg.RootfsPath, "usr/local/bin/entrypoint.sh"), 0755)
}

func stageOfflineAPKs(cfg *Config) error {
	entries, err := offlineManifestEntries()
	if err != nil {
		return offlinePayloadError(err)
	}
	count := 0
	for name := range entries {
		if !strings.HasPrefix(name, "apks/") {
			continue
		}
		if path.Dir(name) != "apks" || !strings.HasSuffix(name, ".apk") {
			return offlinePayloadError(fmt.Errorf("invalid APK path %s", name))
		}
		if err := copyOfflineFile(cfg, name, filepath.Join(cfg.RootfsPath, "var/cache/ntfsmac-apks", path.Base(name)), 0644); err != nil {
			return err
		}
		count++
	}
	if count == 0 {
		return offlinePayloadError(fmt.Errorf("no APKs in embedded manifest"))
	}
	return nil
}
