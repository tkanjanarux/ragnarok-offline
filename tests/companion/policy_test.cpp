#include "population_engine/companion_policy.hpp"
#include <cassert>
using namespace companion_policy;
int main(){
 assert(defaults(7).role=="tank");assert(order(defaults(8))=="resurrection,heal,kyrie,blessing,agi,angelus,magnificat,impositio,gloria");
 assert(valid_role(7,"dps") && !valid_role(8,"tank") && !valid_role(9,"support"));
 std::vector<std::string> v;
 assert(parse_skills(8,"heal,resurrection",v) && v.size()==2 && v.front()=="heal");
 for(auto text:{"heal,heal","heal,","","bash","heal,,agi","heal');DROP TABLE char;--"}) assert(!parse_skills(8,text,v));
 assert(parse_skills(7,"none",v) && v.empty());assert(parse_skills(9,"firebolt",v));assert(!parse_skills(9,"heal",v));
}
