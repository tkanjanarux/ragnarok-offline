#!/usr/bin/env python3
"""Audit authored virtual-Cash unit consistency and deterministic pack discounts.
This checks prices/conversion values, not external economy or live player balances.
"""
import json
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
root = Path(__file__).resolve().parents[2]
specs = json.loads((root / 'server/cash-shop/candidate-bundles.json').read_text())
units = {}
for sku in specs:
    total = Decimal(0)
    for component in sku['components']:
        value = Decimal(str(component['unit_cash']))
        assert value > 0 and component['quantity'] > 0
        previous = units.setdefault(component['item_id'], value)
        assert previous == value, ('inconsistent component value', component['item_id'])
        total += value * component['quantity']
    price = int((total * Decimal('.9')).quantize(Decimal(1), rounding=ROUND_HALF_UP))
    assert sku['price_cash'] == price, (sku['item_id'], sku['price_cash'], price)
    assert 0 < sku['price_cash'] <= total
# Exact native Arrow Crafting output, also verified through actual skill packets.
for material, output, quantity in [(990, 1752, 600), (991, 1754, 150), (992, 1755, 150), (993, 1756, 150)]:
    assert units[material] == units[output] * quantity, ('conversion underpricing', material)
print(json.dumps(dict(bundle_skus=len(specs),consistent_component_values=len(units),
                      discount='10%, rounded to nearest virtual Cash',arrow_conversions_checked=4,
                      external_economy_claim=False)))
