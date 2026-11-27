// Copyright (c) Ragnarok Offline contributors. GNU GPL, like the including server.
// Server-only script primitive: catalogue_exchange(voucher, item, count, ...).
// Fixed plain stackable rewards only; no pets, rentals, equipment or GUID items.
// No script yield between validation, grants and voucher consumption.
BUILDIN_FUNC(catalogue_exchange) {
    map_session_data* sd;
    if (!script_rid2sd(sd)) return SCRIPT_CMD_FAILURE;
    auto reject = [&]() { script_pushint(st, 0); return SCRIPT_CMD_SUCCESS; };
    if (sd->state.trading || pc_isdead(sd)) return reject();
    const int last = script_lastdata(st);
    if (last < 4 || (last - 2) % 2 != 0 || last > 66) return reject();
    const int64 voucher_value = script_getnum64(st, 2);
    if (voucher_value <= 0 || voucher_value > UINT32_MAX) return reject();
    const t_itemid voucher = static_cast<t_itemid>(voucher_value);
    int voucher_slot = -1;
    for (int i = 0; i < sd->status.inventory_slots; ++i) {
        const auto& v = sd->inventory.u.items_inventory[i];
        if (v.nameid == voucher && v.amount > 0 && !v.equip && !v.equipSwitch) { voucher_slot = i; break; }
    }
    if (voucher_slot < 0) return reject();
    struct Reward { t_itemid id; int amount; int slot; };
    std::vector<Reward> rewards;
    uint64 weight = sd->weight;
    int needed = 0;
    for (int arg = 3; arg <= last; arg += 2) {
        const int64 raw_id = script_getnum64(st, arg), raw_amount = script_getnum64(st, arg + 1);
        if (raw_id <= 0 || raw_id > UINT32_MAX || raw_amount <= 0 || raw_amount > MAX_AMOUNT) return reject();
        const t_itemid id = static_cast<t_itemid>(raw_id);
        const int amount = static_cast<int>(raw_amount);
        if (id == voucher) return reject();
        for (const auto& previous : rewards) if (previous.id == id) return reject();
        auto data = item_db.find(id);
        if (!data || !itemdb_isstackable2(data.get()) || data->flag.guid || data->flag.autoequip || data->type == IT_PETEGG) return reject();
        if (data->stack.inventory && amount > data->stack.amount) return reject();
        int slot = -1;
        for (int i = 0; i < MAX_INVENTORY; ++i) {
            const auto& v = sd->inventory.u.items_inventory[i];
            bool plain = v.bound == 0 && v.expire_time == 0 && v.unique_id == 0;
            for (const auto card : v.card) if (card != 0) plain = false;
            if (v.nameid != id || !plain) continue;
            // Match the exact first stack pc_additem uses, including its capacity.
            if (i >= sd->status.inventory_slots || amount > MAX_AMOUNT - v.amount ||
                (data->stack.inventory && amount > data->stack.amount - v.amount)) return reject();
            slot = i;
            break;
        }
        if (slot < 0) ++needed;
        weight += static_cast<uint64>(data->weight) * amount;
        rewards.push_back({id, amount, slot});
    }
    // Conservative: don't spend the voucher's weight/slot until all rewards fit.
    if (weight > sd->max_weight || needed > pc_inventoryblank(sd)) return reject();
    size_t granted = 0;
    for (auto& reward : rewards) {
        if (reward.slot < 0) reward.slot = pc_search_inventory(sd, 0);
        struct item plain = {};
        plain.nameid = reward.id;
        plain.identify = 1;
        if (pc_additem(sd, &plain, reward.amount, LOG_TYPE_SCRIPT) != ADDITEM_SUCCESS) {
            // Defensive rollback within this synchronous call. No item-use/equip
            // scripts run for the accepted plain stackable rewards.
            for (size_t i = 0; i < granted; ++i)
                pc_delitem(sd, rewards[i].slot, rewards[i].amount, 0, 0, LOG_TYPE_SCRIPT);
            return reject();
        }
        ++granted;
    }
    if (pc_delitem(sd, voucher_slot, 1, 0, 0, LOG_TYPE_SCRIPT) != 0) {
        for (const auto& reward : rewards)
            pc_delitem(sd, reward.slot, reward.amount, 0, 0, LOG_TYPE_SCRIPT);
        return reject();
    }
    script_pushint(st, 1);
    return SCRIPT_CMD_SUCCESS;
}

