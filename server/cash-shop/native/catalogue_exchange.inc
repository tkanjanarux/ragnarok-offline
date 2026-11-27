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
