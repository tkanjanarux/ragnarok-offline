"""Preflight and emergency injection. No injected events in measured normal runs."""
import os
from pathlib import Path
probe=os.environ.get('TRIAL_PROBE','')
base=Path('/tests/brain_stage1/fixture.py').read_text()
initialize="""
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
            if body is None:
                body='getmapxy .@m$,.@x,.@y,BL_PC,"'+f.row(3)[14]+'"; monster .@m$,.@x,.@y,"Camp attacker",1213,12;'
            event=stage/'npc/custom/qa_limited_probe.txt'
            event.write_text('-\\tscript\\tQA Limited Probe\\t-1,{\\nOnInit:\\n if(attachrid(2000001)){ debugmes "B_PROBE '+probe+'"; '+body+' } end;\\n}\\n')
            c.command('@loadnpc npc/custom/qa_limited_probe.txt')
"""
base=base.replace('exec(compile(source,',"""source=source.replace('before=stock()',initialize+'\\nbefore=stock()').replace('start=time.monotonic()', 'tested=False\\nstart=time.monotonic()').replace('    if measure_train:',trigger+'\\n    if measure_train:',1)
exec(compile(source,""")
exec(compile(base,'/tests/brain_stage1/fixture.py','exec'))
