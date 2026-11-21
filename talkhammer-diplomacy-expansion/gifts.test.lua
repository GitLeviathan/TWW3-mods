local directory = (... or ".") .. "/"
local gifts = assert(loadfile(directory .. "settlement-gifts.lua"))()
local influence = assert(loadfile(directory .. "vassal-influence.lua"))()
local names = { player = "Обманщики", sisters = "Сёстры Сумерек", kislev = "Ледяной двор", malus = "Хаг Греф" }
local cities = { faraway = "Дальняя гавань", home = "Свой город" }
local current_turn, moves, stock_accepts, stock_cases = 80, 0, 0, 0
local confederations, war, player_vassal = 0, false, true
local city_owners = { faraway = "sisters", home = "player" }
local faction_records, region_records, dead = {}, {}, {}
local human = {player = true}
local notes = {}
local listeners = {}
local scheduled
local async_transfer = false

local function list(entries)
    return {
        num_items = function() return #entries end,
        item_at = function(_, index) return entries[index + 1] end,
    }
end

for key in pairs(names) do
    faction_records[key] = {
        is_null_interface = function() return false end,
        is_dead = function() return dead[key] == true end,
        is_human = function() return human[key] == true end,
        is_vassal_of = function(_, other) return key == "sisters" and other:name() == "player" and player_vassal end,
        at_war_with = function() return war end,
        subculture = function() return (key == "sisters" or key == "malus") and "elves" or key end,
        was_confederated = function() return dead[key] == "confederated" end,
        name = function() return key end,
        region_list = function()
            local entries = {}
            for region, owner in pairs(city_owners) do
                if owner == key then entries[#entries + 1] = region_records[region] end
            end
            return list(entries)
        end,
    }
end
for key in pairs(cities) do
    region_records[key] = {
        name = function() return key end,
        is_null_interface = function() return false end,
        owning_faction = function() return faction_records[city_owners[key]] end,
    }
end

local ruler = {
    counterpart = "sisters",
    table_action = function() return nil end,
    ledger_text = function() return "vanilla", "vanilla card" end,
    settle = function() stock_accepts = stock_accepts + 1; return true, "stock" end,
    show_conversation = function() stock_cases = stock_cases + 1 end,
    publish_status = function() end,
}
local cm = {
    get_faction = function(_, key) return faction_records[key] end,
    get_region = function(_, key) return region_records[key] end,
    get_local_faction_name = function() return "player" end,
    turn_number = function() return current_turn end,
    transfer_region_to_faction = function(_, region, receiver)
        moves = moves + 1
        if not async_transfer then city_owners[region] = receiver end
    end,
    callback = function(_, action) scheduled = action end,
    force_confederation = function(_, absorber, absorbed)
        assert(absorber == "malus" and absorbed == "sisters")
        confederations = confederations + 1
        dead[absorbed] = "confederated"
        for key, listener in pairs(listeners) do
            local context = {
                faction = function() return faction_records[absorbed] end,
                confederation = function() return faction_records.kislev end,
            }
            assert(not listener.condition(context))
            context.confederation = function() return faction_records[absorber] end
            assert(listener.condition(context))
            listener.received()
            listeners[key] = nil
        end
    end,
}
local deps = {
    cm = cm, ruler = ruler,
    core = { add_listener = function(_, key, event, condition, received)
        assert(event == "FactionJoinsConfederation")
        listeners[key] = {condition = condition, received = received}
    end, remove_listener = function(_, key) listeners[key] = nil end },
    state = { data = {}, remember = function(_, _, text) notes[#notes + 1] = text end },
    world = { keys = {"player", "sisters", "kislev", "malus"}, name_of = function(key) return names[key] end },
    actions = { blocked = false },
    localise = function(key) return cities[key:match("^regions_onscreen_(.+)$")] end,
    fold = function(text) return (text:gsub("[A-Z]", string.lower)) end,
    language = function() return "ru" end,
    transcript = function() end,
    influence = influence,
}
local controller = gifts.install(deps)
local sentence = 'Передайте поселение «Дальняя гавань» в дар фракции «Ледяной двор».'
local function prepare(text)
    local deal, reason = controller.prepare("sisters", text or sentence, "player", current_turn)
    assert(deal, reason)
    return deal
end
local function offer()
    local deal = prepare()
    assert(controller.finish(deal, { line = "Согласны при вашем подтверждении.", gift_agreed = true }))
    local card = assert(ruler.table_action("sisters", current_turn))
    assert(card.kind == "settlement_gift")
    return card
end
local function accept(card)
    return ruler.settle("sisters", true, {turn = current_turn}, card.print)
end

assert(controller.prepare("sisters", "Как поживает Ледяной двор?", "player", current_turn) == nil)
assert(controller.prepare("sisters", 'Благодарю за «приветствие» и «ответ».', "player", current_turn) == nil)
assert(ruler.settle("sisters", true, {turn = current_turn}))
assert(stock_accepts == 1)
local donor = prepare()
assert(donor.from == "sisters" and donor.to == "kislev" and donor.region == "faraway")
assert(controller.prompt(donor):find("Дальняя гавань", 1, true))
local base_schema = { json_schema = { schema = {
    properties = { action = { enum = {"none", "gift_gold"} } }, required = {"action"},
} } }
local changed = controller.schema(base_schema, donor)
assert(changed.json_schema.schema.properties.gift_agreed.type == "boolean")
assert(changed.json_schema.schema.properties.action.enum[2] == nil)
assert(base_schema.json_schema.schema.properties.action.enum[2] == "gift_gold")
controller.finish(donor, {line = "Отказываюсь.", gift_agreed = false})
assert(moves == 0 and ruler.table_action("sisters", current_turn) == nil)
deps.world.keys = {"sisters", "kislev", "malus"}
local landless = prepare("[дар: Дальняя гавань -> Обманщики]")
assert(landless.from == "sisters" and landless.to == "player")
controller.finish(landless, {line = "Отказываюсь.", gift_agreed = false})
human.sisters = true
local human_gift, human_reason = controller.prepare("sisters", sentence, "player", current_turn)
assert(not human_gift and human_reason)
human.sisters = false

local card = offer()
local _, ledger = ruler.ledger_text("sisters", nil, true)
assert(ledger:find("Сёстры Сумерек", 1, true) and ledger:find("Дальняя гавань", 1, true)
       and ledger:find("Ледяной двор", 1, true))
assert(not ruler.settle("sisters", true, {turn = current_turn}))
assert(moves == 0)
assert(not accept({print = "settlement_gift|different"}))
assert(accept(card))
assert(moves == 1 and city_owners.faraway == "kislev")
assert(not accept(card) and moves == 1)

city_owners.faraway = "sisters"
card = offer()
city_owners.faraway = "player"
assert(not accept(card) and moves == 1)
city_owners.faraway = "sisters"
card = offer()
dead.kislev = true
assert(not accept(card) and moves == 1)
dead.kislev = false

card = offer()
current_turn = current_turn + 1
assert(not accept(card) and ruler.table_action("sisters", current_turn) == nil and moves == 1)
card = offer()
deps.state.data = {}
assert(not accept(card) and moves == 1)

card = offer()
assert(ruler.settle("sisters", false, {turn = current_turn}))
assert(not accept(card) and moves == 1)
card = offer()
deps.actions.blocked = true
assert(not accept(card) and moves == 1)
deps.actions.blocked = false
assert(ruler.settle("sisters", false, {turn = current_turn}))

local outgoing = prepare('[дар: Свой город -> Сёстры Сумерек]')
assert(outgoing.from == "player" and outgoing.to == "sisters")
local wrong, reason = controller.prepare("sisters", '[дар: Свой город -> Ледяной двор]', "player", current_turn)
assert(not wrong and reason)

async_transfer = true
card = offer()
assert(accept(card) and moves == 2 and scheduled)
assert(not accept(card) and moves == 2)
city_owners.faraway = "kislev"
scheduled()
assert(notes[#notes]:find("передано", 1, true))
city_owners.faraway = "sisters"
card = offer()
assert(accept(card) and moves == 3)
scheduled()
assert(notes[#notes]:find("не подтвердила", 1, true) and city_owners.faraway == "sisters")
assert(stock_cases > 0)

local influence_text = "[конфедерация: Сёстры Сумерек -> Хаг Греф] Поддерживаю это соглашение."
local function influence_with(key, agree)
    ruler.counterpart = key
    local deal, reason = controller.prepare(key, influence_text, "player", current_turn)
    assert(deal, reason)
    assert(deal.from == "sisters" and deal.to == "malus")
    assert(controller.finish(deal, {line = "Ответ.", influence_agreed = agree}))
end
war = true
local invalid, message = controller.prepare("sisters", influence_text, "player", current_turn)
assert(not invalid and message)
war = false
player_vassal = false
invalid, message = controller.prepare("malus", influence_text, "player", current_turn)
assert(not invalid and message)
player_vassal = true
influence_with("malus", true)
assert(not ruler.table_action("malus", current_turn))
influence_with("sisters", false)
assert(not ruler.table_action("sisters", current_turn) and confederations == 0)
current_turn = current_turn + 1
local background = assert(controller.prepare("sisters", influence_text, "player", current_turn))
ruler.counterpart = "malus"
assert(controller.finish(background, {line = "Согласна.", influence_agreed = true}))
assert(not ruler.table_action("sisters", current_turn))
influence_with("malus", true)
local confederation = assert(ruler.table_action("malus", current_turn))
assert(confederation.kind == "vassal_confederation")
assert(not ruler.settle("malus", true, {turn = current_turn}))
assert(confederations == 0)
war = true
assert(not ruler.settle("malus", true, {turn = current_turn}, confederation.print))
assert(confederations == 0)
war = false
influence_with("malus", true)
confederation = assert(ruler.table_action("malus", current_turn))
assert(ruler.settle("malus", true, {turn = current_turn}, confederation.print))
assert(confederations == 1)
assert(not ruler.settle("malus", true, {turn = current_turn}, confederation.print))
print("Settlement gifts: consent, confirmation, live ownership, expiry, and delayed transfer passed")
print("Vassal influence: both parties, refusal, eligibility, direction, and confirmation passed")
