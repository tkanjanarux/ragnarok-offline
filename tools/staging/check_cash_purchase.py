import pathlib,struct,time,json,sqlite3
from protocol import login,TABLE
from check_m4_skills import wait
assert pathlib.Path('/stage/STAGING_ONLY').exists()
for id,n in [(0x8ca,-1),(0xb6e,14),(0x849,16)]:TABLE[str(id)]={'length':n}
c=login();c.command('@reloadcashdb');time.sleep(.5);c.command('@cash 10000');time.sleep(.5)
c.send(struct.pack('<H',0x8c9));tabs={}
end=time.monotonic()+15
while time.monotonic()<end:
 i,b=c.packet()
 if i==0x8ca:
  count,tab=struct.unpack_from('<HH',b,4)
  tabs.setdefault(tab,[]).extend(struct.unpack_from('<II',b,8+n*8) for n in range(count))
  if len(tabs.get(6,[]))==27 and len(tabs.get(5,[]))==3 and len(tabs.get(4,[]))==4:break
assert len(tabs[6])==27 and len(tabs[5])==3 and len(tabs[4])==4,tabs
assert len(set(i for i,p in tabs[6]))==27
c.send(struct.pack('<HI',0xb6d,6));b=wait(c,lambda i,b:i==0xb6e)
points=struct.unpack_from('<I',b,2)[0]
# Buy a cheap existing potion in disposable fixture only.
c.send(struct.pack('<HHHIIIH',0x848,20,1,0,505,1,6))
b=wait(c,lambda i,b:i==0x849)
item,result,cash,kafra=struct.unpack_from('<IHII',b,2)
assert result==0 and cash==points-5,(result,cash,points)
c.send(struct.pack('<H',0x84a));c.close();time.sleep(2)
db=sqlite3.connect('file:/stage/ragoff-stage.sqlite3?mode=ro',uri=True)
assert db.execute('select sum(amount) from inventory where char_id=150001 and nameid=505').fetchone()[0]>=1
out={'catalog_count':sum(map(len,tabs.values())),'consumables_count':27,'pages_of_nine':3,'buy_blue_potion_success':True,'cash_deducted':5,'inventory_persisted':True}
pathlib.Path('/stage/artifacts/cash-purchase.json').write_text(json.dumps(out,indent=2));print(json.dumps(out))
