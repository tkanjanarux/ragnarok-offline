"""Drive genuine progression, injury, death and a native card award."""
from companion_ai_fixture import setup, attack, wait, stage
from bird_fixture import BirdFixture
import re,struct,time

c,profiles=setup(7)
f=BirdFixture(c)
knight=profiles[7]
actor=knight['actor']
f.db.execute("insert into ragoff_companion_supply select id,owner_char,501,25 from ragoff_companion where id=?",(knight["id"],))
assert f.note('talk chatty')=='Team speech: chatty'
def hear(*phrases,seconds=16):
    def expected(i,b):
        return i==0x8d and struct.unpack_from('<I',b,4)[0]==actor and any(p.encode() in b[8:] for p in phrases)
    b=wait(c,expected,seconds)
    print('PASS',b[8:].rstrip(b'\0').decode(),flush=True)
c.command('@set BaseLevel 86')
hear('เลเวล','เก่งขึ้น')
c.command(f'#set {knight["name"]} Hp 5')
hear('ข้ายังยืนไหว','ช่วยดูแผลให้ข้า','แนวหน้าขอฮีล')
c.command(f'#die {knight["name"]}')
hear('ล้มซะแล้ว','ฝากที่เหลือ','ขอนอน')
c.command(f'#alive {knight["name"]}')
hear('ลุกไหวแล้ว','ขอบคุณที่ช่วย','กลับมาแล้ว')
# Configure only the test server with a guaranteed Poring Card.
c.command('@setbattleflag item_drop_card_max 10000')
c.command('@setbattleflag item_drop_card_min 10000')
path=stage/'npc/custom/qa_speech_drop.txt'
path.write_text("""-	script	QA Speech Drop	-1,{
OnInit: bindatcmd "speechdrop",strnpcinfo(3)+"::OnDrop",99,99; end;
OnDrop:
 monster "prontera",151,180,"Card QA",1002,1;
 .@id=$@mobid[0];
 setunitdata .@id,UMOB_MODE,MD_NOCAST;
 unitwarp .@id,"prontera",151,180;
 setunitdata .@id,UMOB_HP,1;
 debugmes "SPEECH_MOB "+.@id;
 end;
}
""")
c.command('@loadnpc npc/custom/qa_speech_drop.txt')
wait(c,lambda i,b:i==0x8e and b'Script loaded' in b)
c.command('@autoloot 100')
c.command('@setbattleflag min_hitrate 100')
c.command('@heal')
log=stage/'artifacts/map-server.log'
offset=log.stat().st_size
c.command('@speechdrop')
for attempt in range(40):
    match=re.search(rb'SPEECH_MOB (\d+)',log.read_bytes()[offset:])
    if match: break
    time.sleep(.1)
assert match
target=int(match[1])
attack(c,target)
hear('ได้การ์ด','การ์ดเข้าเป้า',seconds=30)
assert f.db.execute('select count(*) from ragoff_companion_gear where nameid=4001').fetchone()==(0,)
print('PASS actual monster card autoloot announces on owner team',flush=True)
c.close()
