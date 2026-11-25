// Real SQLite, adversarial stale-snapshot/crash boundary tests for stack transfers.
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include "common/companion_supply.hpp"
int32 parse_console(const char*){return 0;}void display_helpscreen(bool){}
using namespace companion_supply;
Sql* db;
void open(){db=Sql_Malloc();assert(Sql_Connect(db,"","","",0,"supply-guard-test")==SQL_SUCCESS);}
void reopen(){Sql_Free(db);open();}
int value(const char* q){assert(Sql_QueryStr(db,q)==SQL_SUCCESS);assert(Sql_NextRow(db)==SQL_SUCCESS);char*s=nullptr;Sql_GetData(db,0,&s,nullptr);int n=std::atoi(s);Sql_FreeResult(db);return n;}
item potion(int n,int id=501){item v{};v.nameid=id;v.amount=n;v.identify=1;return v;}
void save(item* inv,int size,bool load=false){assert(Sql_QueryStr(db,"BEGIN IMMEDIATE")==SQL_SUCCESS);assert(guard(db,150001,inv,size,load));assert(Sql_QueryStr(db,"DELETE FROM inventory WHERE char_id=150001")==SQL_SUCCESS);for(int i=0;i<size;i++)if(inv[i].nameid)assert(Sql_Query(db,"INSERT INTO inventory(char_id,nameid,amount,identify) VALUES(150001,%u,%d,1)",inv[i].nameid,inv[i].amount)==SQL_SUCCESS);assert(Sql_QueryStr(db,"COMMIT")==SQL_SUCCESS);}
int main(){
 open();assert(available(db)==1);item inv[3]{};inv[0]=potion(100);save(inv,3);
 assert(!transfer(db,2000002,150001,1,501,20,100,true,3));
 assert(!transfer(db,2000001,150001,1,506,20,100,true,3));
 assert(transfer(db,2000001,150001,1,501,20,100,true,3));
 assert(!transfer(db,2000001,150001,1,501,20,80,true,3));reopen();
 assert(value("SELECT amount FROM inventory WHERE nameid=501")==80);
 save(inv,3);assert(inv[0].amount==80&&value("SELECT count(*) FROM ragoff_companion_supply_journal")==1);
 save(inv,3);assert(value("SELECT count(*) FROM ragoff_companion_supply_journal")==0);
 inv[0].amount=70;save(inv,3);assert(value("SELECT amount FROM inventory WHERE nameid=501")==70);
 assert(transfer(db,2000001,150001,1,501,20,70,false,3));reopen();
 save(inv,3);assert(inv[0].amount==90);save(inv,3);assert(value("SELECT count(*) FROM ragoff_companion_supply_journal")==0);
 // Reconnect loads the already-committed count and acknowledges before player interaction.
 assert(transfer(db,2000001,150001,1,501,10,90,true,3));reopen();inv[0].amount=80;save(inv,3,true);assert(value("SELECT count(*) FROM ragoff_companion_supply_journal")==0);
 assert(Sql_QueryStr(db,"CREATE TRIGGER fail_supply BEFORE UPDATE ON ragoff_companion_supply BEGIN SELECT RAISE(FAIL,'injected supply failure'); END")==SQL_SUCCESS);
 assert(!transfer(db,2000001,150001,1,501,10,80,true,3));assert(value("SELECT amount FROM inventory WHERE nameid=501")==80);assert(Sql_QueryStr(db,"DROP TRIGGER fail_supply")==SQL_SUCCESS);
 assert(Sql_QueryStr(db,"DELETE FROM ragoff_companion WHERE id=1")!=SQL_SUCCESS);
 assert(transfer(db,2000001,150001,1,501,10,80,false,3));inv[0].amount=90;save(inv,3,true);
 inv[0]={};save(inv,3);assert(value("SELECT count(*) FROM inventory")==0);
 // Returned potion is durably in DB; a stale full bag cannot create a fourth slot.
 assert(Sql_QueryStr(db,"UPDATE ragoff_companion_supply SET amount=5 WHERE profile_id=1 AND nameid=501")==SQL_SUCCESS);
 assert(transfer(db,2000001,150001,1,501,5,0,false,3));
 for(auto& v:inv)v=potion(1,505);
 assert(Sql_QueryStr(db,"BEGIN IMMEDIATE")==SQL_SUCCESS);assert(!guard(db,150001,inv,3,false));assert(Sql_QueryStr(db,"ROLLBACK")==SQL_SUCCESS);
 assert(value("SELECT amount FROM inventory WHERE nameid=501")==5);
 for(auto& v:inv)v={};inv[0]=potion(5);save(inv,3,true);
 assert(value("SELECT count(*) FROM ragoff_companion_supply_journal")==0);
 Sql_Free(db);std::puts("SUPPLY_STALE_SAVE_CRASH_ACK_SQL_FAILURE_CAPACITY_OWNERSHIP_PASS");
}
