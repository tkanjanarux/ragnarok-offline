// SPDX-License-Identifier: GPL-3.0
#pragma once
#include "mmo.hpp"
#include "sql.hpp"
#include <array>
#include <string>
namespace catalogue_pet {
// Existing CARD0_PET wire marker, checked against itemdb.hpp in the map adapter.
inline constexpr t_itemid pet_marker = 0x0100;
using Snapshot = std::array<item,MAX_INVENTORY>;
struct Claim {
    uint32 account, character;
    int capacity, voucher_slot, food_slot, egg_slot;
    int food_amount;
    uint16 monster, level, intimacy;
    t_itemid food_id, egg_id;
    uint32 egg_card0, egg_card3;
    std::string name;
    Snapshot before;
};
int available(Sql* db);
bool same(const item* a, const item* b);
bool plain(const item& value);
bool commit(Sql* db, const Claim& claim, Snapshot& after, item& egg);
// Runs INSIDE the existing char inventory SQL transaction. Never opens a nested one.
bool guard(Sql* db, uint32 character, item* values, bool loading);
}
// Map-side callback for the existing inventory-save barrier, no new wire opcode.
void catalogue_pet_barrier(uint32 account,uint32 character,uint32 token,int ready);
