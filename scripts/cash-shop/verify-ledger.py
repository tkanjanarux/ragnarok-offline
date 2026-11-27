#!/usr/bin/env python3
"""Check final sale IDs/prices against the 88-row ledger and recorded transaction cases.

This is evidence consistency validation, NOT a fresh gameplay/effect integration test.
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
docs = root / 'docs/cash-shop-full-catalogue'
read = lambda name: json.loads((docs / name).read_text())
rows = read('coverage.json')
assert [r['request'] for r in rows] == list(range(1, 89))
specs = []
for name in ['bundles', 'services', 'costumes', 'utilities']:
    specs += json.loads((root / f'server/cash-shop/candidate-{name}.json').read_text())
listed = {s['item_id']: s for s in specs if not s.get('alias_of')}
assert len(listed) == 123
aliases = {s['item_id'] for s in specs if s.get('alias_of')}
assert len(aliases) == 6 and not aliases & listed.keys()
covered = set()
for r in rows:
    if r['request'] == 88:
        assert r['status'] == 'blocked_excluded' and not r['skus'] and not r['candidate_ready']
        continue
    assert r['candidate_ready'] and not r['live_deployed'] and not r['sellable']
    assert not r['evidence']['device']
    assert r['proposed_cash_prices'] == [listed[i]['price_cash'] for i in r['skus']]
    assert r['catalogue_variants'] == [listed[i] for i in r['skus']]
    assert r['effect_references']
    for name in r['effect_references']:
        assert (docs / name).is_file(), name
    covered.update(r['skus'])
assert covered == listed.keys()
assert rows[10]['status'] == rows[11]['status'] == 'adapted_pending_deploy'

# Transaction-case identity, separate from component effect evidence in the ledger.
purchased = set()
for row in read('bundle-packet-evidence.json')['results'] + read('additional-bundle-packet-evidence.json'):
    assert row['purchase'] and row['cash_debit_once'] and row['open_exact_contents'] and row['reconnect_inventory_cash']
    purchased.add(row['item_id'])
for row in read('services-evidence.json')['tests']:
    assert row['purchase_debit_once'] and row['effect_persisted'] and row['reconnect']
    purchased.add(row['item_id'])
for row in read('styles-evidence.json')['tests']:
    assert row['buy_cancel_apply_reconnect']; purchased.add(row['item_id'])
for row in read('costumes-evidence.json'):
    assert row['cash_once'] and row['inventory_persisted'] and row['reconnect']
    purchased.add(row['item_id'])
for row in read('pet-packs-final-evidence.json'):
    assert row['cash_once'] and row['atomic_egg_food_voucher'] and row['reconnect']
    purchased.add(row['pack'])
# These fields record equip/feed/reconnect. The private packet harness bought
# Incubator and each accessory and asserted its configured Cash debit before use.
for row in read('pet-species-evidence.json'):
    assert row['accessory_equip'] and row['reconnect']
    purchased.update([643, row['accessory']])
wing = read('giant-wing-evidence.json')
assert wing['purchase_cash_once'] and wing['persisted']
purchased.add(wing['item_id'])
token = next(r for r in read('utilities-evidence.json') if r['item_id'] == 7621)
assert token['purchased_two'] and token['cash_once'] and token['persisted']
purchased.add(7621)
cards = read('card-outcomes-evidence.json')['cases']
assert len(cards) == 26 and all(c['cash_debit'] == 100 for c in cards)
purchased.add(2000460)
assert not listed.keys() - purchased, sorted(listed.keys() - purchased)
print(json.dumps(dict(requirements=88,listed_skus=123,transaction_case_ids_covered=123,
                      unlisted_aliases=6,effect_scope='See per-row evidence; not rerun by this script',
                      device_verified=False,live_deployed=False)))
