local chronicle_source, russian_source = ...
local turn = 82
local listeners = {}
local names = { morathi = "Культ удовольствий", hellebron = "Хар Ганет", raider = "Налётчики" }
local regions = { old = "Гронд", gift = "Великая Арена", other = "Другой город", failed = "Крепость" }
local function faction(key)
    return { name = function() return key end }
end
local function ownership_event(key, previous, owner)
    return {
        region = function()
            return { name = function() return key end, owning_faction = function() return faction(owner) end }
        end,
        previous_faction = function() return previous and faction(previous) end,
    }
end

local russian = assert(loadstring(russian_source))()
local show_russian = false
local environment = setmetatable({
    core = { add_listener = function(_, _, event, _, callback) listeners[event] = callback end },
    cm = {
        turn_number = function() return turn end,
        get_local_faction_name = function() return "player" end,
    },
    common = { get_localised_string = function(key) return regions[key:match("^regions_onscreen_(.+)$")] or key end },
    TALKHAMMER_U8 = { sub = string.sub, blen = string.len },
    TALKHAMMER_LANG = {
        TS = function(key, english, values)
            local pattern = show_russian and russian[key] or english
            return (pattern:gsub("{(%w+)}", function(name) return values[name] end))
        end,
    },
}, { __index = _G })
local chronicle = setfenv(assert(loadstring(chronicle_source)), environment)()
local state = {
    data = {
        factions = {
            morathi = { history = {
                { turn = 81, speaker = "note", line = "Поселение передано · Культ удовольствий → Гронд → Хар Ганет" },
                { turn = 82, speaker = "note", line = "Предложение отклонено." },
            } },
        },
        chronicle = {
            { t = 81, k = "region", a = "hellebron", b = "morathi", r = "old" },
            { t = 82, k = "region", a = "hellebron", b = "morathi", r = "other" },
        },
        chronicle_survey = { hellebron = { hist = { 3 } } },
    },
}
chronicle.init({
    state = state,
    world = { name_of = function(key) return names[key] end, get = function(key) return names[key] end },
})
local entries = state.data.chronicle
assert(entries[1].k == "settlement_gift" and entries[1].a == "morathi" and entries[1].b == "hellebron")
assert(entries[2].k == "region", "Unverified changes must not be classified as gifts")
local first_prompt = chronicle.text("hellebron")
assert(first_prompt:find("voluntarily gave the settlement of Гронд", 1, true))
assert(first_prompt:find("has gained 3 provinces", 1, true) and not first_prompt:find("the war", 1, true))
show_russian = true
assert(chronicle.describe(entries[1]):find("передала поселение Гронд в дар фракции Хар Ганет", 1, true))
show_russian = false

local function proposal(region)
    return { from = "morathi", to = "hellebron", region = region, campaign = state.data }
end
local gift = proposal("gift")
local change = ownership_event(gift.region, gift.from, gift.to)
chronicle.begin_settlement_gift(gift)
assert(chronicle.is_settlement_gift_event(change), "The reaction handler must recognize the peaceful transfer")
listeners.RegionFactionChangeEvent(change)
assert(#entries == 2, "The engine event alone must not record a conquest or a completed gift")
chronicle.finish_settlement_gift(gift, true)
chronicle.finish_settlement_gift(gift, true)
assert(#entries == 3 and entries[3].k == "settlement_gift")
listeners.RegionFactionChangeEvent(change)
assert(#entries == 3, "A late duplicate engine event must not add a conquest")
assert(chronicle.text(gift.from):find("voluntarily gave the settlement of Великая Арена", 1, true))
assert(chronicle.text(gift.to):find("voluntarily gave the settlement of Великая Арена", 1, true))

local seizure = ownership_event(gift.region, gift.to, "raider")
assert(not chronicle.is_settlement_gift_event(seizure))
listeners.RegionFactionChangeEvent(seizure)
assert(#entries == 4 and entries[4].k == "region" and entries[4].a == "raider")

local failed = proposal("failed")
chronicle.begin_settlement_gift(failed)
chronicle.finish_settlement_gift(failed, false)
local later = ownership_event(failed.region, failed.from, failed.to)
assert(not chronicle.is_settlement_gift_event(later))
listeners.RegionFactionChangeEvent(later)
assert(#entries == 5 and entries[5].k == "region")
print("Gift chronicle: legacy evidence, neutral ownership changes, confirmed gifts and late events passed")
