local faction_key = "wh3_dlc24_tze_the_deceivers"
local cult_template = "wh3_dlc24_tze_cult_changeling"
local expansion_bonus = "the_changeling_cult_adjacent_region_expansion_chance"
local prefix = "changeling_cult_tracker_"
local published = {}
local refresh_queued = false

local function settlement_name(region)
    local key = region:name()
    local loc_key = "regions_onscreen_" .. key
    local name = common.get_localised_string(loc_key)
    if not name or name == "" or name == loc_key or name == key then
        return "Соседнее поселение"
    end
    return name
end

local function expansion_targets(region)
    local targets = {}
    local neighbors = region:adjacent_region_list()
    -- Match the eligibility checks and the order used by the game's expansion roll.
    for index = 0, neighbors:num_items() - 1 do
        local neighbor = neighbors:item_at(index)
        local owner = neighbor:owning_faction()
        if not neighbor:is_abandoned() and not owner:is_null_interface() and owner:name() ~= faction_key
            and neighbor:foreign_slot_manager_for_faction(faction_key):is_null_interface() then
            targets[#targets + 1] = settlement_name(neighbor)
        end
    end
    return targets
end

local function publish(region_key, count, tooltip)
    local previous = published[region_key]
    if not previous or previous.tooltip ~= tooltip then
        common.set_context_value(prefix .. "tooltip_" .. region_key, tooltip)
    end
    if not previous or previous.count ~= count then
        common.set_context_value(prefix .. "count_" .. region_key, count)
    end
end

local function refresh()
    if cm:get_local_faction_name(true) ~= faction_key then return end
    local current = {}
    local managers = cm:get_faction(faction_key):foreign_slot_managers()
    for index = 0, managers:num_items() - 1 do
        local manager = managers:item_at(index)
        local slots = manager:slots()
        if slots:num_items() > 0 and slots:item_at(0):template_key() == cult_template then
            local region = manager:region()
            local targets = expansion_targets(region)
            if #targets > 0 then
                local key = region:name()
                local count = tostring(#targets)
                local chance = cm:get_regions_bonus_value(region, expansion_bonus)
                local tooltip = "Доступно для распространения культа: " .. count
                    .. "\n• " .. table.concat(targets, "\n• ")
                    .. "\n\nШанс распространения в начале хода: " .. tostring(chance) .. "%"
                if chance <= 0 then
                    tooltip = tooltip .. "\nБонус к распространению сейчас не действует."
                end
                publish(key, count, tooltip)
                current[key] = {count = count, tooltip = tooltip}
            end
        end
    end
    for key in pairs(published) do
        if not current[key] then publish(key, "", "") end
    end
    published = current
end

local function queue_refresh()
    if refresh_queued then return end
    refresh_queued = true
    cm:callback(function()
        refresh_queued = false
        refresh()
    end, 0.1)
end

cm:add_first_tick_callback(function()
    if cm:get_local_faction_name(true) ~= faction_key then return end
    local function player_faction(context)
        return context:faction():name() == faction_key
    end
    local function player_building(context)
        return context:slot_manager():faction():name() == faction_key
    end
    local events = {
        FactionTurnStart = player_faction,
        FactionTurnEnd = player_faction,
        ForeignSlotBuildingCompleteEvent = player_building,
        ForeignSlotBuildingDismantledEvent = player_building,
        ForeignSlotManagerCreatedEvent = function(context) return context:requesting_faction():name() == faction_key end,
        ForeignSlotManagerRemovedEvent = function(context) return context:owner():name() == faction_key end,
        RegionFactionChangeEvent = function() return true end,
    }
    for event, predicate in pairs(events) do
        core:add_listener(prefix .. event, event, predicate, queue_refresh, true)
    end
    queue_refresh()
end)
