local native = {}

local faction_key = "wh3_dlc24_tze_the_deceivers"
local cult_template = "wh3_dlc24_tze_cult_changeling"
local cult_sets = {
    wh3_dlc24_slot_set_tze_changeling = true,
    wh3_dlc24_slot_set_tze_changeling_startpos = true,
}

local function query(region_cqi, expression)
    return common.get_context_value("CcoCampaignSettlement", region_cqi, expression)
end

local function slot_list(slot_set)
    return "HostileForeignSlotList(PlayersFaction, CcoSlotSetRecord(" .. string.format("%q", slot_set) .. "))"
end

local function slot_expression(job)
    return slot_list(job.slot_set) .. ".FirstContext(Index == " .. job.slot_index .. ")"
end

local function candidates(slot, occupied)
    if occupied then
        return "Join(" .. slot .. ".PossibleUpgradeList, " .. slot .. ".PossibleUpgradeOnlyConversionsList).Distinct"
    end
    return slot .. ".PossibleBuildingChainsList"
end

local function level_expression(slot, job)
    local matches = "Key == " .. string.format("%q", job.level)
    if job.kind == "upgrade" then
        return candidates(slot, true) .. ".FirstContext(" .. matches .. ")"
    end
    return candidates(slot, false) .. ".FirstContext(LevelsList.FirstContext." .. matches .. ").LevelsList.FirstContext"
end

local function building_query(job, slot, expression)
    return query(job.region_cqi, "(slot = " .. slot .. ", level = " .. level_expression(slot, job)
        .. ") => { " .. expression .. " }")
end

local function slot_ready(job, slot)
    return query(job.region_cqi, "(slot = " .. slot .. ") => { IsContextValid(slot)"
        .. " && slot.IsForeignSlot && slot.IsPlayerFaction && slot.IsActive"
        .. " && slot.ForeignSlotSetKey == " .. string.format("%q", job.slot_set)
        .. " && slot.SlotTemplateKey == \"" .. cult_template .. "\""
        .. " && !IsContextValid(slot.ConstructionItemContext) && !slot.IsDismantling }") == true
end

local function current_building(job, slot)
    if query(job.region_cqi, slot .. ".IsEmpty") == true then return nil end
    return query(job.region_cqi, slot .. ".BuildingContext.BuildingLevelRecordContext.Key")
end

local function construction_quote(job, slot)
    local gold = building_query(job, slot, "level.CreateCost(slot.SettlementContext, PlayersFaction)")
    local turns = building_query(job, slot, "level.CreateTime(slot)")
    if type(gold) ~= "number" or type(turns) ~= "number" then return end

    local transaction = "level.ResourceCostContext(slot)"
    local pooled = transaction .. ".PooledResourceTransactionList"
    local count = building_query(job, slot, "GetIfElse(IsContextValid(" .. transaction .. "), " .. pooled .. ".Size, 0)")
    if type(count) ~= "number" then return end

    local resources = {}
    local supplies = 0
    for i = 0, count - 1 do
        local entry = pooled .. ".At(" .. i .. ")"
        local key = building_query(job, slot, entry .. ".ResourceKey")
        local amount = building_query(job, slot, entry .. ".AbsoluteValue")
        if type(key) ~= "string" or type(amount) ~= "number" then return end
        resources[key] = (resources[key] or 0) + amount
        if key == "wh3_dlc24_tze_cult_supplies_buildings" or key == "wh3_dlc24_tze_cult_supplies" then
            supplies = supplies + amount
        end
    end

    local can_pay = "level.CanAfford(slot.SettlementContext, PlayersFaction)"
    if count > 0 then can_pay = can_pay .. " && level.CanAffordResourceCostForSlot(slot)" end
    local affordable = building_query(job, slot, can_pay)
    if type(affordable) ~= "boolean" then return end
    return gold, supplies, turns, affordable, resources
end

local function can_construct(job, slot)
    return building_query(job, slot, "IsContextValid(level) && level.CanBuildInCurrentSlot(slot)") == true
end

local function can_remove(job, slot)
    return job.current ~= nil and job.level == job.current and query(job.region_cqi, slot .. ".CanDismantle") == true
end

