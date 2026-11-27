#!/usr/bin/env python3
"""Regression tests for preserving imports and refusing unsafe catalogue merges."""
import copy
import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('assembly', Path(__file__).resolve().parents[2] / 'server/cash-shop/assemble.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class AssemblyTests(unittest.TestCase):
    def setUp(self):
        self.items = dict(Header=dict(Type='ITEM_DB', Version=3), Body=[dict(Id=569, Script='itemheal 44,0;')])
        self.cash = dict(Header=dict(Type='ITEM_CASH_DB', Version=1), Body=[dict(Tab='Consumables', Items=[dict(Item='Blue_Potion', Price=5)])])
        self.new = [dict(Id=2000010, AegisName='Pack', Script='close;')]
        self.add = [dict(Item='Pack', Price=900)]
    def test_preserves_overrides_tabs_and_inputs(self):
        original = copy.deepcopy((self.items, self.cash))
        items, cash, counts = m.merge(self.items, self.cash, self.new, self.add)
        self.assertEqual(items['Body'][0], original[0]['Body'][0])
        self.assertEqual(cash['Body'][0], original[1]['Body'][0])
        self.assertEqual((self.items, self.cash), original)
        self.assertEqual(counts, dict(preserved_cash_entries=1, added_cash_entries=1, custom_items=1))
    def test_existing_other_tab_not_duplicated(self):
        self.cash['Body'][0]['Tab'] = 'Other'
        _, cash, _ = m.merge(self.items, self.cash, self.new, self.add)
        self.assertEqual(len(cash['Body']), 1); self.assertEqual(len(cash['Body'][0]['Items']), 2)
    def test_reserved_id_collision(self):
        self.items['Body'] += self.new
        with self.assertRaises(AssertionError): m.merge(self.items, self.cash, self.new, self.add)
    def test_reprice_or_duplicate_rejected(self):
        for price in [5, 900]:
            with self.subTest(price=price), self.assertRaises(AssertionError):
                m.merge(self.items, self.cash, self.new, [dict(Item='Blue_Potion', Price=price)])
    def test_duplicate_additions_rejected(self):
        with self.assertRaises(AssertionError): m.merge(self.items, self.cash, self.new, self.add * 2)
    def test_invalid_prices_rejected(self):
        for price in [0, -1, .5, 2147483648]:
            with self.subTest(price=price), self.assertRaises(AssertionError):
                m.merge(self.items, self.cash, self.new, [dict(Item='Pack', Price=price)])

class BundleAliasTests(unittest.TestCase):
    def run_generator(self, changed=False, cycle=False):
        import tempfile
        import json
        source = Path(__file__).resolve().parents[2] / 'server/cash-shop/generate.py'
        spec = importlib.util.spec_from_file_location('bundles', source)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        base = dict(item_id=2000270, aegis_name='Canonical', name='Food', price_cash=90,
                    components=[dict(item_id=12045, aegis_name='Str_Dish05', quantity=10)])
        alias = copy.deepcopy(base); alias.update(item_id=2000330, aegis_name='Alias', alias_of=2000270)
        if changed: alias['components'][0]['quantity'] = 20
        if cycle: base['alias_of'] = 2000330
        with tempfile.TemporaryDirectory() as directory:
            module.HERE = Path(directory)
            (module.HERE / 'candidate-bundles.json').write_text(json.dumps([base, alias]))
            output = module.HERE / 'generated'; module.generate(output)
            return json.loads((output / 'item_db.yml').read_text()), json.loads((output / 'item_cash.yml').read_text())
    def test_alias_keeps_usable_definition_but_lists_only_canonical(self):
        items, cash = self.run_generator()
        self.assertEqual([x['Id'] for x in items['Body']], [2000270, 2000330])
        self.assertEqual(cash['Body'][0]['Items'], [dict(Item='Canonical', Price=90)])
    def test_different_contents_cannot_be_hidden_as_alias(self):
        with self.assertRaises(AssertionError): self.run_generator(changed=True)
    def test_alias_cycles_rejected(self):
        with self.assertRaises(AssertionError): self.run_generator(cycle=True)

if __name__ == '__main__': unittest.main()
