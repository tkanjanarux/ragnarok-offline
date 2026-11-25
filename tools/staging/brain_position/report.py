"""Write stratified paired results from completed native windows."""
from pathlib import Path
from collections import Counter,defaultdict
import re,json,sys
root=Path(sys.argv[1]);rows=json.loads((root/'normal.json').read_text())
def agg(keys):
    c=Counter()
    for k in keys:
        r=rows[k]; c.update({i:r[i] for i in ('base','job','seconds','SG','tagged','arrived')})
        m=r['metrics'];c.update(m)
        c['stop']+=bool(r['stops']);c['owner_deaths']+=r['deaths'].get('2000001',0);c['other_deaths']+=sum(r['deaths'].values())-r['deaths'].get('2000001',0)
        c['dmg']+=sum(r['damage'].values());c['wizdmg']+=r['damage'].get('95000002',0);c['sp']+=sum(r['sp'].values())
        c.update({'item'+i:n for i,n in r['used'].items()})
        for i,h in r['healing'].items():
            for key,n in h.items():
                c['all_'+key]+=n
                if i=='95000004':c['camp_'+key]+=n
        c['unrecovered']+=any(x[0]<x[1]*.7 for x in r['last'].values())
        c['arrows']+=sum(r['used'].get(i,0) for i in ('1750','1754'))
        c['n']+=1
    c['rate']=round(c['base']*600/c['seconds'])
    return c
def mdrow(*cols):return '| '+' | '.join(map(str,cols))+' |'
def rr(x):return round(x,1)
text=[];totals={}
for rad in ('6','96'):
    text+=['## '+('ขอบ 4 ช่อง' if rad=='6' else 'รัศมี 96 ช่อง'),'',
          mdrow('แผนที่ / คนลาก','คู่','EXP เดิม / ปรับ ต่อ 10 นาที','ส่วนต่าง','คู่ที่ปรับได้มากกว่า','ช่วงส่วนต่างรายคู่ / 10 นาที','เที่ยวออก–กลับ เดิม / ปรับ','หยุด เดิม / ปรับ'), '|---|---:|---:|---:|---:|---:|---|---:|']
    for field,role in [('07','knight'),('07','priest'),('09','knight'),('09','priest'),('*','*')]:
        keys=[k for k in rows if k.split('-')[0]==rad and k.endswith('native') and (field=='*' or k.split('-')[1:3]==[field,role])]
        aa,bb=agg(keys),agg([k.replace('native','moved') for k in keys]);diff=[]
        for k in keys:
            a,b=rows[k],rows[k.replace('native','moved')]
            assert a['anchor']==b['anchor']
            assert a['build'].keys()==b['build'].keys()
            assert a['gear']==b['gear'],(k,'equipment')
            diff.append(round(600*(b['base']/b['seconds']-a['base']/a['seconds'])))
        text.append(mdrow('รวม' if role=='*' else field+' / '+role,len(keys),f"{aa['rate']:,} / {bb['rate']:,}",f"{bb['rate']-aa['rate']:+,}",sum(v>0 for v in diff),f"{min(diff):+,} ถึง {max(diff):+,}",f"{aa['outward']:.0f}–{aa['returned']:.0f} / {bb['outward']:.0f}–{bb['returned']:.0f}",f"{aa['stop']} / {bb['stop']}"))
        if field=='*':totals[rad]={'native':aa,'moved':bb}
    text+=['',mdrow('ค่ารวมทั้งสองแผนที่ / คนลาก','เดิม','ปรับตำแหน่ง'),'|---|---:|---:|']
    for title,key in [('วินาทีรวม','seconds'),('Base EXP สุทธิ','base'),('Job EXP สุทธิ','job'),('มอนที่เห็นตามจากไกลเข้าค่าย','arrived'),('Storm Gust ที่ลงจริง','SG'),('HP เสียจากการโจมตีทั้งทีม','dmg'),('HP เสียจากการโจมตี Wizard','wizdmg'),('HP จาก Heal ทั้งทีม','all_restored'),('Heal ของ Priest ค่าย ครั้ง','camp_heal'),('HP จาก Heal ของ Priest ค่าย','camp_restored'),('HP ที่ Priest ค่าย Heal ให้ Wizard','camp_wiz_hp'),('Kyrie ของ Priest ค่าย ครั้ง','camp_kyrie'),('ผลรวมความจุโล่ตอนสกิลออก','camp_shield_capacity'),('เวลาที่ทั้ง Wizard/Priest ค่ายมีชีวิตก่อนหยุด (วิ.)','both_alive_pre_s'),('Wizard อยู่นอกระยะ Heal ขณะทั้งคู่มีชีวิตก่อนหยุด (วิ.)','wiz_out_before_stop_s'),('Wizard ต้องฮีลขณะทั้งคู่มีชีวิตก่อนหยุด (วิ.)','urgent_alive_pre_s'),('ในเวลาที่ต้องฮีลและฮีลไม่ถึง (วิ.)','urgent_out_pre_s'),('คนลากอยู่นอกระยะ Heal ค่าย (วิ.)','pull_unreachable_s'),('ลงเดินเปลี่ยนตำแหน่งค่ายตามกติกาใหม่ ครั้ง','moves'),('เวลาหลังหยุด (วิ.)','after_stop_s'),('เจ้าของตาย','owner_deaths'),('companion ตาย','other_deaths'),('รอบที่จบมีคน HP <70%','unrecovered'),('SP ที่หักจริง','sp'),('White Syrup','item11623'),('Blue Syrup','item11624'),('Blue Gemstone','item717'),('ลูกธนู','arrows')]:
        text.append(mdrow(title,rr(aa[key]),rr(bb[key])))
    text+=['']
