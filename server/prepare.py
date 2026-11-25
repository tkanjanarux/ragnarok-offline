#!/usr/bin/env python3
"""Reconstruct a deployed native server profile without changing the iOS submodule."""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent

def digest(data):
    return hashlib.sha256(data).hexdigest()

def normalized(data):
    return data if b'\0' in data else data.replace(b'\r\n', b'\n')

def load(profile):
    return json.loads((HERE / 'profiles' / profile / 'source-manifest.json').read_text())

def restore_newlines(data, mode):
    if mode == 'binary':
        return data
    data = normalized(data)
    if mode == 'lf':
        return data
    if mode == 'crlf':
        return data.replace(b'\n', b'\r\n')
    lines = data.splitlines(keepends=True)
    indices = set(mode.get('crlf_lines', mode.get('lf_lines', [])))
    for index, line in enumerate(lines):
        crlf = index in indices if 'crlf_lines' in mode else index not in indices
        if crlf and line.endswith(b'\n'):
            lines[index] = line[:-1] + b'\r\n'
    return b''.join(lines)

def verify(output, profile):
    manifest = load(profile)
    for name, expected in manifest['files'].items():
        path = output / name
        if not path.is_file() or digest(path.read_bytes()) != expected:
            raise ValueError('Source does not match deployed profile: ' + name)
    actual = {str(p.relative_to(output)) for part in ['src', '3rdparty']
              for p in (output / part).rglob('*') if p.is_file()}
    assert actual == set(manifest['files']) - {'Makefile.dgx'}, 'Unexpected source files'
    return len(manifest['files'])

def prepare(output, profile, base, runtime=False):
    if output.exists():
        raise ValueError('Output already exists; choose a new directory or use --verify')
    if not (base / 'src/common/mmo.hpp').is_file():
        raise ValueError('Initialize the pinned dependency: git submodule update --init --recursive')
    production = load('production')
    output.mkdir(parents=True)
    for name in production['files']:
        source = base / name
        if source.is_file():
            target = output / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(normalized(source.read_bytes()))
    for step in ['production'] + (['playable'] if profile == 'playable' else []):
        manifest = load(step)
        patch = HERE / 'profiles' / step / 'source.patch'
        assert digest(patch.read_bytes()) == manifest['patch_sha256'], 'Patch digest changed'
        subprocess.run(['git', 'apply', '--check', str(patch)], cwd=output, check=True, env={**os.environ, 'GIT_CEILING_DIRECTORIES': str(output.parent)})
        subprocess.run(['git', 'apply', str(patch)], cwd=output, check=True, env={**os.environ, 'GIT_CEILING_DIRECTORIES': str(output.parent)})
    manifest = load(profile)
    for name, mode in manifest['newline_modes'].items():
        path = output / name
        path.write_bytes(restore_newlines(path.read_bytes(), mode))
    count = verify(output, profile)
    if runtime:
        # Only upstream templates and reviewed gameplay overrides, never a player database.
        for part in ['conf', 'db', 'npc', 'sqlite-files', 'sql-files']:
            if (base / part).is_dir():
                shutil.copytree(base / part, output / part)
        for part in ['conf', 'db']:
            templates = output / part / 'import-tmpl'
            if templates.is_dir():
                shutil.copytree(templates, output / part / 'import', dirs_exist_ok=True)
        runtime_manifest = json.loads((HERE / 'profiles' / profile / 'runtime-manifest.json').read_text())
        for name, entry in runtime_manifest.items():
            if 'template' in entry:
                data = normalized((base / entry['template']).read_bytes())
                if entry['crlf']:
                    data = data.replace(b'\n', b'\r\n')
            else:
                data = (HERE / 'profiles' / entry['override_profile'] / 'runtime' / name).read_bytes()
            assert digest(data) == entry['sha256'], name
            target = output / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    (output / 'BASELINE-PROFILE.json').write_text(json.dumps({
        'profile': profile, 'base_commit': manifest['base_commit'],
        'verified_source_files': count, 'runtime_templates': runtime,
        'player_database_included': False}, indent=2) + '\n')
    return count

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', choices=['production', 'playable'])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--base', type=Path, default=REPO / 'swift-rathena')
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--with-runtime-templates', action='store_true')
    args = parser.parse_args()
    count = verify(args.output.resolve(), args.profile) if args.verify else prepare(
        args.output.resolve(), args.profile, args.base.resolve(), args.with_runtime_templates)
    print(json.dumps({'profile': args.profile, 'verified_source_files': count}))

if __name__ == '__main__':
    main()
