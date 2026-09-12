package main

import (
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// This file is run only with the patched real initializer (see Bats harness).
func TestOfflineImportAndUnpack(t *testing.T) {
	prefix := os.Getenv("NTFSMAC_OFFLINE_TEST_PREFIX")
	if prefix == "" {
		t.Fatal("missing test prefix")
	}
	prefix, err := filepath.EvalSymlinks(prefix)
	if err != nil {
		t.Fatal(err)
	}
	home, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	cfg := defaultConfig(home, filepath.Join(prefix, "libexec"), offlineRuntimeReference, "offline-test")
	if err := downloadImage(&cfg); err != nil {
		t.Fatal(err)
	}
	if err := unpackImage(&cfg); err != nil {
		t.Fatal(err)
	}
	if err := stageOfflineAPKs(&cfg); err != nil {
		t.Fatal(err)
	}
	if err := copyOfflineEntrypoint(&cfg); err != nil {
		t.Fatal(err)
	}
	if len(getDefaultPackages()) != 54 {
		t.Fatal("package configuration differs from locked closure")
	}
	if err := writeSetupScript(&cfg, ""); err != nil {
		t.Fatal(err)
	}
	files, err := filepath.Glob(filepath.Join(cfg.RootfsPath, "var/cache/ntfsmac-apks/*.apk"))
	if err != nil || len(files) != 54 {
		t.Fatalf("APK count %d, error %v", len(files), err)
	}
	data, err := os.ReadFile(filepath.Join(cfg.RootfsPath, "lib/apk/db/installed"))
	if err != nil || !strings.Contains(string(data), "P:alpine-baselayout") {
		t.Fatalf("missing unpacked package database: %v", err)
	}
	setup, err := os.ReadFile(filepath.Join(cfg.RootfsPath, "usr/local/bin/vm-setup.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(setup), "wget") || !strings.Contains(string(setup), "apk --no-network --no-cache add") || !strings.Contains(string(setup), "sha256sum -c -") {
		t.Fatal("setup is not locked and offline")
	}
}

func TestOfflineInitRejectsBeforeCacheRemoval(t *testing.T) {
	home, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	cfg := defaultConfig(home, filepath.Join(home, "missing-prefix/libexec"), offlineRuntimeReference, "keep-cache")
	os.MkdirAll(cfg.ImageBasePath, 0755)
	sentinel := filepath.Join(cfg.ImageBasePath, "sentinel")
	os.WriteFile(sentinel, []byte("preserved"), 0600)
	if err := initRootfs(&cfg, "", ""); err == nil || !strings.Contains(err.Error(), "reinstall") {
		t.Fatalf("expected reinstall error: %v", err)
	}
	if data, err := os.ReadFile(sentinel); err != nil || string(data) != "preserved" {
		t.Fatal("cache modified before verification")
	}
}

func TestSandboxDeniesNetworking(t *testing.T) {
	conn, err := net.DialTimeout("tcp", "127.0.0.1:9", time.Second)
	if conn != nil {
		conn.Close()
	}
	if err == nil || !strings.Contains(err.Error(), "operation not permitted") {
		t.Fatalf("network denial was not enforced: %v", err)
	}
}

func TestOfflineTamperingPreservesCache(t *testing.T) {
	prefix, err := filepath.EvalSymlinks(os.Getenv("NTFSMAC_OFFLINE_TEST_PREFIX"))
	if err != nil {
		t.Fatal(err)
	}
	home, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	cfg := defaultConfig(home, filepath.Join(prefix, "libexec"), offlineRuntimeReference, "keep-tampered-cache")
	os.MkdirAll(cfg.ImageBasePath, 0755)
	sentinel := filepath.Join(cfg.ImageBasePath, "sentinel")
	os.WriteFile(sentinel, []byte("preserved"), 0600)
	entrypoint := filepath.Join(prefix, "lib/ntfsmac-runtime/entrypoint.sh")
	original, err := os.ReadFile(entrypoint)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.WriteFile(entrypoint, original, 0644) })
	if err := os.WriteFile(entrypoint, []byte("tampered"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := initRootfs(&cfg, "", ""); err == nil || !strings.Contains(err.Error(), "checksum mismatch") {
		t.Fatalf("expected checksum error: %v", err)
	}
	if data, err := os.ReadFile(sentinel); err != nil || string(data) != "preserved" {
		t.Fatal("cache modified before verification")
	}
}

func TestOfflineVerificationCLI(t *testing.T) {
	binary := os.Getenv("NTFSMAC_OFFLINE_TEST_BINARY")
	prefix, err := filepath.EvalSymlinks(os.Getenv("NTFSMAC_OFFLINE_TEST_PREFIX"))
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, path string
		valid      bool
	}{
		{"valid", filepath.Join(prefix, "lib/ntfsmac-runtime"), true},
		{"missing", filepath.Join(prefix, "missing"), false},
		{"empty", "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			home := filepath.Join(t.TempDir(), "nonexistent-home")
			command := exec.Command(binary, "-verify-offline-runtime", tc.path)
			command.Env = append(os.Environ(), "HOME="+home)
			output, err := command.CombinedOutput()
			if (err == nil) != tc.valid {
				t.Fatalf("verification success=%v, expected=%v: %s", err == nil, tc.valid, output)
			}
			if tc.valid && !strings.Contains(string(output), "offline runtime payload verified") {
				t.Fatalf("missing success: %s", output)
			}
			if strings.Contains(string(output), "User store:") || strings.Contains(string(output), "VM must not") {
				t.Fatalf("verification entered initialization: %s", output)
			}
			if _, err := os.Stat(home); !os.IsNotExist(err) {
				t.Fatalf("verification accessed home: %v", err)
			}
		})
	}
}
