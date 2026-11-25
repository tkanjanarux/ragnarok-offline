"""A separate, unpartied peer crosses the observed puller's intended path.
The fixture supplies monsters. Only the production AI controls companions."""
from pathlib import Path
base=Path('/tests/brain_stage1/fixture.py').read_text()
setup="""
peer=login('/stage/peer-fixture.json')
peer.command('@heal')
sent_scene=False
next_probe=10
peer_depart=0
"""
pulse="""
    elapsed=time.monotonic()-start
    if elapsed>next_probe:
        # A repeatable environmental HP deficit. The owner issues no combat order.
        c.command('@loadnpc npc/custom/qa_shadow_probe.txt') if next_probe==10 else None
        c.command('@shadowprobe')
        next_probe+=16
    if peer_depart and elapsed>=peer_depart:
        warp(peer,'prontera 150 180')
        peer_depart=0
    if not sent_scene and time.monotonic()-start>12:
        # Seed a camp attack and use the actual puller's next walking destination.
        snap=log.read_bytes()[-250000:].decode(errors='replace')
        matches=re.findall(r'B_A (\\d+) '+str(tank_id)+r' (.+)',snap)
        if matches:
            vals=list(map(int,matches[-1][1].split()))
            dest=vals[8:10]
            if max(abs(dest[0]-anchor[0]),abs(dest[1]-anchor[1]))>=4:
                warp(peer,f'{field} {dest[0]} {dest[1]}')
                ev=stage/'npc/custom/qa_shadow_camp.txt'
                ev.write_text('-\\tscript\\tQA Shadow Camp\\t-1,{\\nOnInit:\\n monster "'+field+'",'+str(anchor[0])+','+str(anchor[1])+',"Camp attacker",1213,5; end;\\n}\\n')
                c.command('@loadnpc npc/custom/qa_shadow_camp.txt')
                sent_scene=True
                peer_depart=elapsed+9
"""
setup+="""
probe=stage/'npc/custom/qa_shadow_probe.txt'
probe.write_text('-\\tscript\\tQA Shadow Probe\\t-1,{\\nOnInit:\\n bindatcmd "shadowprobe",strnpcinfo(3)+"::OnProbe",99,99; end;\\nOnProbe:\\n if(Hp*100>MaxHp*80){ percentheal -36,0; debugmes "B_PROBE 1"; } end;\\n}\\n')
"""
import os
if os.getenv('BRAIN_FAR_STRESS')=='1':
    # Only the scenario controller can create an HP deficit, always on a
    # healthy actor actually outside native Heal range. Normal AI heals it.
    setup=setup.replace('if(Hp*100>MaxHp*80){','if(attachrid(atoi(.@atcmd_parameters$[0])) && Hp*100>MaxHp*80){')
    pulse=pulse.replace("c.command('@shadowprobe')", """tail=log.read_bytes()[-350000:].decode(errors='replace')
        aid=95000002 if puller=='priest' else 95000001
        cv=re.findall(r'B_COVER \\d+ '+str(aid)+r' (\\d+)',tail)
        if cv and cv[-1]=='0':c.command('@shadowprobe '+str(aid))""").replace('next_probe+=16','next_probe+=4')
base=base.replace("exec(compile(source,", "source=source.replace('before=stock()',setup+'\\nbefore=stock()').replace('    if measure_train:',pulse+'\\n    if measure_train:',1)\nexec(compile(source,")
exec(compile(base,'/tests/brain_stage1/fixture.py','exec'))
