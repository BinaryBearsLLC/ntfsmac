#!/usr/bin/env python3
"""Verify the self-contained runtime against reviewed locks, without network access."""
import hashlib
import json
import pathlib
import re
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(root):
    root = pathlib.Path(root)
    payload = root / 'vendor/runtime'
    lock = dict(line.split('=', 1) for line in (root / 'build/sources.lock').read_text().splitlines() if line and not line.startswith('#'))
    require(not (root / 'vendor').is_symlink(), 'symlink vendor path forbidden')
    require(payload.is_dir() and not payload.is_symlink(), 'invalid runtime directory')
    actual = set()
    for path in payload.rglob('*'):
        require(not path.is_symlink(), f'symlink path forbidden: {path}')
        require(path.is_dir() or path.is_file(), f'non-regular path: {path}')
        if path.is_file() and path != payload / 'SHA256SUMS':
            actual.add(path.relative_to(payload).as_posix())
    manifest = payload / 'SHA256SUMS'
    require(sha(manifest) == lock['OFFLINE_RUNTIME_SHA256'], 'runtime manifest hash mismatch')
    entries = {}
    for line in manifest.read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9_./+-]+)', line)
        require(match is not None, 'invalid manifest path or hash')
        digest, name = match.groups()
        require(not name.startswith('/') and all(part not in ('', '.', '..') for part in name.split('/')), 'unsafe manifest path')
        require(name not in entries and name != 'SHA256SUMS', 'duplicate or recursive manifest path')
        entries[name] = digest
    require(set(entries) == actual, 'runtime file inventory mismatch')
    for name, digest in entries.items():
        require(sha(payload / name) == digest, f'runtime hash mismatch: {name}')
    for suffix, key in [('base-packages', 'ALPINE_BASE_PACKAGES_SHA256'), ('packages', 'ALPINE_PACKAGES_SHA256'), ('apks', 'ALPINE_APKS_SHA256')]:
        require(sha(root / f'build/alpine-{suffix}.lock') == lock[key], f'{suffix} lock hash mismatch')
    apk_entries = {}
    packages = []
    for line in (root / 'build/alpine-apks.lock').read_text().splitlines():
        spec, channel, digest = line.split()
        name, version = spec.split('=')
        require(re.fullmatch(r'[a-zA-Z0-9_.+-]+', name) and re.fullmatch(r'[a-zA-Z0-9_.+-]+', version), 'invalid APK name/version')
        filename = f'apks/{name}-{version}.apk'
        require(filename not in apk_entries and re.fullmatch(r'[0-9a-f]{64}', digest), 'invalid APK lock')
        apk_entries[filename] = digest
        packages.append(spec)
    require(apk_entries == {n: d for n, d in entries.items() if n.startswith('apks/')}, 'APK artifact lock mismatch')
    require(packages == (root / 'build/alpine-packages.lock').read_text().splitlines(), 'APK package closure mismatch')

    oci = payload / 'oci'
    require(json.loads((oci / 'oci-layout').read_text()) == {'imageLayoutVersion': '1.0.0'}, 'unsupported OCI layout')
    index = json.loads((oci / 'index.json').read_text())
    require(index['schemaVersion'] == 2 and len(index['manifests']) == 1, 'invalid OCI index')
    descriptor = index['manifests'][0]
    require(descriptor['digest'] == lock['ALPINE_DIGEST'], 'OCI pinned identity mismatch')
    require(descriptor.get('annotations', {}).get('org.opencontainers.image.ref.name') == 'pinned-' + lock['ALPINE_DIGEST'][7:19], 'OCI reference annotation mismatch')
    blobs = set()

    def blob(desc):
        require(re.fullmatch(r'sha256:[0-9a-f]{64}', desc['digest']), 'invalid OCI blob digest')
        name = 'oci/blobs/sha256/' + desc['digest'][7:]
        path = payload / name
        require(entries.get(name) == desc['digest'][7:] and path.stat().st_size == desc['size'], 'OCI blob hash/size mismatch')
        blobs.add(name)
        return path

    image = json.loads(blob(descriptor).read_text())
    require(image['schemaVersion'] == 2 and image['layers'], 'invalid OCI image')
    config = json.loads(blob(image['config']).read_text())
    require(config['architecture'] == 'arm64' and config['os'] == 'linux', 'wrong OCI platform')
    for layer in image['layers']:
        blob(layer)
    require(blobs == {n for n in entries if n.startswith('oci/blobs/')}, 'unexpected OCI blob')
    provenance = json.loads((payload / 'PROVENANCE.json').read_text())
    require(provenance['alpine_oci_reference'] == 'docker.io/library/alpine@' + lock['ALPINE_DIGEST'], 'OCI provenance mismatch')
    require(provenance['nfs_entrypoint']['commit'] == lock['NFS_ENTRYPOINT_COMMIT'] and provenance['nfs_entrypoint']['sha256'] == entries['entrypoint.sh'], 'entrypoint provenance mismatch')
    require(sorted(f"{p['pkgname']}={p['pkgver']}" for p in provenance['packages'] if p['arch'] in ('aarch64', 'noarch')) == sorted(packages), 'APK provenance mismatch')
    return len(entries)


if __name__ == '__main__':
    try:
        require(len(sys.argv) == 2, 'usage: verify-offline-runtime.py repository-root')
        count = verify(sys.argv[1])
        print(f'offline runtime: verified {count} files, pinned OCI and APK closure')
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f'offline runtime: {error}', file=sys.stderr)
        sys.exit(1)
