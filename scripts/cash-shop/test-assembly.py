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

if __name__ == '__main__': unittest.main()