// Cash reset service: refund the points actually spent, preserving existing
// bonus/unspent points, quest skills, permanent grants and unrelated quest state.
// mode1 skills, mode2 six classic stats, mode3 both (traits intentionally unchanged).
BUILDIN_FUNC(catalogue_reset) {
    map_session_data* sd;
    if (!script_rid2sd(sd)) return SCRIPT_CMD_FAILURE;
    auto reject = [&]() { script_pushint(st, 0); return SCRIPT_CMD_SUCCESS; };
    const int64 raw_voucher = script_getnum64(st, 2);
    const int mode = script_getnum(st, 3);
    if (raw_voucher <= 0 || raw_voucher > UINT32_MAX || mode < 1 || mode > 3) return reject();
    if (pc_isdead(sd) || sd->state.trading || sd->weight != 0 ||
        !map_getmapflag(sd->m, MF_TOWN) || pc_iscarton(sd) || pc_isfalcon(sd) ||
        pc_isriding(sd) || pc_isridingdragon(sd) || pc_isridingwug(sd) ||
        sd->ud.skilltimer != INVALID_TIMER) return reject();
    const int slot = pc_search_inventory(sd, static_cast<t_itemid>(raw_voucher));
    if (slot < 0 || sd->inventory.u.items_inventory[slot].amount < 1) return reject();
    const bool skills = mode & 1, stats = mode & 2;
    uint64 stat_refund = 0, skill_refund = 0;
    const _sp stat_types[] = {SP_STR, SP_AGI, SP_VIT, SP_INT, SP_DEX, SP_LUK};
    if (stats) {
        for (const auto type : stat_types) {
            const int value = pc_getstat(sd, type);
            if (value < 1) return reject();
            stat_refund += pc_need_status_point(sd, type, 1 - value);
        }
        if (stat_refund + sd->status.status_point > UINT32_MAX) return reject();
    }
    std::vector<std::pair<uint16, s_skill>> preserved;
    if (skills) {
        if (battle_config.quest_skill_learn || battle_config.quest_skill_reset || pc_is_taekwon_ranker(sd)) return reject();
        for (const auto& entry : skill_db) {
            const uint16 id = entry.second->nameid, idx = skill_get_index(id);
            const auto& skill = sd->status.skill[idx];
            if (!skill.lv) continue;
            if (entry.second->inf2[INF2_ISQUEST] || entry.second->inf2[INF2_ISWEDDING] ||
                entry.second->inf2[INF2_ISSPIRIT] || skill.flag == SKILL_FLAG_PERM_GRANTED ||
                (id == NV_BASIC && (sd->class_ & MAPID_SECONDMASK) != MAPID_NOVICE)) {
                preserved.emplace_back(idx, skill);
                continue;
            }
            if (skill.flag == SKILL_FLAG_PERMANENT) skill_refund += skill.lv;
            else if (skill.flag >= SKILL_FLAG_REPLACED_LV_0) skill_refund += skill.flag - SKILL_FLAG_REPLACED_LV_0;
        }
        if (skill_refund + sd->status.skill_point > UINT32_MAX) return reject();
    }
    if (!stat_refund && !skill_refund) return reject();
    if (skills) {
        const auto prior_points = sd->status.skill_point;
        pc_resetskill(sd, 0);
        for (const auto& keep : preserved) sd->status.skill[keep.first] = keep.second;
        sd->status.skill_point = prior_points + static_cast<uint32>(skill_refund);
        clif_updatestatus(*sd, SP_SKILLPOINT);
        clif_skillinfoblock(*sd);
    }
    if (stats) {
        sd->status.status_point += static_cast<uint32>(stat_refund);
        for (const auto type : stat_types) {
            pc_setstat(sd, type, 1);
            clif_updatestatus(*sd, type);
        }
        for (const auto type : {SP_USTR, SP_UAGI, SP_UVIT, SP_UINT, SP_UDEX, SP_ULUK}) clif_updatestatus(*sd, type);
        clif_updatestatus(*sd, SP_STATUSPOINT);
    }
    pc_delitem(sd, slot, 1, 0, 0, LOG_TYPE_SCRIPT);
    status_calc_pc(sd, SCO_FORCE);
    script_pushint(st, 1);
    return SCRIPT_CMD_SUCCESS;
}

// Portable card-removal voucher. Same outcome probabilities/material/Zeny policy
// as npc/custom/card_remover.txt; synchronous preflight and defensive rollback.
// Args: voucher, equip slot, expected item/refine/card0..3, protection (1 item/2 cards).
static constexpr int catalogue_card_outcome(int roll, int protect) {
    return roll < 2 ? 2 : roll < 8 ? (protect == 1 ? 3 : 4) : roll < 10 ? 5 : 1;
}

