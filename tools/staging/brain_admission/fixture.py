"""Preflight and emergency injection. No injected events in measured normal runs."""
import os
from pathlib import Path
probe=os.environ.get('TRIAL_PROBE','')
base=Path('/tests/brain_stage1/fixture.py').read_text()
initialize="""
if probe=='raise':
    positions=[(x,y) for _,_,x,y in json.loads(layout.read_text())[1]]
    choices=[(x,y) for x in range(12,width-12,5) for y in range(12,height-12,5)
             if all(open_cell(x+i,y+j) for i in (-3,0,3) for j in (-3,0,3))]
    anchor=max(choices,key=lambda p:min(max(abs(p[0]-x),abs(p[1]-y)) for x,y in positions))
    warp(c,f'{field} {anchor[0]} {anchor[1]}')
    time.sleep(1)
if probe in ('critical','late','manual','heartbeat','range','orc','orc_late'):
    c.command('@killmonster2')
    time.sleep(.4)
"""
trigger="""
    if probe and not tested and time.monotonic()-start>(45 if probe=='orc_late' else 4):
        tested=True
        if probe=='manual':
            (stage/'artifacts/trial.stop').touch()
        elif probe=='heartbeat':
            (stage/'artifacts/trial.disconnect').touch()
        else:
            body={'critical':'percentheal -90,0;', 'late':'percentheal -40,0;'}.get(probe)
            if probe=='range':
                body='unitwarp 95000004,"'+field+'",'+str(anchor[0]+18)+','+str(anchor[1])+';'
            if probe=='cover':
                spot=next((anchor[0]+dx,anchor[1]+dy) for dx in (14,-14,13,-13) for dy in range(-3,4) if open_cell(anchor[0]+dx,anchor[1]+dy))
                body='unitwarp 95000002,"'+field+'",'+str(spot[0])+','+str(spot[1])+';'
            if probe in ('raise','allyraise'):
                body='getmapunits BL_MOB,"'+field+'",.@m; for(.@i=0;.@i<getarraysize(.@m);.@i++)unitwarp .@m[.@i],"'+field+'",143,21; percentheal -100,0;'
                if probe=='allyraise':
                    body=body.replace('percentheal -100,0;', 'detachrid; if(attachrid(95000003)){percentheal -100,0;}')
            if body is None:
                body='getmapxy .@m$,.@x,.@y,BL_PC,"'+f.row(3)[14]+'"; monster .@m$,.@x,.@y,"Camp attacker",1213,12;'
            event=stage/'npc/custom/qa_limited_probe.txt'
            event.write_text('-\\tscript\\tQA Limited Probe\\t-1,{\\nOnInit:\\n if(attachrid(2000001)){ debugmes "B_PROBE '+probe+'"; '+body+' } end;\\n}\\n')
            c.command('@loadnpc npc/custom/qa_limited_probe.txt')
"""
base=base.replace('exec(compile(source,',"""source=source.replace('before=stock()',initialize+'\\nbefore=stock()').replace('start=time.monotonic()', 'tested=False\\nstart=time.monotonic()').replace('    if measure_train:',trigger+'\\n    if measure_train:',1)
exec(compile(source,""")
exec(compile(base,'/tests/brain_stage1/fixture.py','exec'))
