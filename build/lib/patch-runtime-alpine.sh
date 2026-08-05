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
  python3 - "$init_rootfs_dir/main.go" "$ALPINE_RUNTIME_REF" <<'PYEOF'
from pathlib import Path
import sys

path = Path(sys.argv[1])
ref = sys.argv[2]
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
    ('flag.StringVar(&dockerRef, "docker-ref", "alpine:latest", "Docker/OCI image reference (e.g. alpine:latest, alpine:edge)")', f'flag.StringVar(&dockerRef, "docker-ref", "{ref}", "Digest-pinned Docker/OCI image reference")'),
]
for old, new in markers:
    if text.count(old) != 1:
        raise SystemExit(f"init-rootfs: HARD-STOP — runtime pin patch marker drifted in {path}: {old[:80]!r}")
    text = text.replace(old, new, 1)

if "alpine:latest" in text:
    raise SystemExit(f"init-rootfs: HARD-STOP — floating Alpine reference remains in {path}")
path.write_text(text)
print(f"init-rootfs: patched Docker reference parsing and default to {ref}")
PYEOF
}
