from bird_fixture import BirdFixture
from check_m4_skills import wait

class BuildFixture(BirdFixture):
    def frames(self, action):
        self.seq += 1
        caps = 'ui2 skills9 gear3 syrup1 hunter1 hunt1' if action.startswith('inspect ') else 'ui2 hunter1 hunt1'
        self.c.command(f'@companion ui {self.seq} {action} {caps}')
        rows=[]
        while True:
            p=wait(self.c,lambda i,b:i==0x8e and b[4:].startswith(f'[RCO1] {self.seq} '.encode()))
            row=p[4:].rstrip(b'\0').decode().split()[2:]
            rows.append(row)
            if row[0]=='end':return rows

    def select(self,pid,key):
        note=self.note(f'build {pid} {key}')
        assert note.startswith('Build: '+key),note
        assert self.row(pid)[-1]==key,self.row(pid)
