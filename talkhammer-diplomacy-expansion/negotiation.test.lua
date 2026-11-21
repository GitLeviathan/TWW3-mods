local dir = (... or ".") .. "/"
local negotiation = assert(loadfile(dir .. "negotiation.lua"))()
local replies, reports, deferred, formations = {}, {}, {}, {}
local turn, paid, fight, pact = 81, 0, true, false
local owners = { fort = "sisters", sh = "kislev" }
local gold = { player = 10000, kislev = 2000 }
local names = { ["Малус"] = "malus", ["Хелеброн"] = "har", ["Хаг Греф"] = "malus", ["Хар Ганет"] = "har",
    ["Катарин"] = "kislev", ["Сёстры"] = "sisters", ["Кислевом"] = "kislev" }
local places = { ["Форт Оберштир"] = "fort", ["Штайнгарт"] = "sh" }
local factions = {}
for _, key in pairs(names) do
    factions[key] = { treasury = function() return gold[key] or 0 end, is_human = function() return false end,
        is_vassal_of = function() return key ~= "kislev" end, at_war_with = function() return fight end,
        non_aggression_pact_with = function() return pact end, subculture = function() return "elves" end }
end
factions.player = { treasury = function() return gold.player end, is_human = function() return true end }
local calls = {}
local deps = {
    cm = {
        turn_number = function() return turn end,
        get_local_faction_name = function() return "player" end,
        force_make_peace = function(_, a, b) calls[#calls + 1] = "peace:" .. a .. ":" .. b; fight = false end,
        force_non_aggression_pact = function() pact = true end,
        treasury_mod = function(_, key, amount) gold[key] = gold[key] + amount; paid = paid + math.max(amount, 0) end,
        transfer_region_to_faction = function(_, key, receiver)
            if key == "sh" and receiver == "sisters" and calls.block_exchange then return false end
            owners[key] = receiver
        end,
        force_confederation = function(_, a, b)
            formations[#formations + 1] = { a, b }
            calls.confirmed = calls.callback and calls.callback({
                faction = function() return { name = function() return b end } end,
                confederation = function() return { name = function() return a end } end,
            })
        end,
        callback = function(_, cb) deferred[#deferred + 1] = cb end,
    },
    core = { add_listener = function(_, _, _, when, cb)
        calls.callback = function(context) if when(context) then cb(context); return true end end
    end, remove_listener = function() calls.callback = nil end },
    actions = { max_payment = 10000 }, state = { data = {} }, world = { name_of = function(k) return k end },
    fold = function(s) return s:gsub("^Д", "д"):gsub("^П", "п"):gsub("^М", "м") end,
}
local api = {
    tr = function(_, ru) return ru end, live = function(key) return factions[key] end,
    direct = function() return true end,
    resolve_faction = function(raw) return names[raw] end,
    resolve_region = function(raw, holder)
        local region = places[raw]
        return owners[region] == holder and region or nil
    end,
    owner_of = function(region) return owners[region] end,
    place_name = function(region) return region end,
    occupied = function() return false end,
    report = function(key, line) reports[#reports + 1] = { key, line } end,
    ask = function(key, prompt, callback)
        replies[#replies + 1] = { key = key, prompt = prompt, callback = callback }
        return true
    end,
}
local ctl = negotiation.install(deps, api)
local function answer(key, verdict, gold)
    local pending = assert(table.remove(replies, 1))
    assert(pending.key == key)
    pending.callback("Мой ответ.", { verdict = verdict, gold = gold or 0 })
    return pending.callback
end
local function flush()
    while #deferred > 0 do table.remove(deferred, 1)() end
end
local union = "Малус, договорись с Хелеброн о конфедерации. Хар Ганет должен войти в Хаг Греф"
fight = false
assert(ctl.handle("malus", union, "player", turn))
answer("malus", "accept")
assert(#formations == 0)
answer("har", "decline")
assert(#formations == 0)
assert(ctl.handle("malus", union, "player", turn))
answer("malus", "accept")
local duplicate = answer("har", "accept")
duplicate("Повтор", {verdict = "accept", gold = 0})
assert(#formations == 1 and formations[1][1] == "malus" and formations[1][2] == "har")
fight = true
local peace = "Договорись о мире с Катарин. Можешь предложить до 5 000 золота"
assert(ctl.handle("sisters", peace, "player", turn))
answer("sisters", "accept")
answer("kislev", "accept", 5001)
assert(fight and paid == 0)
assert(ctl.handle("sisters", peace, "player", turn))
answer("sisters", "accept")
answer("kislev", "accept", 2500)
flush()
assert(not fight and paid == 2500 and gold.player == 7500 and gold.kislev == 4500)
fight = true
assert(ctl.handle("sisters", "Прекратите войну с Кислевом и заключите пакт о ненападении", "player", turn))
answer("sisters", "accept")
answer("kislev", "accept")
flush()
assert(not fight and pact)
local trade = "Передай Катарин Форт Оберштир, если она уступит тебе Штайнгарт"
assert(ctl.handle("sisters", trade, "player", turn))
answer("sisters", "accept")
answer("kislev", "accept")
local card = assert(ctl.card("sisters"))
assert(owners.fort == "sisters" and owners.sh == "kislev")
assert(not ctl.settle("sisters", true, "wrong"))
calls.block_exchange = true
ctl.settle("sisters", true, card.print)
flush()
assert(owners.fort == "sisters" and owners.sh == "kislev", "The failed exchange must restore the first settlement")
calls.block_exchange = false
assert(ctl.handle("sisters", trade, "player", turn))
answer("sisters", "accept")
answer("kislev", "accept")
card = assert(ctl.card("sisters"))
assert(ctl.settle("sisters", true, card.print))
flush()
assert(owners.fort == "kislev" and owners.sh == "sisters")
fight = true
assert(ctl.handle("sisters", peace, "player", turn))
answer("sisters", "accept")
turn = turn + 1
answer("kislev", "accept", 100)
assert(fight and paid == 2500)
print("Envoys: both decisions, direction, paid peace and budget, pact, exchange rollback and confirmation, stale replies")
