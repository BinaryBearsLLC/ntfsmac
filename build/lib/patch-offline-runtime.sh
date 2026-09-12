#!/bin/bash
# Apply after patch_init_rootfs_runtime_alpine, only to the scratch Go source.
patch_init_rootfs_offline_runtime() {
  local init_rootfs_dir="$1" repo_root="$2"
  python3 "$repo_root/build/verify-offline-runtime.py" "$repo_root" || return 1
  python3 - "$init_rootfs_dir" "$repo_root" "$ALPINE_RUNTIME_REF" <<'PYEOF'
from pathlib import Path
import json
import sys

root, repo = map(Path, sys.argv[1:3])
reference = sys.argv[3]
source = root / "main.go"
text = source.read_text()

def replace(old, new):
    global text
    if text.count(old) != 1:
        raise SystemExit(f"init-rootfs: HARD-STOP — offline patch marker drifted: {old[:100]!r}")
    text = text.replace(old, new, 1)

for imported in ('"io"', '"net/http"', '"go.podman.io/image/v5/docker"'):
    replace('\t' + imported + '\n', '')
replace('docker.ParseReference("//" + cfg.SourceReference)',
        'layout.ParseReference(filepath.Join(cfg.PrefixDir, "lib", "ntfsmac-runtime", "oci") + ":" + cfg.Tag)')
replace('func downloadImage(cfg *Config) error {\n', '''func downloadImage(cfg *Config) error {
\tif err := verifyOfflineRuntime(cfg); err != nil {
\t\treturn err
\t}
''')
replace('func initRootfs(cfg *Config, nameserver string, setupScript string) error {\n', '''func initRootfs(cfg *Config, nameserver string, setupScript string) error {
\t// Verify the complete installed payload before touching an existing cache.
\tif err := verifyOfflineRuntime(cfg); err != nil {
\t\tfmt.Println(err)
\t\treturn err
\t}
''')
start = text.index('func downloadEntrypointScript(rootfsPath string) error {')
end = text.index('\nfunc copyFile(', start)
text = text[:start] + text[end:]
replace('downloadEntrypointScript(cfg.RootfsPath)', 'copyOfflineEntrypoint(cfg)')
replace('\tif err := writeSetupScript(cfg, setupScript); err != nil {', '''\tif err := stageOfflineAPKs(cfg); err != nil {
\t\treturn err
\t}

\tif err := writeSetupScript(cfg, setupScript); err != nil {''')
# Preserve the independently locked package list and sha256sum verification.
start = text.index('    APK_URL="https://dl-cdn.alpinelinux.org/')
end = text.index("done <<'NTFSMAC_APK_LOCK'", start)
text = text[:start] + '''    if [ ! -f "$APK_PATH" ] || [ -L "$APK_PATH" ]; then
        echo "ntfsmac: bundled Alpine APK missing; reinstall ntfsmac: $APK_FILE" >&2
        exit 1
    fi
    if ! printf '%%s  %%s\\n' "$APK_SHA256" "$APK_PATH" | sha256sum -c -; then
        echo "ntfsmac: bundled Alpine APK checksum failed; reinstall ntfsmac: $APK_FILE" >&2
        exit 1
    fi
''' + text[end:]
replace('\tvar nameserver string\n', '\tvar verifyOfflinePath string\n\tvar nameserver string\n')
replace('\tflag.Parse()\n', '''\tflag.StringVar(&verifyOfflinePath, "verify-offline-runtime", "", "Verify an offline runtime payload directory and exit")
\tflag.Parse()

\t// Installer verification must not consult the user's home, cache, or VM.
\tverificationOnly := false
\tflag.Visit(func(value *flag.Flag) {
\t\tif value.Name == "verify-offline-runtime" {
\t\t\tverificationOnly = true
\t\t}
\t})
\tif verificationOnly {
\t\tif verifyOfflinePath == "" {
\t\t\tfmt.Fprintln(os.Stderr, "ntfsmac: -verify-offline-runtime requires a payload directory")
\t\t\tos.Exit(1)
\t\t}
\t\tif err := verifyOfflineRuntimeAt(verifyOfflinePath); err != nil {
\t\t\tfmt.Fprintln(os.Stderr, err)
\t\t\tos.Exit(1)
\t\t}
\t\tfmt.Println("ntfsmac: offline runtime payload verified")
\t\treturn
\t}
''')
replace('// Download image', '// Import the verified local OCI image')
for remote in ('http.Get(', 'wget ', 'docker.ParseReference(', 'raw.githubusercontent.com', 'dl-cdn.alpinelinux.org'):
    if remote in text:
        raise SystemExit(f"init-rootfs: HARD-STOP — remote runtime source remains: {remote}")
source.write_text(text)
(root / 'offline_runtime.go').write_bytes((repo / 'build/runtime/offline_runtime.go').read_bytes())
(root / 'offline-runtime.sha256').write_bytes((repo / 'vendor/runtime/SHA256SUMS').read_bytes())
(root / 'offline_runtime_constants.go').write_text('package main\n\nconst offlineRuntimeReference = ' + json.dumps(reference) + '\n')
print('init-rootfs: embedded verified offline runtime manifest and replaced all remote runtime sources')
PYEOF
}
