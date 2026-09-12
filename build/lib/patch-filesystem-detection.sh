#!/bin/bash
# Apply only to a disposable copy; never change the pinned upstream submodule.
patch_anylinuxfs_filesystem_detection() {
  local target="$1/anylinuxfs/src/diskutil/darwin.rs"
  local probe_source
  probe_source="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../runtime" && pwd)/filesystem_probe.rs"
  python3 - "$target" "$probe_source" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '''                let line = match dev_info {
                    Some(dev_info) => {
                        let fs_type = dev_info.fs_type().unwrap_or(part_type);
                        pv.try_collect(&dev_info, dev_ident, &disk_path, fs_type);

                        augment_line(line, part_type, Some(&dev_info), fs_type)
                    }
                    None => line.to_owned(),
                };'''
new = '''                // MBR 0x07 and GPT Microsoft Basic Data identify a partition family,
                // not a filesystem. Both NTFS and exFAT use them. An unprivileged
                // libblkid probe can fail; ask macOS about THIS partition in that case.
                let host_fs = if dev_info.as_ref().and_then(|di| di.fs_type()).is_none()
                    && matches!(part_type, "Windows_NTFS" | "Microsoft Basic Data")
                {
                    ntfsmac_host_filesystem(dev_ident)
                } else {
                    None
                };
                let fs_type = dev_info.as_ref().and_then(|di| di.fs_type())
                    .or(host_fs.as_deref())
                    .unwrap_or(if matches!(part_type, "Windows_NTFS" | "Microsoft Basic Data") {
                        "Unknown"
                    } else {
                        part_type
                    });
                if let Some(ref di) = dev_info {
                    pv.try_collect(di, dev_ident, &disk_path, fs_type);
                }
                let line = augment_line(line, part_type, dev_info.as_ref(), fs_type);'''
if text.count(old) != 1 or 'fn ntfsmac_host_filesystem' in text:
    raise SystemExit('filesystem patch: HARD-STOP — upstream detection markers drifted')
text = text.replace(old, new, 1)
text += r'''

// Only FilesystemType is evidence. Content/partition names must never be used here.
#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
struct NtfsmacFilesystemInfo {
    device_identifier: String,
    filesystem_type: Option<String>,
}

fn ntfsmac_filesystem_from_plist(bytes: &[u8], expected: &str) -> Option<String> {
    let info: NtfsmacFilesystemInfo = plist::from_bytes(bytes).ok()?;
    if info.device_identifier != expected {
        return None;
    }
    info.filesystem_type.filter(|kind| !kind.is_empty())
}

fn ntfsmac_host_filesystem(device: &str) -> Option<String> {
    let output = Command::new("/usr/sbin/diskutil")
        .args(["info", "-plist", device]).output().ok()?;
    if !output.status.success() {
        return None;
    }
    ntfsmac_filesystem_from_plist(&output.stdout, device)
}

#[cfg(test)]
mod ntfsmac_filesystem_tests {
    use super::ntfsmac_filesystem_from_plist;

    fn fixture(device: &str, fields: &str) -> Vec<u8> {
        format!(r#"<?xml version="1.0"?><plist version="1.0"><dict>
        <key>DeviceIdentifier</key><string>{device}</string>{fields}</dict></plist>"#).into_bytes()
    }

    #[test]
    fn distinguishes_ntfs_and_exfat_with_identical_partition_types() {
        for fs in ["ntfs", "exfat"] {
            let bytes = fixture("disk4s1", &format!(
                "<key>Content</key><string>Windows_NTFS</string><key>FilesystemType</key><string>{fs}</string>"));
            assert_eq!(ntfsmac_filesystem_from_plist(&bytes, "disk4s1"), Some(fs.into()));
        }
    }

    #[test]
    fn never_borrows_filesystem_from_another_device() {
        let bytes = fixture("disk5s1", "<key>FilesystemType</key><string>ntfs</string>");
        assert_eq!(ntfsmac_filesystem_from_plist(&bytes, "disk4s1"), None);
    }

    #[test]
    fn missing_malformed_and_partition_only_metadata_are_unknown() {
        for bytes in [b"not a plist".to_vec(), fixture("disk4s1", ""),
            fixture("disk4s1", "<key>Content</key><string>Microsoft Basic Data</string>"),
            fixture("disk4s1", "<key>FilesystemType</key><string></string>")] {
            assert_eq!(ntfsmac_filesystem_from_plist(&bytes, "disk4s1"), None);
        }
    }
}
'''
path.write_text(text)
source_dir = path.parent.parent
main = source_dir / 'main.rs'
cli = source_dir / 'cli.rs'
main_text, cli_text = main.read_text(), cli.read_text()
replacements = [
    ('mod fsutil;', 'mod fsutil;\nmod filesystem_probe;'),
    ('            Commands::List(cmd) => self.run_list(cmd),',
     '            Commands::List(cmd) => self.run_list(cmd),\n'
     '            Commands::ProbeFilesystem { device } => filesystem_probe::run(&device),'),
]
for old, new in replacements:
    if main_text.count(old) != 1:
        raise SystemExit('filesystem patch: HARD-STOP — native probe main marker drifted')
    main_text = main_text.replace(old, new, 1)
marker = '    List(ListCmd),'
if cli_text.count(marker) != 1:
    raise SystemExit('filesystem patch: HARD-STOP — native probe CLI marker drifted')
cli_text = cli_text.replace(marker, marker + '\n'
    '    /// Read one partition superblock as JSON, without mounting or starting a VM\n'
    '    ProbeFilesystem { device: String },', 1)
main.write_text(main_text)
cli.write_text(cli_text)
(source_dir / 'filesystem_probe.rs').write_text(Path(sys.argv[2]).read_text())
print('filesystem patch: verified per-device macOS filesystem fallback')
PY
}
