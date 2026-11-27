#!/usr/bin/env python3
"""Review-only service voucher definitions; each keeps the voucher on cancel."""
import argparse,json
from pathlib import Path
HERE=Path(__file__).resolve().parent

def script(s):
    ident=s['item_id']
    header='disable_items;\nmes '+json.dumps(s['name'])+';\n'
    stock=f'if (countitem({ident}) < 1) {{ mes "Voucher unavailable."; close; }}\n'
    if 'mode' in s:
        return header+'''mes "Use in town, with carried weight zero and no mount, falcon or cart.";
mes "Refunds spent points; keeps quest/permanent skills and unspent/bonus points. Traits are unchanged.";
mes "Nothing is consumed on cancel, invalid conditions or an empty build.";
if (select("Confirm reset:Cancel") != 1) close;
'''+stock+f'''if (!catalogue_reset({ident},{s['mode']})) {{
    mes "Cannot reset under current conditions, or there are no spent points to reset.";
    close;
}}
mes "Reset completed.";
close;
'''
    if s['service']=='card_removal':
        return header+'''mes "Portable Wise Old Woman policy: 200,000 Zeny + 25,000 per card, one Star Crumb and one Yellow Gemstone.";
mes "90% success; 2% destroys item AND cards; 6% destroys the unprotected side; 2% keeps both but spends all fees.";
mes "One voucher is also consumed for any completed attempt. Cancel or invalid conditions costs nothing.";
mes "Permanent equipped items only; special forged/pet items, rentals, switch-set items and unequip scripts are not supported.";
setarray .@slots[0],EQI_HEAD_TOP,EQI_ARMOR,EQI_HAND_L,EQI_HAND_R,EQI_GARMENT,EQI_SHOES,EQI_ACC_L,EQI_ACC_R,EQI_HEAD_MID,EQI_HEAD_LOW;
.@choice = select("Upper head:Armour:Left hand:Right hand:Garment:Shoes:Left accessory:Right accessory:Middle head:Lower head:Cancel");
if (.@choice == 11) close;
.@slot = .@slots[.@choice-1];
if (!getequipisequiped(.@slot) || getequipcardcnt(.@slot) < 1) { mes "No carded equipment in that slot. Voucher kept."; close; }
.@item = getequipid(.@slot);
.@refine = getequiprefinerycnt(.@slot);
for (.@i=0; .@i<4; ++.@i) .@card[.@i] = getequipcardid(.@slot,.@i);
mes getequipname(.@slot);
mes "Fee: " + (200000+25000*getequipcardcnt(.@slot)) + " Zeny, 1 Star Crumb, 1 Yellow Gemstone and 1 voucher.";
mes "Which side should survive the 6% partial failure? The 2% total failure can still destroy both.";
.@protect = select("Protect equipment:Protect cards:Cancel");
if (.@protect == 3) close;
if (select("Accept risks and attempt:Cancel") != 1) close;
'''+stock+f'''.@result = catalogue_remove_cards({ident},.@slot,.@item,.@refine,.@card[0],.@card[1],.@card[2],.@card[3],.@protect);
if (.@result == 0) mes "Cannot proceed: check unchanged eligible equipment, money, materials, weight and inventory space. Nothing consumed.";
else if (.@result == 1) mes "Success. Cards and equipment returned separately. Refinement and other item attributes are retained.";
else if (.@result == 2) mes "Total failure: equipment and cards destroyed. Fees and voucher consumed.";
else if (.@result == 3) mes "Partial failure: equipment retained, cards destroyed. Fees and voucher consumed.";
else if (.@result == 4) mes "Partial failure: cards retained, equipment destroyed. Fees and voucher consumed.";
else mes "Failed to remove cards. Equipment and cards unchanged; fees and voucher consumed.";
close;
'''
    if s['service']=='style':
        look=s['look']; lo=s['minimum']; hi=s['maximum']
        flag={'LOOK_HAIR':'hair_style','LOOK_HAIR_COLOR':'hair_color','LOOK_CLOTHES_COLOR':'cloth_color'}[look]
        # Audit covers classic and rebirth human jobs. No unverified Doram/body palettes.
        jobs=','.join(str(j) for j in list(range(22))+list(range(4001,4023)))
        return header+f'''setarray .@jobs[0],{jobs};
if (inarray(.@jobs,Class) < 0) {{ mes "This voucher supports classic and rebirth human jobs only. Voucher kept."; close; }}
if ({look} != LOOK_HAIR && (getlook(LOOK_HAIR) < 1 || getlook(LOOK_HAIR) > 42)) {{ mes "Choose a supported hairstyle first. Voucher kept."; close; }}
.@min = max({lo},getbattleflag("min_{flag}"));
.@max = min({hi},getbattleflag("max_{flag}"));
if (.@min > .@max) {{ mes "No supported styles are enabled on this server. Voucher kept."; close; }}
mes "Choose a style number from " + .@min + " to " + .@max + ". Nothing changes until confirmation.";
input .@value,.@min,.@max;
mes "Apply style number " + .@value + "?";
if (select("Apply:Cancel") != 1) close;
'''+stock+f'''if (.@value < .@min || .@value > .@max || getlook({look}) == .@value) {{ mes "No change needed. Voucher kept."; close; }}
setlook {look},.@value;
delitem {ident},1;
mes "Appearance updated.";
close;
'''
    if s['service']=='gym':
        return header+'''mes "One permanent Enlarge Weight Limit level per voucher, maximum 10. Existing training is retained.";
if (select("Train:Cancel") != 1) close;
'''+stock+f''' .@level = max(gympassmemory,getskilllv("ALL_INCCARRY"));
if (.@level >= 10) {{ mes "Training is already at its limit. Voucher kept."; close; }}
delitem {ident},1;
gympassmemory = .@level + 1;
skill "ALL_INCCARRY",gympassmemory,SKILL_PERM_GRANT;
mes "Training completed.";
close;
'''
    if s['service']=='repair':
        return header+'''mes "Repairs all broken equipment in your inventory. No additional materials. Cards and refinement stay unchanged.";
if (select("Repair:Cancel") != 1) close;
'''+stock+f'''if (!getbrokenid(1)) {{ mes "No broken equipment. Voucher kept."; close; }}
repairall;
delitem {ident},1;
mes "Equipment repaired.";
close;
'''
    if s['service']=='rename_credit':
        return header+'''mes "Activate one saved rename credit, then use Rename on the character selection screen.";
mes "Cancelling name entry or a rejected name keeps the credit. No second voucher is needed.";
mes "Server name, party and guild restrictions still apply.";
if (select("Activate credit:Cancel") != 1) close;
'''+stock+f'''if (CharRename > 0) {{ mes "A rename credit is already available. Voucher kept."; close; }}
CharRename = 1;
delitem {ident},1;
mes "Rename credit activated. Return to character selection to choose a name.";
close;
'''
    raise ValueError(s)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    specs=json.loads((HERE/'candidate-services.json').read_text());items=[]
    for s in specs:
        items.append(dict(Id=s['item_id'],AegisName=s['aegis_name'],Name=s['name'],Type='DelayConsume',Weight=0,Trade=dict(NoDrop=True,NoTrade=True,NoSell=True,NoCart=True,NoGuildStorage=True,NoMail=True,NoAuction=True),Script=script(s)))
    (a.output/'item_db.yml').write_text(json.dumps(dict(Header=dict(Type='ITEM_DB',Version=3),Body=items),indent=2)+'\n')
    (a.output/'item_cash.yml').write_text(json.dumps(dict(Header=dict(Type='ITEM_CASH_DB',Version=1),Body=[dict(Tab='Other',Items=[dict(Item=s['aegis_name'],Price=s['price_cash']) for s in specs])]),indent=2)+'\n')
    print(json.dumps(dict(candidate_services=len(specs),live_deployed=False)))
