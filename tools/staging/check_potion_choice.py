import time
from potion_ai_fixture import PotionFixture

f=PotionFixture(7)
f.seed({501:12,502:10,503:10,504:10,505:10,569:1})
expected=f.stock()
for level, percent, potion in [(1,40,501),(15,40,502),(1,10,504),(1,100,505)]:
    f.c.command(f'@set BaseLevel {level}')
    time.sleep(.8)
    row=f.refresh()
    hp=max(1,row['max_hp']*percent//100)
    f.set('Hp',hp)
    f.set('Sp',1 if potion==505 else row['max_sp'])
    f.command('follow')
    used=f.next_use(expected)
    f.command('stop')
    assert used==potion,(level,hp,row['max_hp'],used,potion)
    expected[potion]-=1
    assert f.stock()==expected
    print('PASS max HP, HP, bottle',row['max_hp'],hp,used)
f.c.close()
