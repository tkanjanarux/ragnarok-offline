#!/usr/bin/env python3
"""Render the full requirement ledger without treating an audit as an effect test."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[2]
folder = root / 'docs/cash-shop-full-catalogue'
rows = json.loads((folder / 'coverage.json').read_text())
assert [r['request'] for r in rows] == list(range(1, 89))
lines = ['# Cash Shop: all 88 requirements', '',
         'Review candidates only. Live catalogue remains unchanged. A source/asset audit is not a purchase/use test.', '',
         '| # | Requirement | Exact candidate IDs / SKUs | Cash price proposal | Status | Remaining prerequisite |',
         '|---|---|---|---|---|---|']
for r in rows:
    ids = sorted({c['item_id'] for c in r['candidate_components']})
    label = ', '.join(map(str, ids)) or 'Not selected / service implementation required'
    if r.get('skus'): label += '; packs ' + ', '.join(map(str,r['skus']))
    price = ', '.join(map(str,r.get('proposed_cash_prices',[])))
    remaining = r.get('blocker') or ' / '.join(k for k,v in r['evidence'].items() if not v and k != 'device')
    cells = [str(r['request']),r['proposal'],label,price,r['status'],remaining]
    lines.append('| ' + ' | '.join(c.replace('|','/').replace('\n',' ') for c in cells) + ' |')
lines += ['', 'Device visual/hardware acceptance is unverified for every row. No Simulator is required.',
          'Prices remain review candidates until economic/conversion checks and actual item effect evidence are recorded.', '']
(folder/'COVERAGE.md').write_text('\n'.join(lines))