(root/'comparison.md').write_text('# ผลแยกตามรัศมี แผนที่ และบทบาท\n\n'+'\n'.join(text)+'\n')
(root/'totals.json').write_text(json.dumps(totals,indent=2)+'\n')
db={}
for p in Path('companion-dev/db/re').glob('item_db_*.yml'):
    for item,name in re.findall(r'(?m)^  - Id: (\d+)\n    AegisName: [^\n]+\n    Name: (.+)',p.read_text()):db[int(item)]=name
part=['# ทีมตอนเริ่มรอบฟาร์ม','', 'ทุกตัว Base 88 / Job 47 ตัวเลขแต่ละคอลัมน์เป็นค่าต่ำสุด–สูงสุดของแต่ละค่าที่ map server อ่านตอนเริ่มวัดจากทุกรอบและทั้งสองบทบาท กรณี Priest 1 เปลี่ยน build ทำให้ความจุ HP/SP เปลี่ยน ดูค่าแยกรายรอบใน normal.json','',mdrow('สมาชิก','HP ปัจจุบัน / สูงสุด','SP ปัจจุบัน / สูงสุด','Heal / Kyrie','ของที่สวมจริง'),'|---|---|---|---|---|']
for i,name in zip(['2000001',*[str(i) for i in range(95000000,95000005)]],['เจ้าของ Hunter','Priest 1 · support / mobber','Knight 2 · ดาบ','Wizard 3 · Storm','Hunter 4','Priest 5 · support ประจำค่าย']):
    samples=[r['first'][i] for r in rows.values()]
    span=lambda n:str(min(x[n] for x in samples)) if min(x[n] for x in samples)==max(x[n] for x in samples) else f'{min(x[n] for x in samples)}–{max(x[n] for x in samples)}'
    gear=sorted({(g[0],g[2]) for r in rows.values() for g in r['gear'].get(i,[])})
    ranks=sorted({tuple(r['build'][i][-2:]) for r in rows.values()})
    part.append(mdrow(name,span(0)+' / '+span(1),span(2)+' / '+span(3),', '.join(f'{a}/{b}' for a,b in ranks),', '.join((('+'+str(ref)+' ') if ref else '')+db.get(id,str(id)) for id,ref in gear)))
(root/'team.md').write_text('\n'.join(part)+'\n')
