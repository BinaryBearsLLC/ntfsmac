package main

import (
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fixture(t *testing.T) (*Config, string) {
	t.Helper()
	prefix, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	cfg := &Config{PrefixDir: prefix, SourceReference: offlineRuntimeReference, RootfsPath: filepath.Join(prefix, "rootfs")}
	root := filepath.Join(prefix, "lib", "ntfsmac-runtime")
	files := map[string]string{"entrypoint.sh": "#!/bin/sh\necho local\n", "apks/example-1-r0.apk": "test apk", "oci/index.json": "{}"}
	manifest := ""
	for _, name := range []string{"entrypoint.sh", "apks/example-1-r0.apk", "oci/index.json"} {
		p := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(files[name]), 0644); err != nil {
			t.Fatal(err)
		}
		manifest += fmt.Sprintf("%x  %s\n", sha256.Sum256([]byte(files[name])), name)
	}
	previous := offlineRuntimeManifest
	offlineRuntimeManifest = manifest
	t.Cleanup(func() { offlineRuntimeManifest = previous })
	if err := os.WriteFile(filepath.Join(root, "SHA256SUMS"), []byte(manifest), 0644); err != nil {
		t.Fatal(err)
	}
	return cfg, root
}

func TestVerifyOfflinePayload(t *testing.T) {
	cfg, _ := fixture(t)
	if err := verifyOfflineRuntime(cfg); err != nil {
		t.Fatal(err)
	}
}

func TestRejectOfflinePayloadDamage(t *testing.T) {
	for _, kind := range []string{"missing-root", "missing-file", "tampered-file", "edited-manifest", "missing-manifest", "extra-file", "symlink-file", "symlink-directory", "symlink-root", "symlink-prefix", "wrong-reference"} {
		t.Run(kind, func(t *testing.T) {
			cfg, root := fixture(t)
			entry := filepath.Join(root, "entrypoint.sh")
			switch kind {
			case "missing-root":
				os.RemoveAll(root)
			case "missing-file":
				os.Remove(entry)
			case "tampered-file":
				os.WriteFile(entry, []byte("tampered"), 0644)
			case "edited-manifest":
				os.WriteFile(filepath.Join(root, "SHA256SUMS"), []byte("replacement"), 0644)
			case "missing-manifest":
				os.Remove(filepath.Join(root, "SHA256SUMS"))
			case "extra-file":
				os.WriteFile(filepath.Join(root, "apks", "extra.apk"), []byte("extra"), 0644)
			case "symlink-file":
				os.Rename(entry, filepath.Join(cfg.PrefixDir, "outside"))
				os.Symlink(filepath.Join(cfg.PrefixDir, "outside"), entry)
			case "symlink-directory":
				os.Rename(filepath.Join(root, "apks"), filepath.Join(cfg.PrefixDir, "outside"))
				os.Symlink(filepath.Join(cfg.PrefixDir, "outside"), filepath.Join(root, "apks"))
			case "symlink-root":
				os.Rename(root, root+"-real")
				os.Symlink(root+"-real", root)
			case "symlink-prefix":
				os.Symlink(cfg.PrefixDir, cfg.PrefixDir+"-link")
				link := cfg.PrefixDir + "-link"
				t.Cleanup(func() { os.Remove(link) })
				cfg.PrefixDir += "-link"
			case "wrong-reference":
				cfg.SourceReference = "docker.io/library/alpine:latest"
			}
			if err := verifyOfflineRuntime(cfg); err == nil || !strings.Contains(err.Error(), "reinstall") {
				t.Fatalf("expected reinstall error for %s, got %v", kind, err)
			}
		})
	}
}

