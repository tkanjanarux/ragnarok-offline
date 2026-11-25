"""Run the existing farm fixture with read-only, synchronous boundary probes."""
from pathlib import Path

source=Path('/tests/check_farming_rate.py').read_text()
boundary=r'''
OnMark:
 .@label$=.@atcmd_parameters$[0];
 debugmes "B_MARK "+.@label$+" "+BaseLevel+" "+BaseExp+" "+JobLevel+" "+JobExp;
 .@n=query_sql("select profile_id,nameid,amount from ragoff_companion_supply union all select id,-717,gems from ragoff_companion",.@pid,.@item,.@amount);
 for(.@i=0;.@i<.@n;.@i++)debugmes "B_STOCK "+.@pid[.@i]+" "+.@item[.@i]+" "+.@amount[.@i];
 query_sql("select coalesce(max(rowid),0) from brain_stock",.@row);
 debugmes "B_INDEX "+.@row;
 for(.@i=0;.@i<5;.@i++){
   .@id=.@i ? 95000000+.@i-1 : 2000001;
   if(attachrid(.@id)){
     getmapxy .@map$,.@x,.@y,BL_PC;
     debugmes "B_COUNTER "+.@id+" "+readparam(PC_DIE_COUNTER)+" "+.@x+" "+.@y;
     detachrid;
   }
 }
 debugmes "B_BOUND "+.@label$;
 end;
'''
import os
if os.getenv('BRAIN_FIVE')=='1':
    boundary=boundary.replace('.@i<5','.@i<6')
source=source.replace(' bindatcmd "farmobs"', ' bindatcmd "brainmark",strnpcinfo(3)+"::OnMark",99,99;\n bindatcmd "farmobs"').replace('OnObs:',boundary+'\nOnObs:')
source=source.replace("before=stock()",'''f.db.executescript("""
CREATE TABLE brain_stock(profile INTEGER,item INTEGER,change INTEGER,ms INTEGER DEFAULT (round((julianday('now')-2440587.5)*86400000)));
CREATE TRIGGER brain_supply_change AFTER UPDATE OF amount ON ragoff_companion_supply
BEGIN INSERT INTO brain_stock(profile,item,change) VALUES(new.profile_id,new.nameid,new.amount-old.amount); END;
CREATE TRIGGER brain_supply_new AFTER INSERT ON ragoff_companion_supply
BEGIN INSERT INTO brain_stock(profile,item,change) VALUES(new.profile_id,new.nameid,new.amount); END;
CREATE TRIGGER brain_supply_del AFTER DELETE ON ragoff_companion_supply
BEGIN INSERT INTO brain_stock(profile,item,change) VALUES(old.profile_id,old.nameid,-old.amount); END;
CREATE TRIGGER brain_gem AFTER UPDATE OF gems ON ragoff_companion WHEN old.gems != new.gems
BEGIN INSERT INTO brain_stock(profile,item,change) VALUES(new.id,-717,new.gems-old.gems); END;
""")
before=stock()''')
source=source.replace('start=time.monotonic()',"""query('@brainmark start','B_BOUND start')
start=time.monotonic()""").replace('after=stock()',"""query('@brainmark end','B_BOUND end')
print('LEDGER',json.dumps(f.db.execute('select rowid,* from brain_stock order by rowid').fetchall()),flush=True)
after=stock()""")
# Optional positive control in its own disposable container. The fixture injects
# two deaths after the normal AI takes its puller beyond the owner's sight.
import os
if os.getenv('BRAIN_POSITIVE_CONTROL')=='1':
    boundary_hook=r'''
 if(!.brain_done && atoi(.@atcmd_parameters$[0])==2){
   getmapxy .@pm$,.@px,.@py,BL_PC,.@atcmd_parameters$[1];
   if(max(max(.@px-.@x,.@x-.@px),max(.@py-.@y,.@y-.@py))>getbattleflag("area_size")+2){
     .brain_done=1;
     debugmes "B_CONTROL "+.@px+" "+.@py+" "+.@x+" "+.@y+" "+getbattleflag("area_size");
     unitkill 95000000;
     unitkill 95000002;
   }
 }
'''
    source=source.replace(' .@r=atoi',boundary_hook+' .@r=atoi')
if os.getenv('BRAIN_FAR_EXP')=='1':
    # Independent peer starts one ordinary auto-attack during setup. Once the
    # window opens both clients only observe, including the stationary owner.
    peer_setup=r'''
import socket
peer=login('/stage/peer-fixture.json')
peer.command('@set BaseLevel 88')
peer.command('@set Vit 90')
peer.command('@set Str 70')
peer.command('@set Dex 70')
c.send(struct.pack('<HI',0xfc,2000002))
peer.s.settimeout(.25)
end_invite=time.monotonic()+2
while time.monotonic()<end_invite:
    try:op,b=peer.packet()
    except socket.timeout:continue
    if op==0x2c6:peer.send(struct.pack('<HIB',0x2c7,struct.unpack_from('<I',b,2)[0],1))
peer.s.settimeout(10)
'''
    source=source.replace("puller=os.environ.get('FARM_PULLER')",peer_setup+"\npuller=os.environ.get('FARM_PULLER')")
    far_setup=r'''
positions=json.loads(layout.read_text())[1]
far_x,far_y=max(((x,y) for x in range(max(anchor[0]-35,2),min(anchor[0]+36,width-2)) for y in range(max(anchor[1]-35,2),min(anchor[1]+36,height-2)) if 22<=max(abs(x-anchor[0]),abs(y-anchor[1]))<=35 and all(cells[(y+j)*width+x+i]==0 for i in (-1,0,1) for j in (-1,0,1))),key=lambda xy:min(max(abs(xy[0]-mx),abs(xy[1]-my)) for _,_,mx,my in positions))
warp(peer,f'{field} {far_x} {far_y}')
peer.command('@heal')
c.send(struct.pack('<HI',0x102,1))
training=stage/'npc/custom/qa_far_exp.txt'
training.write_text('-\tscript\tQA Far Credit\t-1,{\nOnInit:\n monster "'+field+'",'+str(far_x)+','+str(far_y)+',"Far Poring",1002,1;\n .@m=$@mobid[0];\n setunitdata .@m,UMOB_MAXHP,1000;\n setunitdata .@m,UMOB_HP,1000;\n debugmes "B_PORING "+.@m; end;\n}\n')
msg=query('@loadnpc npc/custom/qa_far_exp.txt','B_PORING ')
target=int(re.search(r'B_PORING (\d+)',msg)[1])
aid,_=entry('clif_parse_ActionRequest')
peer.send(struct.pack('<HIB',aid,target,7))
'''
    source=source.replace("query('@brainmark start'",far_setup+"\nquery('@brainmark start'")
exec(compile(source,'/tests/check_farming_rate.py','exec'))
