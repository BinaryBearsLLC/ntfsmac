#!/bin/bash
# Deterministic source transformations applied only to scratch build copies of pinned anylinuxfs.
# The vendored submodule remains byte-for-byte at ANYLINUXFS_COMMIT.

patch_anylinuxfs_runtime_alpine() {
  local build_root="$1"
  python3 - "$build_root" "$ALPINE_RUNTIME_REF" "$ALPINE_RUNTIME_BASE_DIR" "$ALPINE_RUNTIME_VERSION" <<'PYEOF'
from pathlib import Path
import sys

root = Path(sys.argv[1])
ref, base_dir, version = sys.argv[2:]

settings = root / "anylinuxfs/src/settings.rs"
text = settings.read_text()
replacements = {
    'base_dir: "alpine".into(),': f'base_dir: "{base_dir}".into(),',
    'docker_ref: Some("alpine:latest".into()),': f'docker_ref: Some("{ref}".into()),',
}
for old, new in replacements.items():
    if text.count(old) != 1:
        raise SystemExit(f"build-all: HARD-STOP — expected exactly one marker in {settings}: {old}")
    text = text.replace(old, new, 1)
settings.write_text(text)

vm_image = root / "anylinuxfs/src/vm_image.rs"
text = vm_image.read_text()
old = 'src.docker_ref.as_deref().unwrap_or("alpine:latest")'
new = f'src.docker_ref.as_deref().unwrap_or("{ref}")'
if text.count(old) != 1:
    raise SystemExit(f"build-all: HARD-STOP — expected exactly one fallback marker in {vm_image}")
vm_image.write_text(text.replace(old, new, 1))

for config_name in ("anylinuxfs.toml", "anylinuxfs-linux.toml"):
    config = root / "etc" / config_name
    text = config.read_text()
    if text.count('base_dir = "alpine"') != 1 or text.count('docker_ref = "alpine:latest"') != 1:
        raise SystemExit(f"build-all: HARD-STOP — Alpine config markers drifted in {config}")
    text = text.replace('base_dir = "alpine"', f'base_dir = "{base_dir}"', 1)
    text = text.replace('docker_ref = "alpine:latest"', f'docker_ref = "{ref}"', 1)
    config.write_text(text)

version_path = root / "share/alpine/rootfs.ver"
version_path.write_text(version)

remaining = []
for path in (settings, vm_image, root / "etc/anylinuxfs.toml", root / "etc/anylinuxfs-linux.toml"):
    if "alpine:latest" in path.read_text():
        remaining.append(str(path))
if remaining:
    raise SystemExit("build-all: HARD-STOP — floating Alpine reference remains in " + ", ".join(remaining))
print(f"build-all: pinned runtime Alpine to {ref} in cache directory {base_dir}")
PYEOF
}

