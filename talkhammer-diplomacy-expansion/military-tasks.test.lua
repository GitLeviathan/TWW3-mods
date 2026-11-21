local chunk, err = loadfile("military-tasks.lua")
assert(chunk, "Military directives require an objective module: " .. tostring(err))
local military = chunk()

local function fixture()
    local turn, owner, at_war, reachable, subordinate = 75, "enemy", true, true, true
    local commands, reports, events, state = {}, {}, {}, { data = {} }
    local general = {
        is_null_interface = function() return false end,
        is_wounded = function() return false end,
        is_besieging = function() return false end,
        command_queue_index = function() return 123 end,
    }
    local force = {
        is_army = function() return true end,
        has_general = function() return true end,
        general_character = function() return general end,
    }
    local factions = {}
    for _, key in ipairs({ "player", "sisters", "kislev", "enemy", "other" }) do
        factions[key] = {
            name = function() return key end,
            is_human = function() return key == "player" end,
            is_vassal_of = function(_, player)
                return subordinate and key == "sisters" and player:name() == "player"
            end,
            at_war_with = function(_, faction) return at_war and faction:name() == "enemy" end,
            military_force_list = function()
                return { num_items = function() return 1 end, item_at = function() return force end }
            end,
        }
    end
    local settlement = {}
    local region = {
        name = function() return "fort" end,
        is_null_interface = function() return false end,
        is_abandoned = function() return owner == nil end,
        settlement = function() return settlement end,
        owning_faction = function() return factions[owner] end,
    }
    local cm = {
        get_local_faction_name = function() return "player" end,
        turn_number = function() return turn end,
        get_region = function(_, key) if key == "fort" then return region end end,
        character_can_reach_settlement = function(_, actual_general, actual_settlement)
            assert(actual_general == general and actual_settlement == settlement)
            return reachable
        end,
        attack_region = function(_, lookup, target)
            commands[#commands + 1] = { lookup, target }
        end,
    }
    local core = {}
    function core:add_listener(_, event, condition, action)
        events[event] = function(context)
            if condition == true or condition(context) then action(context) end
        end
    end
    local actions = {}
    local function install()
        return military.install({
            cm = cm, state = state, core = core, actions = actions,
            world = { name_of = function(key) return key end },
            fold = function(line)
                return (line:gsub("[A-Z]", string.lower):gsub("Сёстры", "сёстры"):gsub("Кислеву", "кислеву")
                    :gsub("Форт Оберштир", "форт оберштир"))
            end,
        }, {
            live = function(key) return factions[key] end,
            resolve_faction = function(text)
                if text == "кислеву" or text == "kislev" then return "kislev" end
            end,
            resolve_region = function(text)
                if text == "форт оберштир" or text == "fort oberstyr" then return "fort" end
            end,
            owner_of = function() return owner end,
            place_name = function() return "Fort Oberstyr" end,
            tr = function(en) return en end,
            report = function(key, message)
                assert(key == "sisters")
                reports[#reports + 1] = message
            end,
        })
    end
    return {
        orders = install(), reload = install, state = state, commands = commands,
        reports = reports, actions = actions, cm = cm,
        set_turn = function(value) turn = value end,
        set_owner = function(value)
            owner = value
            events.RegionFactionChangeEvent({ region = function() return region end })
        end,
        set_war = function(value) at_war = value end,
        set_reachable = function(value) reachable = value end,
        set_subordinate = function(value) subordinate = value end,
        ai_turn = function(key)
            events.FactionBeginTurnPhaseNormal({ faction = function() return factions[key or "sisters"] end })
        end,
    }
end

local function message(note, phrase)
    assert(note and note:lower():find(phrase:lower(), 1, true),
        "Expected " .. phrase .. ", received " .. tostring(note))
end

do
    local f = fixture()
    local handled, note = f.orders.handle("sisters", "Сёстры, помогите Кислеву отбить Форт Оберштир", "player", 75)
    assert(handled)
    message(note, "Fort Oberstyr")
    message(note, "kislev")
    message(note, "80")
    assert(#f.commands == 0)
    f.ai_turn("other")
    assert(#f.commands == 0)
    f.ai_turn()
    f.ai_turn()
    assert(#f.commands == 1)
    assert(f.commands[1][1] == "character_cqi:123" and f.commands[1][2] == "fort")
end

do
    local f = fixture()
    local handled, note = f.orders.handle("sisters", "Сёстры, помогите Кислеву отбить Форт Оберштир, за 3 хода", "player", 75)
    assert(handled)
    message(note, "78")
    f.ai_turn()
    f.set_owner("sisters")
    assert(#f.reports == 1)
    message(f.reports[1], "Partial")
    f.orders.start_turn("player", 76)
    assert(#f.reports == 1)
    f.set_turn(77)
    f.set_owner("kislev")
    assert(#f.reports == 2)
    message(f.reports[2], "kislev now controls Fort Oberstyr")
end

do
    local f = fixture()
    for _, line in ipairs({
        "Could you help Kislev retake Fort Oberstyr?",
        "Don't attack Fort Oberstyr.",
        "Help Kislev retake Fort Oberstyr if we can negotiate peace.",
        "Help Kislev reach a deal.",
    }) do
        assert(not f.orders.handle("sisters", line, "player", 75), line)
    end
    f.ai_turn()
    assert(#f.commands == 0)
end

do
    local f = fixture()
    assert(f.orders.handle("sisters", "Help Kislev retake Fort Oberstyr by turn 81.", "player", 75))
    f.set_reachable(false)
    f.ai_turn()
    assert(#f.commands == 0)
    f.orders = f.reload()
    f.set_turn(81)
    f.set_reachable(true)
    f.ai_turn()
    assert(#f.commands == 1)
    f.set_turn(82)
    f.orders.start_turn("player", 82)
    assert(#f.reports == 1)
    message(f.reports[1], "deadline")
    f.ai_turn()
    assert(#f.commands == 1)
end

do
    local f = fixture()
    assert(f.orders.handle("sisters", "Help Kislev retake Fort Oberstyr.", "player", 75))
    f.set_owner("kislev")
    assert(#f.reports == 1)
    message(f.reports[1], "kislev now controls Fort Oberstyr")
    message(f.reports[1], "contribution unverified")
    f.ai_turn()
    assert(#f.commands == 0)
end

do
    local f = fixture()
    assert(f.orders.handle("sisters", "Attack Fort Oberstyr.", "player", 75))
    f.ai_turn()
    f.set_owner("sisters")
    assert(#f.reports == 1)
    message(f.reports[1], "sisters now controls Fort Oberstyr")
end

do
    local f = fixture()
    f.set_war(false)
    local handled, note = f.orders.handle("sisters", "Attack Fort Oberstyr.", "player", 75)
    assert(handled)
    message(note, "already be at war")
    f.ai_turn()
    assert(#f.commands == 0)
end

do
    local f = fixture()
    assert(f.orders.handle("sisters", "Attack Fort Oberstyr.", "player", 75))
    f.set_subordinate(false)
    f.ai_turn()
    assert(#f.commands == 0 and #f.reports == 1)
    message(f.reports[1], "vassal")
end

do
    local f = fixture()
    local handled, note = f.orders.handle("sisters", "Attack Fort Oberstyr by turn 74.", "player", 75)
    assert(handled)
    message(note, "deadline")
    handled, note = f.orders.handle("sisters", "Attack.", "player", 75)
    assert(handled)
    message(note, "settlement")
    f.actions.blocked = true
    handled, note = f.orders.handle("sisters", "Attack Fort Oberstyr.", "player", 75)
    assert(handled)
    message(note, "disabled")
    f.ai_turn()
    assert(#f.commands == 0)
end

do
    local f = fixture()
    assert(f.orders.handle("sisters", "Attack Fort Oberstyr.", "player", 75))
    f.cm.attack_region = function() return false end
    f.ai_turn()
    assert(#f.reports == 1)
    message(f.reports[1], "rejected")
end

print("Military objective tests passed")
