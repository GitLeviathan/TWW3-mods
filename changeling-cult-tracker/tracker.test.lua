local faction_key = "wh3_dlc24_tze_the_deceivers"
local context_prefix = "changeling_cult_tracker_"
local slot_template = "wh3_dlc24_tze_cult_changeling"

local function list(items)
    return {
        num_items = function() return #items end,
        item_at = function(_, index) return assert(items[index + 1]) end,
    }
end

local function faction(key)
    return {name = function() return key end, is_null_interface = function() return not key end}
end

local player = faction(faction_key)
local foreign = faction("reikland")
local no_cult = {is_null_interface = function() return true end}

local function region(key, owner, abandoned)
    local result = {owner = owner, neighbors = {}, chance = 0}
    result.name = function() return key end
    result.province_name = function() return result.province or "province_one" end
    result.is_abandoned = function() return abandoned end
    result.owning_faction = function() return result.owner end
    result.adjacent_region_list = function() return list(result.neighbors) end
    result.foreign_slot_manager_for_faction = function(_, key)
        assert(key == faction_key)
        return result.cult or no_cult
    end
    return result
end

local function add_cult(region, template)
    region.cult = {
        is_null_interface = function() return false end,
        region = function() return region end,
        slots = function()
            return list({{template_key = function() return template or slot_template end}})
        end,
    }
    return region.cult
end

local center = region("center", foreign)
local adjacent = region("adjacent", foreign)
local other_adjacent = region("new_settlement", foreign)
local abandoned = region("ruin", foreign, true)
local own = region("own", player)
local vacant_owner = region("no_owner", faction(nil))
local occupied = region("occupied", foreign)
local unrelated = region("unrelated", foreign)
local first_cult = add_cult(center)
local other_cult = add_cult(occupied)
local unrelated_slots = add_cult(unrelated, "allied_outpost")
center.neighbors = {adjacent, other_adjacent, abandoned, own, vacant_owner, occupied, unrelated}
occupied.neighbors = {adjacent}
occupied.chance = 5
unrelated.neighbors = {adjacent}
local cults = {first_cult, other_cult, unrelated_slots}
player.foreign_slot_managers = function() return list(cults) end

local values, listeners, scheduled = {}, {}, {}
local local_faction_key = faction_key
local startup
local writes = 0
local localized = {
    regions_onscreen_adjacent = "Альтдорф",
    regions_onscreen_center = "Первый культ",
    regions_onscreen_occupied = "Второй культ",
}
common = {
    get_localised_string = function(key) return localized[key] or key end,
    set_context_value = function(key, value) writes = writes + 1; values[key] = value end,
}
cm = {
    add_first_tick_callback = function(_, callback) startup = callback end,
    get_local_faction_name = function() return local_faction_key end,
    get_faction = function(_, key) assert(key == faction_key); return player end,
    get_regions_bonus_value = function(_, region, key)
        assert(key == "the_changeling_cult_adjacent_region_expansion_chance")
        return region.chance
    end,
    callback = function(_, callback) scheduled[#scheduled + 1] = callback end,
}
core = {
    add_listener = function(_, _, event, predicate, action)
        listeners[event] = function(context) if predicate(context) then action() end end
    end,
}

local function flush()
    local pending = scheduled
    scheduled = {}
    for _, callback in ipairs(pending) do callback() end
end

assert(loadfile("changeling_cult_tracker.lua"))()
startup()
flush()
local count_key = context_prefix .. "count_center"
local tooltip_key = context_prefix .. "tooltip_center"
local province_count = context_prefix .. "province_count_province_one"
local province_tooltip = context_prefix .. "province_tooltip_province_one"
assert(values[count_key] == "2", "only eligible enemy settlements without a slot manager count")
assert(values[tooltip_key]:find("Альтдорф", 1, true))
assert(values[tooltip_key]:find("0%", 1, true))
assert(not values[tooltip_key]:find("new_settlement", 1, true), "never show an internal region key")
assert(not values[context_prefix .. "count_unrelated"], "an outpost is not a cult")
assert(values[province_count] == "2", "count a target shared by two cults only once")
local _, shared_target_count = values[province_tooltip]:gsub("Альтдорф", "")
assert(shared_target_count == 1, "list a shared target once in the province tooltip")
assert(values[province_tooltip]:find("Первый культ (0%)", 1, true))
assert(values[province_tooltip]:find("Второй культ (5%)", 1, true))

occupied.province = "province_two"
listeners.RegionFactionChangeEvent()
flush()
assert(values[province_count] == "2")
assert(not values[province_tooltip]:find("Второй культ", 1, true), "do not include a cult from another province")
assert(values[context_prefix .. "province_count_province_two"] == "1")
occupied.province = nil
listeners.RegionFactionChangeEvent()
flush()
assert(values[context_prefix .. "province_count_province_two"] == "")

local prior_writes = writes
listeners.RegionFactionChangeEvent()
listeners.RegionFactionChangeEvent()
assert(#scheduled == 1, "coalesce events from the same update")
flush()
assert(writes == prior_writes, "do not republish unchanged values")

center.chance = 10
listeners.ForeignSlotBuildingCompleteEvent({slot_manager = function() return {faction = function() return player end} end})
flush()
assert(values[tooltip_key]:find("10%", 1, true))
assert(values[province_tooltip]:find("Первый культ (10%)", 1, true))

cults[#cults + 1] = add_cult(adjacent)
other_adjacent.owner = player
listeners.ForeignSlotManagerCreatedEvent({requesting_faction = function() return player end})
flush()
assert(values[count_key] == "" and values[tooltip_key] == "", "clear the label when all targets are gone")
assert(values[province_count] == "" and values[province_tooltip] == "", "hide the province badge when no targets remain")

adjacent.cult = nil
table.remove(cults)
listeners.ForeignSlotManagerRemovedEvent({owner = function() return player end})
flush()
assert(values[count_key] == "1", "restored targets return to the label")
assert(values[province_count] == "1")

table.remove(cults, 1)
listeners.ForeignSlotManagerRemovedEvent({owner = function() return player end})
flush()
assert(values[count_key] == "" and values[tooltip_key] == "", "clear the label after removing its cult")

local_faction_key = "other"
local prior_writes = writes
listeners.RegionFactionChangeEvent()
flush()
assert(writes == prior_writes, "do not track non-Changeling players")
print("Cult tracker tests passed")
