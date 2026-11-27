// SPDX-License-Identifier: GPL-3.0
// Uses the prepared production SQL adapter and real in-memory SQLite; no player data.
#include "sql.cpp"
#include "catalogue_pet.hpp"
#include <cassert>
#include <fstream>
#include <sstream>
#include <iostream>
// The test opens SQLite directly, so no keepalive timer is installed.
int32 delete_timer(int32,TimerFunc){std::abort();}
using namespace catalogue_pet;
static int number(Sql* db,const char* query){assert(Sql_QueryStr(db,query)==SQL_SUCCESS);assert(Sql_NextRow(db)==SQL_SUCCESS);char* p;Sql_GetData(db,0,&p,nullptr);int n=std::atoi(p);Sql_FreeResult(db);return n;}
static void sql(Sql* db,const std::string& s){assert(Sql_QueryStr(db,s.c_str())==SQL_SUCCESS);}
static Sql* fixture(const char* migration){
 auto* db=Sql_Malloc();assert(sqlite3_open(":memory:",&db->db)==SQLITE_OK);
 sql(db,"CREATE TABLE char(char_id INTEGER PRIMARY KEY,account_id INTEGER,inventory_slots INTEGER)");sql(db,"INSERT INTO char VALUES(7,9,100)");
 std::string columns="id INTEGER PRIMARY KEY,char_id INTEGER,nameid INTEGER,amount INTEGER,identify INTEGER DEFAULT 0";
 for(auto n:{"unique_id","equip","equip_switch","refine","attribute","expire_time","bound","favorite","enchantgrade","card0","card1","card2","card3"})columns+=std::string(",")+n+" INTEGER DEFAULT 0";
 for(int i=0;i<5;++i)for(auto p:{"id","val","parm"})columns+=",option_"+std::string(p)+std::to_string(i)+" INTEGER DEFAULT 0";
 sql(db,"CREATE TABLE inventory("+columns+")");
 sql(db,"CREATE TABLE pet(pet_id INTEGER PRIMARY KEY,class,name,account_id,char_id,level,egg_id,equip,intimate,hungry,rename_flag,incubate,autofeed)");
 std::ifstream file(migration);std::stringstream buffer;buffer<<file.rdbuf();assert(!buffer.str().empty());
 // Sql_QueryStr accepts one prepared statement; migration contains one CREATE.
 sql(db,buffer.str());assert(available(db)==1);return db;
}
static Claim claim(){Claim q{};q.account=9;q.character=7;q.capacity=100;q.voucher_slot=0;q.egg_slot=1;q.food_slot=2;q.food_id=531;q.food_amount=50;q.egg_id=9001;q.monster=1002;q.level=1;q.intimacy=250;q.egg_card0=pet_marker;q.name="Poring";q.before[0].nameid=2000710;q.before[0].amount=1;q.before[0].identify=1;return q;}
static void voucher(Sql* db,int amount=1){sql(db,"INSERT INTO inventory(char_id,nameid,amount,identify) VALUES(7,2000710,"+std::to_string(amount)+",1)");}
int main(int argc,char** argv){assert(argc==2);int cases=0;
 {auto* db=fixture(argv[1]);auto q=claim();voucher(db);Snapshot after{};item egg{};
  assert(commit(db,q,after,egg));assert(egg.card[0]==pet_marker && egg.card[1]>0);assert(number(db,"SELECT count(*) FROM pet")==1);assert(number(db,"SELECT sum(amount) FROM inventory WHERE nameid=531")==50);assert(number(db,"SELECT count(*) FROM inventory WHERE nameid=2000710")==0);++cases;
  Snapshot ignored{};item other{};assert(!commit(db,q,ignored,other));assert(number(db,"SELECT count(*) FROM pet")==1);++cases;
  auto mixed=q.before;mixed[3].nameid=501;mixed[3].amount=1;assert(!guard(db,7,mixed.data(),false));assert(number(db,"SELECT count(*) FROM ragoff_catalogue_pet_journal")==1);++cases;
  auto stale=q.before;assert(guard(db,7,stale.data(),false));assert(same(stale.data(),after.data()));assert(number(db,"SELECT count(*) FROM ragoff_catalogue_pet_journal")==1);++cases;
  assert(!guard(db,7,q.before.data(),true));++cases;
  // Reordering/SQL row IDs and generated pet egg UID do not change pet identity.
  after[1].id=40;after[1].unique_id=12345;std::swap(after[1],after[5]);assert(guard(db,7,after.data(),true));assert(number(db,"SELECT count(*) FROM ragoff_catalogue_pet_journal")==0);++cases;Sql_Free(db);
 }
 {auto* db=fixture(argv[1]);auto q=claim();voucher(db,2);q.before[0].amount=2;q.before[2].nameid=531;q.before[2].amount=7;q.before[2].identify=1;sql(db,"INSERT INTO inventory(char_id,nameid,amount,identify) VALUES(7,531,7,1)");Snapshot after{};item egg{};assert(commit(db,q,after,egg));assert(number(db,"SELECT amount FROM inventory WHERE nameid=2000710")==1);assert(number(db,"SELECT amount FROM inventory WHERE nameid=531")==57);++cases;Sql_Free(db);}
 for(auto table:{"pet","ragoff_catalogue_pet_journal"}){auto* db=fixture(argv[1]);auto q=claim();voucher(db);sql(db,std::string("CREATE TRIGGER test_failure BEFORE INSERT ON ")+table+" BEGIN SELECT RAISE(ABORT,'synthetic SQL failure'); END");Snapshot after{};item egg{};assert(!commit(db,q,after,egg));assert(number(db,"SELECT count(*) FROM pet")==0);assert(number(db,"SELECT count(*) FROM inventory")==1);assert(number(db,"SELECT amount FROM inventory WHERE nameid=2000710")==1);assert(number(db,"SELECT count(*) FROM ragoff_catalogue_pet_journal")==0);++cases;Sql_Free(db);}
 {auto* db=fixture(argv[1]);auto q=claim();voucher(db);Snapshot after{};item egg{};q.food_slot=q.egg_slot;assert(!commit(db,q,after,egg));q=claim();q.before[0].bound=1;assert(!commit(db,q,after,egg));q=claim();q.name=std::string(NAME_LENGTH,'x');assert(!commit(db,q,after,egg));assert(number(db,"SELECT count(*) FROM pet")==0);cases+=3;Sql_Free(db);}
 std::cout<<"PASS "<<cases<<" native SQL pet transaction/recovery cases\n";
}
