#!/usr/bin/env python3
"""Render the full requirement ledger without treating an audit as an effect test."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[2]
folder = root / 'docs/cash-shop-full-catalogue'
rows = json.loads((folder / 'coverage.json').read_text())
assert [r['request'] for r in rows] == list(range(1, 89))
lines = ['# Cash Shop: all 88 requirements', '',
         '85 requirements have implementation and enumerated isolated tests; 11/12 are explicit potion adaptations; 88 is excluded. Live catalogue remains unchanged.', '',
         'Ready means ready for deployment review, not exhaustive testing or device acceptance. See [limits and usage](README.md), [deployment plan](SERVER-DELIVERY.md), and [full specifications/evidence](coverage.json).', '',
         '| # | Requirement | Exact sale ID / AegisName / Cash | Status | Effect evidence / limitation |',
         '|---|---|---|---|---|']
for r in rows:
    label = '; '.join(f"{s['item_id']} {s['aegis_name']} ({s['price_cash']})" for s in r.get('catalogue_variants', [])) or 'Excluded; no sale SKU'
    evidence = ', '.join(f'[{name.removesuffix("-evidence.json")}]({name})' for name in r.get('effect_references', []))
    remaining = r.get('blocker') or (r.get('mapping_note', '') + ' ' + evidence).strip()
    cells = [str(r['request']),r['proposal'],label,r['status'],remaining]
    lines.append('| ' + ' | '.join(c.replace('|','/').replace('\n',' ') for c in cells) + ' |')
lines += ['', 'Device visual/hardware acceptance is unverified for every row. No Simulator is required.',
          'Quantities, components, service policy, variant choice, restrictions, assets and transaction evidence are in coverage.json and candidate specifications. Prices use local virtual Cash; no live grants/charges occurred.', '']
(folder/'COVERAGE.md').write_text('\n'.join(lines))
