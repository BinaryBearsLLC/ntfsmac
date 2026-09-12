// Added only to the disposable build copy of the pinned anylinuxfs source.
// No AppRunner/config/image/VM/mount path is entered by this command.
use anyhow::{Context, bail};
use crate::devinfo::DevInfo;

fn valid_device(device: &str) -> bool {
    let Some(rest) = device.strip_prefix("disk") else { return false; };
    let Some((disk, slice)) = rest.split_once('s') else { return false; };
    !disk.is_empty() && !slice.is_empty()
        && disk.bytes().all(|c| c.is_ascii_digit())
        && slice.bytes().all(|c| c.is_ascii_digit())
}

pub(crate) fn run(device: &str) -> anyhow::Result<()> {
    if !valid_device(device) { bail!("rejected: expected diskNsM partition identifier"); }
    // libblkid safeprobe reads metadata; it never mounts, repairs, assembles or decrypts.
    // Unlike `list`, this probes only the requested partition, not its siblings.
    let path = format!("/dev/{device}");
    let info = DevInfo::pv(path.as_str(), false).context("filesystem metadata unavailable")?;
    println!("{}", serde_json::json!({
        "device": device,
        "fs_type": info.fs_type(),
        "label": info.label(),
    }));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn permits_only_partition_identifiers() {
        for name in ["disk0s1", "disk12s34"] { assert!(valid_device(name)); }
        for name in ["", "disk4", "/dev/disk4s2", "disk4s2\n", "disk4s2;id", "disk4s2s3", "disk４s2"] {
            assert!(!valid_device(name), "{name}");
            assert!(run(name).is_err());
        }
    }
}