local function add_construction(jobs, base, slot, level, catalog)
    if type(level) ~= "string" or not catalog[level] then return end
    local job = {}
    for key, value in pairs(base) do job[key] = value end
    job.level = level
    job.kind = job.current and "upgrade" or "build"
    if not can_construct(job, slot) then return end
    job.gold, job.supplies, job.turns, job.affordable, job.resources = construction_quote(job, slot)
    if job.gold ~= nil then jobs[#jobs + 1] = job end
end

local function scan_slot(jobs, region, slot_set, model_slot, index, catalog)
    local job = {
        region = region:name(),
        region_cqi = region:cqi(),
        province = region:province_name(),
        owner = region:owning_faction():name(),
        slot = model_slot:cqi(),
        slot_index = index,
        slot_set = slot_set,
    }
    local slot = slot_expression(job)
    if not slot_ready(job, slot) then return end
    job.current = current_building(job, slot)
    job.damaged = job.current ~= nil and query(job.region_cqi, slot .. ".BuildingContext.IsDamaged") == true

    local possible = candidates(slot, job.current ~= nil)
    local count = query(job.region_cqi, possible .. ".Size") or 0
    for candidate = 0, count - 1 do
        local entry = possible .. ".At(" .. candidate .. ")"
        if not job.current then entry = entry .. ".LevelsList.FirstContext" end
        add_construction(jobs, job, slot, query(job.region_cqi, entry .. ".Key"), catalog)
    end

    if job.current and catalog[job.current] then
        job.level = job.current
        job.kind = "remove"
        if can_remove(job, slot) then
            job.gold, job.supplies, job.affordable, job.resources = 0, 0, true, {}
            job.refund_gold = query(job.region_cqi, slot .. ".BuildingContext.DismantleRefundAmount")
            jobs[#jobs + 1] = job
        end
    end
end

local function visit_cult(manager, visit)
    local set = manager:slot_set_key()
    if not cult_sets[set] then return end
    local region = manager:region()
    if region:is_abandoned() then return end
    local slots = manager:slots()
    for index = 0, slots:num_items() - 1 do
        local slot = slots:item_at(index)
        if slot:template_key() == cult_template and slot:active() then
            visit(region, set, slot, index)
        end
    end
end

function native.scan_manager(manager, catalog, jobs)
    visit_cult(manager, function(region, slot_set, slot, slot_index)
        scan_slot(jobs, region, slot_set, slot, slot_index, catalog)
    end)
end

function native.scan(faction, catalog, region_key)
    local jobs = {}
    if faction:is_null_interface() or faction:name() ~= faction_key then return jobs end
    local managers = faction:foreign_slot_managers()
    for index = 0, managers:num_items() - 1 do
        local manager = managers:item_at(index)
        if region_key == nil or manager:region():name() == region_key then
            native.scan_manager(manager, catalog, jobs)
        end
    end
    return jobs
end

local function resolve(job)
    if cm:get_local_faction_name() ~= faction_key or not cult_sets[job.slot_set]
        or type(job.slot_index) ~= "number" or job.slot_index < 0 or job.slot_index % 1 ~= 0 then return end
    local region = cm:get_region(job.region)
    if not region or region:is_null_interface() or region:is_abandoned() or region:cqi() ~= job.region_cqi then return end

    local managers = region:foreign_slot_managers()
    for i = 0, managers:num_items() - 1 do
        local manager = managers:item_at(i)
        if manager:slot_set_key() == job.slot_set and manager:faction():name() == faction_key then
            local slots = manager:slots()
            if job.slot_index < slots:num_items() then
                local slot = slots:item_at(job.slot_index)
                if slot:cqi() == job.slot and slot:template_key() == cult_template and slot:active() then
                    return slot_expression(job)
                end
            end
        end
    end
end

local function same_resource_cost(latest, shown)
    for key, amount in pairs(latest) do
        if amount ~= (shown[key] or 0) then return false end
    end
    for key, amount in pairs(shown) do
        if amount ~= (latest[key] or 0) then return false end
    end
    return true
end

function native.validate(job)
    local slot = resolve(job)
    if not slot or not slot_ready(job, slot) or current_building(job, slot) ~= job.current then
        return false, "slot_changed"
    end

    if job.kind == "remove" then
        if not can_remove(job, slot) then return false, "unavailable" end
        return slot
    end

    local expected_kind = job.current and "upgrade" or "build"
    if job.kind ~= expected_kind or not can_construct(job, slot) then return false, "unavailable" end
    local gold, supplies, turns, affordable, resources = construction_quote(job, slot)
    if not affordable then return false, "unaffordable" end
    if gold ~= job.gold or supplies ~= job.supplies or turns ~= job.turns
        or not same_resource_cost(resources, job.resources or {}) then return false, "quote_changed" end

    return slot
end

function native.issue(job)
    local slot, reason = native.validate(job)
    if not slot then return false, reason end
    local command = job.kind == "remove" and ".Dismantle" or (".Construct(" .. level_expression(slot, job) .. ")")
    common.call_context_command("CcoCampaignSettlement", job.region_cqi, slot .. command)
    return true
end

function native.queued(job)
    local slot = resolve(job)
    if not slot then return false end
    if job.kind == "remove" then
        return query(job.region_cqi, slot .. ".IsDismantling") == true
    end
    return query(job.region_cqi, "(slot = " .. slot .. ") => { IsContextValid(slot.ConstructionItemContext)"
        .. " && !slot.IsDismantling && slot.ConstructionItemContext.BuildingLevelRecordContext.Key == "
        .. string.format("%q", job.level) .. " }") == true
end

return native
