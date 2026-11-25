"""Count actual committed supply use on the disposable M9 server."""
import sqlite3
import time

from companion_ai_fixture import api, setup, stage


class PotionFixture:
    def __init__(self, *jobs):
        self.c, self.rows = setup(*jobs)
        self.row = self.rows[jobs[0]]
        self.pid = self.row['id']
        self.db = sqlite3.connect(stage/'ragoff-stage.sqlite3', isolation_level=None)
        self.owner, = self.db.execute('SELECT owner_char FROM ragoff_companion WHERE id=?',(self.pid,)).fetchone()

    def command(self, action):
        return api(self.c, f'{action} {self.pid}')

    def refresh(self):
        self.row = next(r for r in api(self.c,'list')[0] if r['id']==self.pid)
        return self.row

    def set(self, stat, value):
        self.c.command(f"#set {self.row['name']} {stat} {value}")

    def stock(self):
        return dict(self.db.execute('SELECT nameid,amount FROM ragoff_companion_supply WHERE profile_id=?',(self.pid,)))

    def seed(self, items):
        self.db.executemany('INSERT INTO ragoff_companion_supply(profile_id,owner_char,nameid,amount) VALUES(?,?,?,?)',
                            [(self.pid,self.owner,item,amount) for item,amount in items.items()])

    def next_use(self, before, timeout=5):
        end = time.monotonic()+timeout
        while time.monotonic()<end:
            after = self.stock()
            if after != before:
                diff = {i: n-after[i] for i,n in before.items() if n!=after[i]}
                assert len(diff)==1 and list(diff.values())==[1], (before, after)
                return next(iter(diff))
            time.sleep(.025)
        raise AssertionError(('stock unchanged',before))
