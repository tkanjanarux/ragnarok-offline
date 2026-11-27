#!/usr/bin/env python3
"""Prepare the review-only cash shop overlay on either immutable deployed profile."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('baseline', HERE.parent / 'prepare.py')
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify(output, profile):
    change = json.loads((HERE / 'preflight-source.json').read_text())
    expected = dict(baseline.load(profile)['files'])
    assert expected[change['source']] == change['base_sha256']
    expected[change['source']] = change['patched_sha256']
    exchange = json.loads((HERE / 'exchange-source.json').read_text())
    assert expected[exchange['source']] == exchange['base_sha256']
    expected[exchange['source']] = exchange['patched_sha256']
    dialog = json.loads((HERE / 'item-dialog-source.json').read_text())[profile]
    assert expected[dialog['source']] == dialog['base_sha256']
    expected[dialog['source']] = dialog['patched_sha256']
    pet = json.loads((HERE / 'pet-source.json').read_text())[profile]
    for pet_change in pet['changes']:
        assert expected[pet_change['source']] == pet_change['base_sha256']
        expected[pet_change['source']] = pet_change['patched_sha256']
    for extra in pet['extra_files']:
        assert sha(HERE / extra['native']) == extra['sha256']
        expected[extra['source']] = extra['sha256']
    for name, digest in expected.items():
        assert sha(output / name) == digest, name
    actual = {str(p.relative_to(output)) for part in ['src', '3rdparty']
              for p in (output / part).rglob('*') if p.is_file()}
    assert actual == set(expected) - {'Makefile.dgx'}
    return len(expected)

def prepare(output, profile, base):
    baseline.prepare(output, profile, base, runtime=True)
    change = json.loads((HERE / 'preflight-source.json').read_text())
    patch = HERE / 'patches/cashshop-preflight.patch'
    assert sha(patch) == change['patch_sha256']
    target = output / change['source']
    assert sha(target) == change['base_sha256']
    # Baseline files retain their original line endings; apply against normalized
    # source, then restore exactly. Never fuzzy/force-apply to an unknown tree.
    original = target.read_bytes()
    target.write_bytes(original.replace(b'\r\n', b'\n'))
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=output, check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=output, check=True)
    if b'\r\n' in original:
        target.write_bytes(target.read_bytes().replace(b'\n', b'\r\n'))
    exchange = json.loads((HERE / 'exchange-source.json').read_text())
    snippet = HERE / 'native/catalogue_exchange.inc'
    assert sha(snippet) == exchange['snippet_sha256']
    pet_runtime = HERE / 'native/pet/catalogue_pet_runtime.inc'
    assert sha(pet_runtime) == exchange['pet_runtime_sha256']
    script = output / exchange['source']
    assert sha(script) == exchange['base_sha256']
    data = script.read_bytes()
    data = data.replace(b'BUILDIN_FUNC(checkweight2)', snippet.read_bytes() + b'\n' + pet_runtime.read_bytes() + b'\nBUILDIN_FUNC(checkweight2)', 1)
    data = data.replace(b'BUILDIN_DEF(checkweight2,"rr"),', b'BUILDIN_DEF(checkweight2,"rr"),\n\tBUILDIN_DEF(catalogue_exchange,"iii*"),\n\tBUILDIN_DEF(catalogue_reset,"ii"),\n\tBUILDIN_DEF(catalogue_remove_cards,"iiiiiiiii"),\n\tBUILDIN_DEF(catalogue_pet_claim,"iiii"),', 1)
    script.write_bytes(data)
    dialog = json.loads((HERE / 'item-dialog-source.json').read_text())[profile]
    patch = HERE / f'patches/item-dialog-{profile}.patch'
    assert sha(patch) == dialog['patch_sha256']
    target = output / dialog['source']
    assert sha(target) == dialog['base_sha256']
    old = target.read_bytes()
    target.write_bytes(old.replace(b'\r\n', b'\n'))
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=output, check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=output, check=True)
    if b'\r\n' in old:
        target.write_bytes(target.read_bytes().replace(b'\n', b'\r\n'))
    pet = json.loads((HERE / 'pet-source.json').read_text())[profile]
    patch = HERE / f'patches/pet-journal-{profile}.patch'
    assert sha(patch) == pet['patch_sha256']
    for pet_change in pet['changes']:
        target = output / pet_change['source']
        assert sha(target) == pet_change['base_sha256']
        target.write_bytes(target.read_bytes().replace(b'\r\n', b'\n'))
    subprocess.run(['git', 'apply', '--check', str(patch)], cwd=output, check=True)
    subprocess.run(['git', 'apply', str(patch)], cwd=output, check=True)
    for pet_change in pet['changes']:
        target = output / pet_change['source']
        if pet_change['crlf']:
            target.write_bytes(target.read_bytes().replace(b'\n', b'\r\n'))
    for extra in pet['extra_files']:
        source = HERE / extra['native']
        assert sha(source) == extra['sha256']
        (output / extra['source']).write_bytes(source.read_bytes())
    count = verify(output, profile)
    (output / 'CASH-SHOP-OVERLAY.json').write_text(json.dumps({
        'profile': profile, 'verified_source_files': count,
        'packetver': change['packetver'], 'overlay': change,
        'production_deployment': False}, indent=2) + '\n')
    return count

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('profile', choices=['production', 'playable'])
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--base', type=Path, default=HERE.parent.parent / 'swift-rathena')
    p.add_argument('--verify', action='store_true')
    a = p.parse_args()
    count = verify(a.output.resolve(), a.profile) if a.verify else prepare(a.output.resolve(), a.profile, a.base.resolve())
    print(json.dumps({'profile': a.profile, 'verified_source_files': count, 'live_deployed': False}))