func TestRejectUnsafeEmbeddedManifest(t *testing.T) {
	for _, name := range []string{"..", "../outside", "/etc/passwd", "apks/../../outside", "apks//file", "apks/./file", "apks/../file", "apks\\file", ".", "apks/file\r", "SHA256SUMS"} {
		t.Run(name, func(t *testing.T) {
			fixture(t)
			offlineRuntimeManifest = fmt.Sprintf("%064x  %s\n", 1, name)
			if _, err := offlineManifestEntries(); err == nil {
				t.Fatal("accepted unsafe manifest")
			}
		})
	}
	for _, kind := range []string{"duplicate", "invalid-hash", "empty"} {
		t.Run(kind, func(t *testing.T) {
			fixture(t)
			switch kind {
			case "duplicate":
				offlineRuntimeManifest += offlineRuntimeManifest
			case "invalid-hash":
				offlineRuntimeManifest = strings.Replace(offlineRuntimeManifest, offlineRuntimeManifest[:64], strings.Repeat("z", 64), 1)
			case "empty":
				offlineRuntimeManifest = ""
			}
			if _, err := offlineManifestEntries(); err == nil {
				t.Fatal("accepted malformed manifest")
			}
		})
	}
}

func TestCopyOfflineFiles(t *testing.T) {
	cfg, root := fixture(t)
	if err := stageOfflineAPKs(cfg); err != nil {
		t.Fatal(err)
	}
	if err := copyOfflineEntrypoint(cfg); err != nil {
		t.Fatal(err)
	}
	for _, pair := range [][2]string{{"apks/example-1-r0.apk", "var/cache/ntfsmac-apks/example-1-r0.apk"}, {"entrypoint.sh", "usr/local/bin/entrypoint.sh"}} {
		src, _ := os.ReadFile(filepath.Join(root, pair[0]))
		dst, err := os.ReadFile(filepath.Join(cfg.RootfsPath, pair[1]))
		if err != nil || string(src) != string(dst) {
			t.Fatalf("copy differs: %v", err)
		}
	}
	info, _ := os.Stat(filepath.Join(cfg.RootfsPath, "usr/local/bin/entrypoint.sh"))
	if info.Mode().Perm() != 0755 {
		t.Fatalf("entrypoint mode: %v", info.Mode())
	}
	os.WriteFile(filepath.Join(root, "entrypoint.sh"), []byte("tampered"), 0644)
	if err := copyOfflineEntrypoint(cfg); err == nil {
		t.Fatal("copied tampered entrypoint")
	}
}

func TestOfflineCopyRejectsDestinationSymlink(t *testing.T) {
	cfg, _ := fixture(t)
	outside := filepath.Join(cfg.PrefixDir, "outside")
	os.MkdirAll(outside, 0755)
	os.MkdirAll(cfg.RootfsPath, 0755)
	os.Symlink(outside, filepath.Join(cfg.RootfsPath, "var"))
	if err := stageOfflineAPKs(cfg); err == nil {
		t.Fatal("followed destination symlink")
	}
}

func TestOfflineCopiesRejectChangedAPKAndDestinationFileSymlink(t *testing.T) {
	cfg, root := fixture(t)
	os.WriteFile(filepath.Join(root, "apks/example-1-r0.apk"), []byte("changed"), 0644)
	if err := stageOfflineAPKs(cfg); err == nil {
		t.Fatal("staged changed APK")
	}
	target := filepath.Join(cfg.PrefixDir, "target")
	os.WriteFile(target, []byte("preserve"), 0600)
	dest := filepath.Join(cfg.RootfsPath, "usr/local/bin/entrypoint.sh")
	os.MkdirAll(filepath.Dir(dest), 0755)
	os.Symlink(target, dest)
	if err := copyOfflineEntrypoint(cfg); err == nil {
		t.Fatal("followed destination file symlink")
	}
	data, _ := os.ReadFile(target)
	if string(data) != "preserve" {
		t.Fatal("modified symlink target")
	}
}

func TestVerifyOfflinePayloadAtIndependentDirectory(t *testing.T) {
	_, root := fixture(t)
	moved := filepath.Join(filepath.Dir(root), "standalone-runtime")
	if err := os.Rename(root, moved); err != nil {
		t.Fatal(err)
	}
	if err := verifyOfflineRuntimeAt(moved); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(moved, "entrypoint.sh"), []byte("tampered"), 0644)
	if err := verifyOfflineRuntimeAt(moved); err == nil {
		t.Fatal("accepted corrupt standalone payload")
	}
}