BUILDIN_FUNC(catalogue_remove_cards) {
    map_session_data* sd;
    if (!script_rid2sd(sd)) return SCRIPT_CMD_FAILURE;
    auto reject = [&]() { script_pushint(st, 0); return SCRIPT_CMD_SUCCESS; };
    if (pc_isdead(sd) || sd->state.trading) return reject();
    const int64 voucher_raw = script_getnum64(st, 2);
    const int slot = script_getnum(st, 3), protect = script_getnum(st, 10);
    if (voucher_raw <= 0 || voucher_raw > UINT32_MAX || !equip_index_check(slot) || (protect != 1 && protect != 2)) return reject();
    const int index = pc_checkequip(sd, equip_bitmask[slot]);
    if (index < 0 || !sd->inventory_data[index] || sd->inventory_data[index]->unequip_script ||
        sd->inventory_data[index]->flag.autoequip) return reject();
    item original = sd->inventory.u.items_inventory[index];
    if (original.amount != 1 || original.expire_time || original.equipSwitch || itemdb_isspecial(original.card[0]) ||
        original.nameid != script_getnum64(st, 4) || original.refine != script_getnum(st, 5)) return reject();
    for (int n = 0; n < MAX_SLOTS; ++n) if (original.card[n] != script_getnum64(st, 6+n)) return reject();
    const int voucher_slot = pc_search_inventory(sd, static_cast<t_itemid>(voucher_raw));
    const int crumb_slot = pc_search_inventory(sd, 1000), gem_slot = pc_search_inventory(sd, 715);
    if (voucher_slot < 0 || crumb_slot < 0 || gem_slot < 0) return reject();
    struct Card { t_itemid id; int amount; int slot; };
    std::vector<Card> cards;
    int count = 0;
    item cleaned = original;
    cleaned.equip = 0; cleaned.equipSwitch = 0;
    for (int n = 0; n < sd->inventory_data[index]->slots; ++n) {
        const auto id = original.card[n];
        if (!id || itemdb_type(id) != IT_CARD) continue;
        ++count; cleaned.card[n] = 0;
        auto found = std::find_if(cards.begin(), cards.end(), [id](const Card& c) { return c.id == id; });
        if (found == cards.end()) cards.push_back({id,1,-1}); else ++found->amount;
    }
    if (!count) return reject();
    const int fee = 200000 + count * 25000;
    if (sd->status.zeny < fee) return reject();
    uint64 weight = sd->weight;
    int needed = 0;
    for (auto& card : cards) {
        auto data = item_db.find(card.id);
        if (!data || data->flag.guid || data->flag.autoequip || !itemdb_isstackable2(data.get())) return reject();
        for (int n = 0; n < sd->status.inventory_slots; ++n) {
            const item& v = sd->inventory.u.items_inventory[n];
            if (v.nameid != card.id || v.bound || v.expire_time || v.unique_id) continue;
            bool plain = true; for (const auto c : v.card) if (c) plain = false;
            if (!plain) continue;
            if (card.amount > MAX_AMOUNT-v.amount || (data->stack.inventory && card.amount > data->stack.amount-v.amount)) return reject();
            card.slot = n; break;
        }
        if (card.slot < 0) ++needed;
        weight += static_cast<uint64>(data->weight) * card.amount;
    }
    if (weight > sd->max_weight || needed > pc_inventoryblank(sd)) return reject();
    const int roll = rnd()%100;
    const int outcome = catalogue_card_outcome(roll, protect);
    size_t granted = 0;
    auto undo_cards = [&]() {
        for (size_t n = 0; n < granted; ++n) pc_delitem(sd, cards[n].slot, cards[n].amount, 0, 0, LOG_TYPE_SCRIPT);
    };
    if (outcome == 1 || outcome == 4) {
        for (auto& card : cards) {
            if (card.slot < 0) card.slot = pc_search_inventory(sd, 0);
            item reward = {}; reward.nameid = card.id; reward.identify = 1;
            if (pc_additem(sd, &reward, card.amount, LOG_TYPE_SCRIPT) != ADDITEM_SUCCESS) { undo_cards(); return reject(); }
            ++granted;
        }
    }
    if (outcome != 5) {
        if (pc_delitem(sd, index, 1, 0, 3, LOG_TYPE_SCRIPT) != 0) { undo_cards(); return reject(); }
        if ((outcome == 1 || outcome == 3) && pc_additem(sd, &cleaned, 1, LOG_TYPE_SCRIPT) != ADDITEM_SUCCESS) {
            undo_cards(); original.equip = 0; original.equipSwitch = 0;
            pc_additem(sd, &original, 1, LOG_TYPE_SCRIPT);
            return reject();
        }
    }
    // No yield or item/equip script between preflight and these validated costs.
    pc_payzeny(sd, fee, LOG_TYPE_SCRIPT);
    pc_delitem(sd, crumb_slot, 1, 0, 0, LOG_TYPE_SCRIPT);
    pc_delitem(sd, gem_slot, 1, 0, 0, LOG_TYPE_SCRIPT);
    pc_delitem(sd, voucher_slot, 1, 0, 0, LOG_TYPE_SCRIPT);
    script_pushint(st, outcome);
    return SCRIPT_CMD_SUCCESS;
}
