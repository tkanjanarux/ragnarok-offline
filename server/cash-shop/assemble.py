#!/usr/bin/env python3
"""Assemble review-only imports without editing a prepared tree or live server.

Requires PyYAML. Always preserves existing cash entries and import overrides.
Generated files are candidates, not a declaration that all effects were tested.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import yaml

HERE = Path(__file__).resolve().parent


def merge(existing_items, existing_cash, new_items, additions):
    items, cash = copy.deepcopy(existing_items), copy.deepcopy(existing_cash)
    assert items['Header']['Type'] == 'ITEM_DB'
    assert cash['Header']['Type'] == 'ITEM_CASH_DB'
    current = items.setdefault('Body', []) or []
    ids = {item['Id'] for item in current}
    names = {item.get('AegisName') for item in current}
    for item in new_items:
        assert 2000000 <= item['Id'] < 2000999, 'custom ID outside reserved range'
        assert item['Id'] not in ids and item['AegisName'] not in names, 'item collision'
        ids.add(item['Id']); names.add(item['AegisName'])
        current.append(copy.deepcopy(item))
    items['Body'] = current
    tabs = cash.setdefault('Body', [])
    prices = {}
    for tab in tabs:
        for item in tab['Items']:
            assert item['Item'] not in prices, 'duplicate existing cash item'
            prices[item['Item']] = item['Price']
    original_count = len(prices)
    new = []
    for item in additions:
        assert isinstance(item['Price'], int) and 0 < item['Price'] <= 2147483647
        assert item['Item'] not in prices, 'duplicate/repriced cash item'
        prices[item['Item']] = item['Price']
        new.append(copy.deepcopy(item))
    other = next((tab for tab in tabs if tab['Tab'] == 'Other'), None)
    if other is None:
        other = dict(Tab='Other', Items=[]); tabs.append(other)
    other['Items'].extend(new)
    return items, cash, dict(preserved_cash_entries=original_count,
                            added_cash_entries=len(new), custom_items=len(new_items))


def assemble(prepared, output):
    assert not output.exists(), 'output must be new; never overwrite an import'
    overlay = json.loads((prepared / 'CASH-SHOP-OVERLAY.json').read_text())
    assert overlay['packetver'] == 20211103
    inputs = {name: prepared / 'db/import' / name for name in ['item_db.yml', 'item_cash.yml']}
    base = {name: yaml.safe_load(path.read_text()) for name, path in inputs.items()}
    definitions, additions = [], []
    with tempfile.TemporaryDirectory() as directory:
        for script in ['generate.py', 'generate-services.py']:
            dest = Path(directory) / script
            subprocess.run([sys.executable, str(HERE / script), '--output', str(dest)], check=True,
                           stdout=subprocess.DEVNULL)
            definitions += json.loads((dest / 'item_db.yml').read_text())['Body']
            additions += json.loads((dest / 'item_cash.yml').read_text())['Body'][0]['Items']
    for name in ['candidate-costumes.json', 'candidate-utilities.json', 'candidate-equipment.json']:
        additions += [dict(Item=s['aegis_name'], Price=s['price_cash'])
                      for s in json.loads((HERE / name).read_text())]
    # Check the reserved range against the actual prepared native item database,
    # not only the import file. These new definitions must not shadow a native ID.
    reserved = {i['Id'] for i in definitions}
    reserved_names = {i['AegisName'] for i in definitions}
    known = set()
    for path in (prepared / 'db').rglob('item_db*.yml'):
        db = yaml.safe_load(path.read_text()) or {}
        for item in db.get('Body', []) or []:
            assert item['Id'] not in reserved, f'ID collision in {path.name}'
            assert item.get('AegisName') not in reserved_names, f'name collision in {path.name}'
            if 'AegisName' in item: known.add(item['AegisName'])
    assert all(item['Item'] in known | reserved_names for item in additions), 'unknown native SKU'
    items, cash, counts = merge(base['item_db.yml'], base['item_cash.yml'], definitions, additions)
    output.mkdir(parents=True)
    for name, value in [('item_db.yml', items), ('item_cash.yml', cash)]:
        (output / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    manifest = dict(profile=overlay['profile'], packetver=overlay['packetver'], **counts,
                    base_import_sha256={name: digest(path) for name, path in inputs.items()},
                    generated_sha256={name: digest(output / name) for name in inputs},
                    live_deployed=False, sale_readiness='See per-requirement evidence ledger; review only')
    (output / 'MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'REVIEW-ONLY').write_text('Not live. Requires matching Char/Map, journal migration and deployment review.\n')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prepared', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(assemble(args.prepared.resolve(), args.output.resolve()), indent=2))
