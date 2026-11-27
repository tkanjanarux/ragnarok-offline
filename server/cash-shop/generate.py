#!/usr/bin/env python3
"""Generate isolated-review bundle definitions. Does not edit live files."""
import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent

def generate(output):
    specs = json.loads((HERE / 'candidate-bundles.json').read_text())
    ids = set()
    items, cash = [], []
    for sku in specs:
        ident = sku['item_id']
        assert ident not in ids and sku['price_cash'] > 0
        ids.add(ident)
        components = sku['components']
        assert 0 < len(components) <= 32
        assert len({c['item_id'] for c in components}) == len(components)
        assert all(0 < c['quantity'] <= 30000 and c['item_id'] != ident for c in components)
        args = ','.join(str(x) for c in components for x in [c['item_id'], c['quantity']])
        # Only integers and escaped authored labels enter the script. Inventory
        # validation and consumption happen inside one synchronous server call.
        title = json.dumps(sku['name'], ensure_ascii=False)
        details = '\n'.join('mes '+json.dumps(str(c['quantity'])+' x '+c['aegis_name'])+';' for c in components)
        script = f'''disable_items;
mes {title};
{details}
mes "One pack is consumed only when every listed item fits.";
if (select("Open pack:Cancel") != 1) close;
if (!catalogue_exchange({ident},{args})) {{
    mes "Cannot open: check pack ownership, weight, stack limits and free slots. Nothing was consumed.";
    close;
}}
mes "Pack opened.";
close;
'''
        items.append(dict(Id=ident,AegisName=sku['aegis_name'],Name=sku.get('server_name',sku['name']),Type='DelayConsume',Weight=10,
            Trade=dict(NoDrop=True,NoTrade=True,NoSell=True,NoCart=True,NoGuildStorage=True,NoMail=True,NoAuction=True),Script=script))
        cash.append(dict(Item=sku['aegis_name'],Price=sku['price_cash']))
    output.mkdir(parents=True, exist_ok=False)
    # JSON is a YAML subset supported by the server reader; no host PyYAML needed.
    (output/'item_db.yml').write_text(json.dumps(dict(Header=dict(Type='ITEM_DB',Version=3),Body=items),indent=2)+'\n')
    (output/'item_cash.yml').write_text(json.dumps(dict(Header=dict(Type='ITEM_CASH_DB',Version=1),Body=[dict(Tab='Other',Items=cash)]),indent=2)+'\n')
    (output/'REVIEW-ONLY').write_text('Generated candidates. Integration and sale approval ledger are not yet complete. Never replace existing import files; merge reviewed entries.\n')
    return len(items)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    print(json.dumps({'candidate_skus':generate(args.output),'live_deployed':False}))
