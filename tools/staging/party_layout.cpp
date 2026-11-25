#include <cstdio>
#include "map/clif.hpp"
int main() {
 printf("%d %zu\n", partymemberinfo, sizeof(PACKET_ZC_ADD_MEMBER_TO_GROUP));
 printf("%d -1\n", partyinfo);
 printf("%d %zu\n", HEADER_ZC_NOTIFY_POSITION_TO_GROUPM, sizeof(PACKET_ZC_NOTIFY_POSITION_TO_GROUPM));
 printf("%d %zu\n", HEADER_ZC_NOTIFY_HP_TO_GROUPM, sizeof(PACKET_ZC_NOTIFY_HP_TO_GROUPM));
 printf("%d %zu\n", HEADER_ZC_DELETE_MEMBER_FROM_GROUP, sizeof(PACKET_ZC_DELETE_MEMBER_FROM_GROUP));
 printf("%d %zu\n", HEADER_ZC_NOTIFY_ACT, sizeof(PACKET_ZC_NOTIFY_ACT));
}
