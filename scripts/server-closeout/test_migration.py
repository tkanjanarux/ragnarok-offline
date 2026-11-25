import concurrent.futures,json,pathlib,sqlite3,tempfile,unittest
from migrate_ids import migrate
SCHEMA=json.loads(pathlib.Path(__file__).with_name('schema-before.json').read_text())
class MigrationTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.p=pathlib.Path(self.tmp.name)/'test.db'
  with sqlite3.connect(self.p) as c:
   for sql in SCHEMA.values(): c.execute(sql)
   c.execute('insert into mail(id,title) values(19,"preserved")')
   c.execute('insert into guild(guild_id,char_id,name) values(31,2,"Guild")')
 def tearDown(self): self.tmp.cleanup()
 def run_migration(self): return migrate(self.p,self.p.with_suffix('.backup'))
 def test_preserve_and_allocate_concurrently(self):
  self.run_migration()
  def insert(i):
   with sqlite3.connect(self.p,timeout=20) as c:
    return c.execute('insert into mail(title) values(?)',(str(i),)).lastrowid
  with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool: ids=list(pool.map(insert,range(80)))
  self.assertEqual(len(set(ids)),80);self.assertTrue(all(i>19 for i in ids))
  with sqlite3.connect(self.p) as c:
   self.assertEqual(c.execute('select title from mail where id=19').fetchone()[0],'preserved')
   self.assertGreater(c.execute('insert into guild(name) values("New")').lastrowid,31)
   last=c.execute('insert into mail(title) values("delete")').lastrowid
   c.execute('delete from mail where id=?',(last,))
   self.assertGreater(c.execute('insert into mail(title) values("next")').lastrowid,last)
 def test_duplicate_identity_rolls_back_every_table(self):
  with sqlite3.connect(self.p) as c: c.execute('insert into guild(guild_id,char_id) values(31,3)')
  with self.assertRaises(ValueError): self.run_migration()
  with sqlite3.connect(self.p) as c:
   self.assertEqual(c.execute('select sql from sqlite_master where name="mail"').fetchone()[0],SCHEMA['mail'])
   self.assertEqual(c.execute('select count(*) from guild').fetchone()[0],2)
 def test_backup_and_idempotence(self):
  self.run_migration()
  with sqlite3.connect(self.p.with_suffix('.backup')) as c:
   self.assertEqual(c.execute('select sql from sqlite_master where name="mail"').fetchone()[0],SCHEMA['mail'])
  self.assertEqual(migrate(self.p,self.p.with_suffix('.second'))['changed'],[])
  with self.assertRaises(ValueError): self.run_migration()
 def test_attachment_failure_rolls_back_mail(self):
  self.run_migration()
  with sqlite3.connect(self.p) as c:
   c.execute('create table attachments(id integer, amount integer check(amount>0))')
   c.execute('BEGIN IMMEDIATE')
   ident=c.execute('insert into mail(title) values("failure")').lastrowid
   with self.assertRaises(sqlite3.IntegrityError): c.execute('insert into attachments values(?,0)',(ident,))
   c.rollback()
   self.assertIsNone(c.execute('select 1 from mail where id=?',(ident,)).fetchone())
if __name__=='__main__': unittest.main(verbosity=2)
