"""Exercise the real payload verifier without network or build side effects."""
import hashlib
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]


class OfflinePayloadTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        shutil.copytree(REPO / 'vendor/runtime', self.root / 'vendor/runtime')
        (self.root / 'build').mkdir()
        for name in ['sources.lock', 'alpine-apks.lock', 'alpine-packages.lock', 'alpine-base-packages.lock']:
            shutil.copy2(REPO / 'build' / name, self.root / 'build' / name)
        self.payload = self.root / 'vendor/runtime'

    def tearDown(self):
        self.temp.cleanup()

    def verify(self):
        return subprocess.run(['python3', str(REPO / 'build/verify-offline-runtime.py'), str(self.root)], capture_output=True, text=True)

    def resign(self):
        manifest = self.payload / 'SHA256SUMS'
        manifest.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(self.payload)}\n' for p in sorted(self.payload.rglob('*')) if p.is_file() and p != manifest))
        lock = self.root / 'build/sources.lock'
        lines = lock.read_text().splitlines()
        lock.write_text('\n'.join('OFFLINE_RUNTIME_SHA256=' + hashlib.sha256(manifest.read_bytes()).hexdigest() if s.startswith('OFFLINE_RUNTIME_SHA256=') else s for s in lines) + '\n')

    def test_valid_payload(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_tampered_artifact(self):
        next((self.payload / 'apks').glob('*.apk')).write_bytes(b'altered')
        self.assertNotEqual(self.verify().returncode, 0)

    def test_missing_artifact(self):
        (self.payload / 'entrypoint.sh').unlink()
        self.assertNotEqual(self.verify().returncode, 0)

    def test_extra_artifact(self):
        (self.payload / 'unexpected').write_bytes(b'extra')
        self.assertNotEqual(self.verify().returncode, 0)

    def test_nested_manifest_is_an_unlisted_artifact(self):
        (self.payload / 'apks/SHA256SUMS').write_text('unexpected')
        self.assertNotEqual(self.verify().returncode, 0)

    def test_symlink_vendor_directory(self):
        vendor = self.root / 'vendor'
        target = self.root / 'real-vendor'
        vendor.rename(target)
        vendor.symlink_to(target, target_is_directory=True)
        self.assertNotEqual(self.verify().returncode, 0)

    def test_symlink_even_to_identical_bytes(self):
        entry = self.payload / 'entrypoint.sh'
        dest = self.root / 'entrypoint.sh'
        entry.rename(dest)
        entry.symlink_to(dest)
        self.assertNotEqual(self.verify().returncode, 0)

    def test_manifest_path_escape(self):
        manifest = self.payload / 'SHA256SUMS'
        manifest.write_text(manifest.read_text() + '0' * 64 + '  ../escape\n')
        lock = self.root / 'build/sources.lock'
        import re
        lock.write_text(re.sub(r'OFFLINE_RUNTIME_SHA256=.*', 'OFFLINE_RUNTIME_SHA256=' + hashlib.sha256(manifest.read_bytes()).hexdigest(), lock.read_text()))
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('path', result.stderr.lower())

    def test_trusted_manifest_cannot_override_apk_lock(self):
        next((self.payload / 'apks').glob('*.apk')).write_bytes(b'altered')
        self.resign()
        self.assertNotEqual(self.verify().returncode, 0)

    def test_trusted_manifest_cannot_override_oci_identity(self):
        index = self.payload / 'oci/index.json'
        import json
        obj = json.loads(index.read_text())
        obj['manifests'][0]['digest'] = 'sha256:' + '0' * 64
        index.write_text(json.dumps(obj))
        self.resign()
        self.assertNotEqual(self.verify().returncode, 0)


if __name__ == '__main__':
    unittest.main()
