"""Exercise the same detail and action frames as the iPhone client."""
import time
import struct
import sqlite3
from companion_ai_fixture import stage
from check_m4_skills import wait

class BirdFixture:
    def __init__(self, client):
        self.c = client
        self.seq = 5000
        self.spawn = {}
        self.db = sqlite3.connect(stage/'ragoff-stage.sqlite3', isolation_level=None)

    def frames(self, action):
        self.seq += 1
        caps = 'ui2 skills8 gear3 syrup1 hunter1 hunt1' if action.startswith('inspect ') else 'ui2 hunter1 hunt1'
        self.c.command(f'@companion ui {self.seq} {action} {caps}')
        rows = []
        while True:
            def matching(i,b):
                if i in (0x9fe,0x9ff):
                    aid=struct.unpack_from('<I',b,5)[0]
                    self.spawn[aid]=(struct.unpack_from('<H',b,23)[0],struct.unpack_from('<H',b,13)[0])
                return i==0x8e and b[4:].startswith(f'[RCO1] {self.seq} '.encode())
            packet = wait(self.c, matching)
            row = packet[4:].rstrip(b'\0').decode().split()[2:]
            rows.append(row)
            if row[0]=='end':
                return rows

    def note(self, action):
        return ' '.join(self.frames(action)[-1][1:])

    def row(self, pid):
        return next(t for t in self.frames(f'inspect {pid}') if t[:2]==['row',str(pid)])

    def ranks(self, pid):
        return {int(t[1]):int(t[2]) for t in self.frames(f'inspect {pid}') if t[0]=='skill'}

    def eventually(self, check):
        for _ in range(80):
            if check():
                return
            time.sleep(.1)
        assert check()
