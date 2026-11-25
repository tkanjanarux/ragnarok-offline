// Adversarial old-save/crash-boundary tests against real SQLite and escrow functions.
#include <cassert>
#include <cstdio>
#include "common/companion_gear.hpp"
int32 parse_console(const char*){return 0;}void display_helpscreen(bool){}
using namespace companion_gear;
Sql* db;
uint64 count(const char* table){assert(Sql_Query(db,"SELECT count(*) FROM %s",table)==SQL_SUCCESS);assert(Sql_NextRow(db)==SQL_SUCCESS);char* s;Sql_GetData(db,0,&s,nullptr);auto n=std::strtoull(s,nullptr,10);Sql_FreeResult(db);return n;}
void open(){db=Sql_Malloc();assert(Sql_Connect(db,"","","",0,"gear-guard-test")==SQL_SUCCESS);}
void reopen(){Sql_Free(db);open();}
// Native save reconciles its whole snapshot. A delete/insert model is strictly
// adversarial: any escrow item absent from the guarded snapshot would be lost.
void snapshot(item* values,int size,bool load=false){
 assert(Sql_QueryStr(db,"BEGIN IMMEDIATE")==SQL_SUCCESS);std::vector<uint32> ack;
 assert(guard_snapshot(db,150001,values,size,ack,load));
 assert(Sql_QueryStr(db,"DELETE FROM inventory WHERE char_id=150001")==SQL_SUCCESS);
 for(int i=0;i<size;i++)if(values[i].nameid)assert(Sql_Query(db,"INSERT INTO inventory(char_id,nameid,amount,identify,unique_id,refine,card0,card1,card2,card3) VALUES(150001,%u,1,1,'%llu',%u,%u,%u,%u,%u)",values[i].nameid,(unsigned long long)values[i].unique_id,unsigned(values[i].refine),values[i].card[0],values[i].card[1],values[i].card[2],values[i].card[3])==SQL_SUCCESS);
 assert(acknowledge(db,ack));assert(Sql_QueryStr(db,"COMMIT")==SQL_SUCCESS);
}
int main(){
 open();assert(available(db)==1);
 assert(Sql_QueryStr(db,"INSERT INTO char(char_id,account_id,name,inventory_slots,sex) VALUES(150001,2000001,'GearGuardPlayer',3,'M')")==SQL_SUCCESS);
 item sword{};sword.nameid=1101;sword.amount=1;sword.identify=1;sword.unique_id=777000;
 item inv[3]{};inv[0]=sword;snapshot(inv,3);assert(count("inventory")==1);
 auto modified=sword;modified.refine=1;assert(!give(db,2000001,150001,1,modified));assert(!give(db,2000002,150001,1,sword));
 assert(Sql_QueryStr(db,"CREATE TRIGGER fail_give BEFORE INSERT ON ragoff_companion_gear BEGIN SELECT RAISE(FAIL,'injected give failure'); END")==SQL_SUCCESS);
 assert(!give(db,2000001,150001,1,sword));assert(count("inventory")==1&&count("ragoff_companion_gear")==0);assert(Sql_QueryStr(db,"DROP TRIGGER fail_give")==SQL_SUCCESS);
 assert(give(db,2000001,150001,1,sword));assert(!give(db,2000001,150001,1,sword));reopen();assert(count("inventory")==0&&count("ragoff_companion_gear")==1);
 // Pre-give in-flight snapshot cannot recreate the loaned item.
 inv[0]=sword;snapshot(inv,3);assert(!inv[0].nameid&&count("inventory")==0);
 assert(Sql_QueryStr(db,"DELETE FROM ragoff_companion WHERE id=1")!=SQL_SUCCESS);
 std::vector<Gear> rows;assert(list(db,150001,1,rows)&&rows.size()==1);auto g=rows[0];
 assert(Sql_QueryStr(db,"CREATE TRIGGER fail_take BEFORE UPDATE ON ragoff_companion_gear BEGIN SELECT RAISE(FAIL,'injected return failure'); END")==SQL_SUCCESS);
 assert(!take(db,g));assert(count("inventory")==0&&count("ragoff_companion_gear")==1);assert(Sql_QueryStr(db,"DROP TRIGGER fail_take")==SQL_SUCCESS);
 auto bad=g;bad.value.unique_id++;assert(!take(db,bad));assert(take(db,g));assert(!take(db,g));reopen();assert(count("inventory")==1);
 // Post-give snapshots missing the returned item cannot delete it, even after crash.
 item old[3]{};snapshot(old,3);assert(count("inventory")==1&&count("ragoff_companion_gear")==1);
 // A stale full bag must fail atomically, never create an inaccessible extra slot.
 item full[3]{};for(int i=0;i<3;i++){full[i]=sword;full[i].unique_id+=10+i;}
 assert(Sql_QueryStr(db,"BEGIN IMMEDIATE")==SQL_SUCCESS);std::vector<uint32> ack;assert(!guard_snapshot(db,150001,full,3,ack));assert(Sql_QueryStr(db,"ROLLBACK")==SQL_SUCCESS);
 assert(count("inventory")==1 && count("ragoff_companion_gear")==1);
 // Map ACK has seen the returned UID: retire journal and never resurrect a later drop.
 item current[3]{};current[0]=sword;snapshot(current,3);assert(count("inventory")==1&&count("ragoff_companion_gear")==0);
 item dropped[3]{};snapshot(dropped,3);assert(count("inventory")==0);
 // A reconnect (load handoff) also retires journal before player can drop/trade.
 inv[0]=sword;snapshot(inv,3);assert(give(db,2000001,150001,1,sword));assert(list(db,150001,1,rows));assert(take(db,rows[0]));reopen();
 current[0]=sword;snapshot(current,3,true);assert(count("ragoff_companion_gear")==0);snapshot(dropped,3);assert(count("inventory")==0);
 // Updated gear cannot be stripped by a late save, an older return, or a forged handle.
 if(details_available(db)==1){
  sword.refine=9;sword.card[0]=4004;sword.card[1]=4004;sword.card[2]=4007;sword.card[3]=4001;
  inv[0]=sword;snapshot(inv,3);assert(give(db,2000001,150001,1,sword));
  reopen();assert(list(db,150001,1,rows)&&rows.size()==1);g=rows.front();
  assert(g.value.refine==9 && g.value.card[3]==4001);
  auto stale=g;stale.value.refine=0;assert(!take(db,stale));
  assert(take(db,g));reopen();
  assert(Sql_QueryStr(db,"BEGIN IMMEDIATE")==SQL_SUCCESS);
  current[0]=sword;current[0].card[0]=0;
  assert(!guard_snapshot(db,150001,current,3,ack));
  assert(Sql_QueryStr(db,"ROLLBACK")==SQL_SUCCESS);
  old[0]={};snapshot(old,3);
  assert(old[0].refine==9 && old[0].card[1]==4004);
  current[0]=sword;snapshot(current,3,true);
  assert(count("ragoff_companion_gear_details")==0 && count("inventory")==1);
 }
 if(options_available(db)==1){
  sword.enchantgrade=2;sword.option[0]={1,-33,4};sword.option[4]={2,19,1};
  assert(Sql_QueryStr(db,"UPDATE inventory SET enchantgrade=2,option_id0=1,option_val0=-33,option_parm0=4,option_id4=2,option_val4=19,option_parm4=1 WHERE unique_id=777000")==SQL_SUCCESS);
  auto changed=sword;changed.option[4].param++;
  assert(!give(db,2000001,150001,1,changed));
  assert(give(db,2000001,150001,1,sword));
  reopen();assert(list(db,150001,1,rows)&&rows.size()==1);g=rows.front();
  assert(g.value.option[0].value==-33 && g.value.option[4].param==1 && g.value.enchantgrade==2);
  auto stale=g;stale.value.option[4]={};assert(!take(db,stale));
  assert(take(db,g));reopen();
  assert(Sql_QueryStr(db,"BEGIN IMMEDIATE")==SQL_SUCCESS);
  current[0]=changed;assert(!guard_snapshot(db,150001,current,3,ack));
  assert(Sql_QueryStr(db,"ROLLBACK")==SQL_SUCCESS);
  assert(Sql_QueryStr(db,"BEGIN IMMEDIATE")==SQL_SUCCESS);
  current[0]=sword;assert(guard_snapshot(db,150001,current,3,ack,true));
  assert(acknowledge(db,ack));assert(Sql_QueryStr(db,"COMMIT")==SQL_SUCCESS);
  assert(count("inventory")==1 && count("ragoff_companion_gear_options")==0);
 }
 Sql_Free(db);std::puts("GEAR_SQL_OLD_SNAPSHOT_CRASH_DUPLICATE_FAILURE_LOAD_HANDOFF_PASS");
}
