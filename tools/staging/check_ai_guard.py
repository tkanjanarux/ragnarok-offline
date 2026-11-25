import struct
from companion_ai_fixture import setup, api, wait, stage, attack, spawn, owner
from check_m4_exp import warp


def target_mob_command(c):
    # Native script fixture runs on this isolated map only.
    path=stage/'npc/custom/ai_guard_fixture.txt'
    path.write_text('-\tscript\tAI Guard Fixture\t-1,{\nOnInit:\n'
                    'bindatcmd "aiguard",strnpcinfo(3)+"::OnTarget",99,99; end;\n'
                    'OnTarget:\n.@mob=atoi(.@atcmd_parameters$[0]); .@ally=atoi(.@atcmd_parameters$[1]);\n'
                    'setunitdata .@mob,UMOB_MAXHP,50000; setunitdata .@mob,UMOB_HP,50000; if (!.@ally) end;\n'
                    'getmapxy(.@map$, .@x, .@y, BL_PC, .@atcmd_parameters$[2]);\n'
                    'setunitdata .@mob,UMOB_MODE,MD_CANMOVE|MD_CANATTACK|MD_CHANGETARGETMELEE|MD_CHANGETARGETCHASE; unitwarp .@mob,.@map$,.@x,.@y; setunitdata .@mob,UMOB_TARGETID,0; setunitdata .@mob,UMOB_TARGETID,.@ally; getunitdata .@mob,.@d; debugmes "guard "+.@mob+" "+.@ally+" "+.@d[UMOB_TARGETID]+" "+.@x+" "+.@y; end;\n}\n')
    c.command('@loadnpc npc/custom/ai_guard_fixture.txt')
    wait(c,lambda i,b: i==0x8e and b'Script loaded' in b)


def run():
    c, rows = setup(7,8,9)
    target_mob_command(c)
    sword = rows[7]
    pid, actor = sword['id'], sword['actor']
    api(c,f'preset {pid} protect')
    for ally, provoke in ((rows[9],True),(rows[8],True),(rows[9],False)):
        api(c,f"skills {pid} {'provoke' if provoke else 'none'}")
        # A companion becomes a native combat participant on its first Assist.
        api(c,f"assist {ally['id']}")
        api(c,f"stop {ally['id']}")
        api(c,f'stop {pid}')
        egg,x,y=spawn(c,1097)
        warp(c,f'prontera {x} {y}')
        c.command(f"@aiguard {egg} 0")
        attack(c,egg)
        wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(owner,egg))
        mob,_,_=spawn(c,1002)
        c.command(f"@aiguard {mob} {ally['actor']} {ally['name']}")
        def incoming(i,b):
            return i==0x8c8 and struct.unpack_from('<II',b,2)==(mob,ally['actor'])
        wait(c,incoming,10)
        c.command(f'@companion ui 900 assist {pid}')
        if provoke:
            wait(c,lambda i,b:i==0x9cb and struct.unpack_from('<H',b,2)[0]==6 and struct.unpack_from('<II',b,8)==(mob,actor))
        else:
            wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(actor,mob))
        wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(mob,actor))
        # Once it is on the tank, the tank assists the owner's separate target.
        wait(c,lambda i,b:i==0x8c8 and struct.unpack_from('<II',b,2)==(actor,egg))
        print('PASS protected',ally['job'],'with', 'Provoke' if provoke else 'melee','and resumed owner target')
        c.command('@killmonster2')
    c.close()

if __name__=='__main__':
    run()
