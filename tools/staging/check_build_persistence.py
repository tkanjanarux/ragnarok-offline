"""Two-process check of build changes, forced rollback, promotion and level replay."""
import time
from pathlib import Path
from protocol import login
from companion_ai_fixture import stage
from build_fixture import BuildFixture
marker=stage/'artifacts/build-test-restart'
c=login()
c.command('@setbattleflag companion_enable 1')
f=BuildFixture(c)
kid=int(next(t[1] for t in f.frames('list') if t[0]=='row' and t[2] in ('7','1')))
if not marker.exists():
    f.select(kid,'spear')
    f.db.execute("create trigger build_rollback before insert on ragoff_companion_policy begin select raise(FAIL,'QA build rollback'); end")
    try:
        assert 'failed' in f.note(f'build {kid} sword').lower()
        assert f.row(kid)[-1]=='spear'
    finally:
        f.db.execute('drop trigger build_rollback')
    marker.write_text(str(kid))
    print('PASS rollback retained build and policy, restart now')
else:
    assert int(marker.read_text())==kid and f.row(kid)[-1]=='spear'
    c.command('@jobchange 3')
    c.command('@set JobLevel 50')
    first=f.ranks(kid)
    c.command('@jobchange 11')
    c.command('@set JobLevel 1')
    low=f.ranks(kid)
    for sk in (5,6,8,4):
        assert first[sk]==low[sk]
    assert low[57]==0 and low[55]==0
    c.command('@set JobLevel 50')
    top=f.ranks(kid)
    assert top[57]==10 and top[63]==1
    c.command('@set JobLevel 12')
    reduced=f.ranks(kid)
    assert reduced[63]==1 and reduced[57]==0 and reduced[58]==3,reduced
    c.command('@set JobLevel 50')
    assert f.ranks(kid)==top
    print('PASS build survived server restart, two skill pools, job level up/down and replay')
c.close()
