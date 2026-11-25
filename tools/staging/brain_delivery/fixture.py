"""Run a real NPC spawn on the isolated, surveyed field. No client attacks."""
from pathlib import Path

base = Path('/tests/brain_stage1/fixture.py').read_text()
marker = "source=source.replace(' bindatcmd"
setup = """
    dock_script=stage/'npc/custom/qa_dock.txt'
    ax,ay=anchor
    rays=[(1,0),(0,1),(-1,0),(0,-1)]
    dx,dy=next((dx,dy) for dx,dy in rays if all(open_cell(ax+i*dx+j*dy,ay+i*dy-j*dx) for i in range(1,19) for j in (-1,0,1)))
    lines=['-\\tscript\\tQA Dock\\t-1,{','OnInit:']
    for gid,k,mx,my in mobs:
        # Use only the recorded local population, parked at an existing remote spawn.
        if max(abs(mx-ax),abs(my-ay))<110 or any(max(abs(x-ax),abs(y-ay))<110 for _,kind,x,y in original if kind==k):
            far=next(((x,y) for _,_,x,y in original if max(abs(x-ax),abs(y-ay))>120),None)
            if far:lines.append(f'unitwarp {gid},"{field}",{far[0]},{far[1]};')
    if os.getenv('DELIVERY_CASE')=='tight':
        for i in range(-8,9):
            for j in range(-8,9):
                if 4<=max(abs(i),abs(j))<=8:
                    lines.append(f'setcell "{field}",{ax+i},{ay+j},{ax+i},{ay+j},cell_walkable,0;')
    probe_case=os.getenv('DELIVERY_CASE')
    species=1197 if probe_case=='undead' else 1369
    distances=(24,26,36,38) if probe_case in ('long','stray','self_defense','camp_add','overlap','withdraw','two_rounds','retreat_before','retreat_after') else (13,15,17,18)
    if probe_case in ('three_sg_native','three_sg_high'):distances=(13,15,17)
    for i in distances:
        px,py=ax+i*dx,ay+i*dy
        if not open_cell(px,py):
            px,py=min(((x,y) for x in range(px-4,px+5) for y in range(py-4,py+5) if open_cell(x,y)),key=lambda p:max(abs(p[0]-px),abs(p[1]-py)))
        lines.append(f'monster "{field}",{px},{py},"Delivery probe",{species},1;')
        if os.getenv('DELIVERY_CASE')=='late':
            lines+=['setunitdata $@mobid[0],UMOB_MAXHP,25000;','setunitdata $@mobid[0],UMOB_HP,25000;']
        lines.append('debugmes "B_PROBE "+$@mobid[0];')
    lines+=['debugmes "B_DOCKREADY";','end;','}']
    dock_script.write_text('\\n'.join(lines)+'\\n')
    query('@loadnpc npc/custom/qa_dock.txt','B_DOCKREADY')
"""
insert = "source=source.replace(\"    assert 'ON' in f.note('mob on')\", " + repr(setup) + " + \"    assert 'ON' in f.note('mob on')\")\n"
move="""
    scenario=os.getenv('DELIVERY_CASE')
    if scenario=='two_rounds' and not dock_walk_sent:
        trace=log.read_text(errors='replace')[dock_offset:]
        if re.search(r'B_ROUND [0-9]+ 1 [23] ',trace):
            second=stage/'npc/custom/qa_dock_second.txt'
            next_spawns=[(ax+i*dx,ay+i*dy) for i in (55,58,61,64)]
            lines=['-\\tscript\\tQA Next\\t-1,{','OnInit:']
            for px,py in next_spawns:
                px,py=min(((x,y) for x in range(px-8,px+9) for y in range(py-8,py+9) if open_cell(x,y)),key=lambda p:max(abs(p[0]-px),abs(p[1]-py)))
                lines += [f'monster "{field}",{px},{py},"Next pack",1369,1;', 'debugmes "B_NEXT "+$@mobid[0];']
            second.write_text('\\n'.join(lines+['debugmes "B_NEXTREADY";','end;','}'])+'\\n')
            query('@loadnpc npc/custom/qa_dock_second.txt','B_NEXTREADY')
            dock_walk_sent=True
    add_due=False
    if scenario in ('camp_add','overlap') and not dock_walk_sent:
        observed=log.read_text(errors='replace')[dock_offset:]
        away=re.findall(r'B_A [0-9]+ 95000001 2 [0-9]+ ([0-9]+) ([0-9]+)',observed)
        add_due=away and max(abs(int(away[-1][0])-ax),abs(int(away[-1][1])-ay))>=8
        if scenario=='overlap':add_due=add_due and 'B_PACK ' in observed
    if add_due:
        stray=stage/'npc/custom/qa_dock_add.txt'
        lines=['-\\tscript\\tQA Round Add\\t-1,{','OnInit:',
               'getmapxy .@m$,.@x,.@y,BL_PC,"'+f.row(4)[14]+'";',
               'monster .@m$,.@x+1,.@y,"Camp intruder",1369,1;',
               'setunitdata $@mobid[0],UMOB_MODE,1;',
               'setunitdata $@mobid[0],UMOB_SPEED,1000;',
               'setunitdata $@mobid[0],UMOB_MAXHP,25000;',
               'setunitdata $@mobid[0],UMOB_HP,25000;',
               'debugmes "B_ADD "+$@mobid[0];','end;','}']
        stray.write_text('\\n'.join(lines)+'\\n')
        query('@loadnpc npc/custom/qa_dock_add.txt','B_ADD ')
        dock_walk_sent=True
    if scenario in ('stray','self_defense') and not dock_walk_sent and 'B_PACK ' in log.read_text(errors='replace')[dock_offset:]:
        stray=stage/'npc/custom/qa_dock_stray.txt'
        lines=['-\\tscript\\tQA Dock Stray\\t-1,{','OnInit:',
               'getmapxy .@m$,.@x,.@y,BL_PC,"'+f.row(3)[14]+'";',
               'monster .@m$,.@x+1,.@y,"Camp stray",1369,1;',
               'setunitdata $@mobid[0],UMOB_TARGETID,95000002;',
               'debugmes "B_STRAY "+$@mobid[0];','end;','}']
        if scenario=='self_defense':
            lines.insert(2,'if(attachrid(95000003)){ sc_start SC_STUN,12000,1,10000,1; detachrid; }')
        stray.write_text('\\n'.join(lines)+'\\n')
        query('@loadnpc npc/custom/qa_dock_stray.txt','B_STRAY ')
        dock_walk_sent=True
    if os.getenv('DELIVERY_CASE')=='move' and not dock_walk_sent and 'B_PACK ' in log.read_text(errors='replace')[dock_offset:]:
        match=re.findall(r'B_DOCK [0-9]+ [0-9]+ [0-9]+ ([0-9]+) ([0-9]+)',log.read_text(errors='replace'))
        if match:
            wx,wy=map(int,match[-1])
            walk,desc=entry('clif_parse_WalkToXY')
            frame=bytearray(desc['length'])
            struct.pack_into('<H',frame,0,walk)
            i=desc['offsets'][0]
            frame[i:i+3]=bytes([wx>>2,((wx&3)<<6)|(wy>>4),(wy&15)<<4])
            c.send(frame);dock_walk_sent=True
            print('OWNER_WALK_REQUEST',wx,wy,flush=True)
"""
insert += "source=source.replace('while time.monotonic()-start<duration:', 'dock_offset=log.stat().st_size\\ndock_walk_sent=False\\nwhile time.monotonic()-start<duration:'+"+repr(move)+")\n"
assert base.count(marker) == 1
exec(compile(base.replace(marker, insert + marker), '/tests/brain_stage1/fixture.py', 'exec'))