patch_init_rootfs_runtime_alpine() {
  local init_rootfs_dir="$1"
  local apk_lock="$2"
  python3 - "$init_rootfs_dir/main.go" "$ALPINE_RUNTIME_REF" \
    "$ALPINE_BASE_PACKAGES_SHA256" "$ALPINE_PACKAGES_SHA256" \
    "$ALPINE_APKS_SHA256" "$apk_lock" <<'PYEOF'
from pathlib import Path
import sys

path = Path(sys.argv[1])
ref, base_packages_sha, packages_sha, apks_sha, apk_lock_path = sys.argv[2:]
apk_manifest = Path(apk_lock_path).read_text().rstrip("\n")
text = path.read_text()

markers = [
    ("// reference when no explicit base_dir is configured. Both the image name and\n// tag are included to avoid collisions (e.g. alpine:latest vs alpine:edge).\n",
     "// reference when no explicit base_dir is configured. Both the image name and\n// tag are included to avoid collisions between tagged or digest-pinned variants.\n"),
    ("\tImageName         string\n", "\tImageName         string\n\tSourceReference   string\n"),
    (
        "\t// Parse docker reference into image name and tag.\n\timageName := dockerRef\n\ttag := \"latest\"\n\tif idx := strings.LastIndex(dockerRef, \":\"); idx >= 0 {\n\t\timageName = dockerRef[:idx]\n\t\ttag = dockerRef[idx+1:]\n\t}\n",
        "\t// Keep the complete source reference (including an optional digest) for the registry.\n\t// The OCI layout still needs a local tag, derived deterministically from the digest.\n\timageName := dockerRef\n\ttag := \"runtime\"\n\tif at := strings.LastIndex(dockerRef, \"@\"); at >= 0 {\n\t\timageName = dockerRef[:at]\n\t\tdigest := strings.TrimPrefix(dockerRef[at+1:], \"sha256:\")\n\t\tif len(digest) < 12 {\n\t\t\tfmt.Println(\"Pinned Docker/OCI reference has an invalid digest\")\n\t\t\tos.Exit(1)\n\t\t}\n\t\ttag = \"pinned-\" + digest[:12]\n\t} else if idx := strings.LastIndex(dockerRef, \":\"); idx >= 0 {\n\t\timageName = dockerRef[:idx]\n\t\ttag = dockerRef[idx+1:]\n\t}\n",
    ),
    ("\t\tImageName:         imageName,\n", "\t\tImageName:         imageName,\n\t\tSourceReference:   dockerRef,\n"),
    ('docker.ParseReference(fmt.Sprintf("//%s:%s", cfg.ImageName, cfg.Tag))', 'docker.ParseReference("//" + cfg.SourceReference)'),
    (
        '\t\tSourceCtx: &types.SystemContext{\n\t\t\tOSChoice: "linux",\n\t\t},',
        '\t\tSourceCtx: &types.SystemContext{\n'
        '\t\t\tOSChoice: "linux",\n'
        '\t\t\t// The pinned public runtime must not inherit optional signature-storage\n'
        '\t\t\t// metadata from ~/.config/containers/registries.d. An unreadable user\n'
        '\t\t\t// directory must not block ntfsmac before drive discovery starts.\n'
        '\t\t\tRegistriesDirPath: filepath.Join(cfg.ImageBasePath, ".ntfsmac-empty-registries.d"),\n'
        '\t\t},',
    ),
    ('flag.StringVar(&dockerRef, "docker-ref", "alpine:latest", "Docker/OCI image reference (e.g. alpine:latest, alpine:edge)")', f'flag.StringVar(&dockerRef, "docker-ref", "{ref}", "Digest-pinned Docker/OCI image reference")'),
]
for old, new in markers:
    if text.count(old) != 1:
        raise SystemExit(f"init-rootfs: HARD-STOP — runtime pin patch marker drifted in {path}: {old[:80]!r}")
    text = text.replace(old, new, 1)

custom_packages_marker = '''\t// Load custom packages from config
\tcustomPackages := loadCustomPackages(cfg.UserStore)

\t// Default packages
\tdefaultPackages := getDefaultPackages()

\t// Combine default and custom packages
\tallPackages := append(defaultPackages, customPackages...)
\tpackagesStr := strings.Join(allPackages, " ")
'''
locked_packages = '''\t// ntfsmac ships one reviewed package closure. Per-user additions would make the
\t// guest mutable and bypass the package lock, so reject them before VM setup.
\tcustomPackages := loadCustomPackages(cfg.UserStore)
\tif len(customPackages) != 0 {
\t\treturn fmt.Errorf("ntfsmac package lock does not allow custom Alpine packages")
\t}

\tdefaultPackages := getDefaultPackages()
\tallPackages := defaultPackages
\tpackagesStr := strings.Join(allPackages, " ")
'''
if text.count(custom_packages_marker) != 1:
    raise SystemExit(f"init-rootfs: HARD-STOP — custom package patch marker drifted in {path}")
text = text.replace(custom_packages_marker, locked_packages, 1)

setup_marker = '''%s
apk --update --no-cache add %s
MOD_PATH="modules/$(uname -r)"
'''
locked_setup = '''%s
# The second fmt placeholder is retained so upstream's package-count/reporting path stays intact.
# ntfsmac locked package set: %s
APK_DIR=/var/cache/ntfsmac-apks
mkdir -p "$APK_DIR"
while read -r APK_CONSTRAINT APK_CHANNEL APK_SHA256; do
    APK_NAME="${APK_CONSTRAINT%%=*}"
    APK_VERSION="${APK_CONSTRAINT#*=}"
    APK_FILE="${APK_NAME}-${APK_VERSION}.apk"
    APK_PATH="$APK_DIR/$APK_FILE"
    APK_URL="https://dl-cdn.alpinelinux.org/alpine/$APK_CHANNEL/aarch64/$APK_FILE"
    if ! wget -q -O "$APK_PATH.download" "$APK_URL"; then
        echo "ntfsmac: locked Alpine APK download failed: $APK_FILE" >&2
        exit 1
    fi
    if ! printf '%%s  %%s\\n' "$APK_SHA256" "$APK_PATH.download" | sha256sum -c -; then
        echo "ntfsmac: locked Alpine APK checksum failed: $APK_FILE" >&2
        exit 1
    fi
    mv -f "$APK_PATH.download" "$APK_PATH"
done <<'NTFSMAC_APK_LOCK'
__APK_MANIFEST__
NTFSMAC_APK_LOCK
if ! apk --no-network --no-cache add "$APK_DIR"/*.apk; then
    echo "ntfsmac: locked Alpine package installation failed" >&2
    exit 1
fi
echo "__BASE_PACKAGES_SHA__" > /etc/ntfsmac-alpine-base-packages.sha256
echo "__PACKAGES_SHA__" > /etc/ntfsmac-alpine-packages.sha256
echo "__APKS_SHA__" > /etc/ntfsmac-alpine-apks.sha256
MOD_PATH="modules/$(uname -r)"
'''
locked_setup = (locked_setup
    .replace("__APK_MANIFEST__", apk_manifest)
    .replace("__BASE_PACKAGES_SHA__", base_packages_sha)
    .replace("__PACKAGES_SHA__", packages_sha)
    .replace("__APKS_SHA__", apks_sha))
if text.count(setup_marker) != 1:
    raise SystemExit(f"init-rootfs: HARD-STOP — package setup patch marker drifted in {path}")
text = text.replace(setup_marker, locked_setup, 1)

if "alpine:latest" in text:
    raise SystemExit(f"init-rootfs: HARD-STOP — floating Alpine reference remains in {path}")
path.write_text(text)
print(f"init-rootfs: patched Docker reference parsing, isolated registry metadata, and default to {ref}")
PYEOF
}
