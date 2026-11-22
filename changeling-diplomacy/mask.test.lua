local addon, exposure, panel = ...
if type(addon) ~= "table" then addon = dofile("changeling-diplomacy/mask.lua") end
if type(exposure) ~= "table" then exposure = dofile("changeling-diplomacy/mask_exposure.lua") end
if type(panel) ~= "table" then panel = dofile("changeling-diplomacy/mask_panel.lua") end
local player = "wh3_dlc24_tze_the_deceivers"
local form, owner, is_leader = "emp_karl_franz", "reikland", true
local turn, queued, applied, last, ordinary = 7, nil, nil, nil, 0
local listeners, scheduled, in_diplomacy, context_reads = {}, nil, false, 0
local faction_reads = {}
local native_draws, native_accepts, input_text = 0, 0, ""
local panel_visible = false
local ledger_ok = true
local ui_sub, ui_ledger, ui_deal, ui_accept, ui_portrait, ui_lines
local buttons = {}
for _, id in ipairs({ "th_mask_regard", "th_mask_status", "th_mask_deal_heading", "th_mask_ledger_heading",
    "th_mask_toggle", "th_mask_explain", "th_mask_withdraw", "th_mask_insist", "th_mask_confirm",
    "th_mask_preview_next", "th_mask_preview_exit", "speak" }) do
    buttons[id] = {
        SetVisible = function(self, value) self.visible = value end,
        SetStateText = function(self, value) self.text = value end,
        GetStateText = function(self) return self.text end,
        Visible = function(self) return self.visible end,
    }
end
local ui = {
    speak_btn = buttons.speak,
    init = function() return true end,
    deep_find = function(_, id) return buttons[id] end,
    set_sub = function(text) ui_sub = text end,
    set_ledger = function(text) ui_ledger = text; return ledger_ok end,
    set_deal = function(text) ui_deal = text end,
    set_accept = function(text) ui_accept = text end,
    set_image = function(kind, path) if kind == "portrait" then ui_portrait = path end end,
    show_history = function(_, lines) ui_lines = table.concat(lines, "\n"); panel_visible = true; return true end,
    compose_take = function() local text = input_text; input_text = ""; return text end,
}
local factions = { [player] = true, reikland = true, gelt = true, kislev = true }
buttons.speak.visible = true
local ruler = {
    COMMANDS = {}, awaiting = {},
    talk_to = function() ordinary = ordinary + 1 end,
    handle_command = function() end,
    report = function(title, lines) last = table.concat(lines, "\n"); ui.set_accept(nil) end,
    publish_status = function() end,
    label_for = function(key) return key end,
    identity = function(key) return key end,
    snapshot = function(key) return { ok = factions[key], key = key, turn = turn } end,
    describe = function(snapshot) return snapshot.key end,
    persona_block = function() return "proud and cautious" end,
}
ruler.select = function(target) ruler.counterpart = target; return true end
ruler.react = function(target) ruler.counterpart = target end
ruler.show_conversation = function()
    native_draws = native_draws + 1
    ui.mode, panel_visible = "talk", true
    ui.set_accept("ACCEPT")
end
ruler.press_accept = function() native_accepts = native_accepts + 1 end
ruler.header_cache = { gelt = {portrait = "gelt-portrait"}, bystander = {portrait = "bystander-portrait"} }
local live_header_reads = 0
ruler.header_facts = function(key)
    live_header_reads = live_header_reads + 1
    return { portrait = key .. "-portrait", crest = key .. "-crest" }
end
ruler.tick = function() end
local settings = {}
local actions = { blocked = false, CONCLUDE = {} }
ruler.handle_command = function(command)
    if command.cmd == "apply" then actions.blocked = command.text == "off" end
    if command.cmd == "talk" then
        ruler.counterpart = command.text
        ruler.talk_to(command.text, "Sign a pact.")
    end
end
local pacts, access, alliances, trades, wars, absorbed = {}, {}, {}, {}, {}, {}
local masters = {}
local engine_accepts = true
local bonus_accepts, bonuses = true, {}
local function conclude(action, agreements, value)
    return function(from, to)
        applied = { action, from, to }
        if engine_accepts then agreements[from .. "|" .. to] = value end
        return true
    end
end
actions.CONCLUDE["non aggression pact"] = conclude("non_aggression", pacts, true)
actions.CONCLUDE["soft military access"] = conclude("military_access", access, true)
actions.CONCLUDE.vassal = function(vassal, master)
    applied = { "vassal", master, vassal }
    if engine_accepts then masters[vassal] = master end
    return true
end
local break_alliance = conclude("break_alliance", alliances, false)
local state = {
    data = {},
    setting = function(key, fallback) if settings[key] == nil then return fallback end return settings[key] end,
    set_setting = function(key, value) settings[key] = value end,
    load_faction_sheet = function() end,
    character_of = function() return "experienced diplomat" end,
    save = function() end,
}
local at_war = true
local masked_attitude = -20
local war_state_readable = true
local applied_actions = {}
local failed_outcome
local parley = { apply = function(action, from, to)
    if action == failed_outcome then return false end
    applied = { action, from, to }
    applied_actions[#applied_actions + 1] = action
    if action == "peace" then at_war = false end
    if action == "war" then wars[from .. "|" .. to] = true end
    if action == "trade" and engine_accepts then trades[to .. "|" .. from] = true end
    if action == "alliance" and engine_accepts then alliances[to .. "|" .. from] = "military" end
    if action == "defensive_alliance" and engine_accepts then alliances[to .. "|" .. from] = "defensive" end
    return true
end }
local world = { keys = { "reikland", "kislev", "gelt" },
    factions = { reikland = { leader_subtype = "emp_karl_franz" }, kislev = { leader_subtype = "ksl_katarin", subculture = "emp" }, gelt = { subculture = "emp" }, reikland_enemy = {} },
    exists = function(key) return factions[key] or key == "reikland_enemy" end,
    resolve = function(name) if name == "Enemy" then return "reikland_enemy" end end, attitude = function() return masked_attitude end }
local orders = { at_war = function(a, b) if a == "reikland_enemy" or b == "reikland_enemy" then return wars[a .. "|" .. b] == true end; return at_war end }
local function value(kind, key, field)
    context_reads = context_reads + 1
    assert(not in_diplomacy, "Form UI was queried while diplomacy was open")
    assert(kind == "CcoCampaignFaction" and key == player)
    if field == "EquippedShapeshiftFormContext.AgentSubtypeRecordContext.Key" then return form end
    error("Unexpected context query: " .. field)
end
local cm = {
    get_local_faction_name = function() return player end,
    turn_number = function() return turn end,
    callback = function(_, callback) scheduled = callback end,
    get_faction = function(_, key)
        faction_reads[#faction_reads + 1] = key
        return {
            key = key,
            non_aggression_pact_with = function(_, other) return pacts[key .. "|" .. other.key] == true end,
            military_access_pact_with = function(_, other) return access[key .. "|" .. other.key] == true end,
            is_vassal = function() return masters[key] ~= nil end,
            is_vassal_of = function(_, other) return masters[key] == other.key end,
            allied_with = function(_, other) return not not alliances[key .. "|" .. other.key] end,
            military_allies_with = function(_, other) return alliances[key .. "|" .. other.key] == "military" end,
            defensive_allies_with = function(_, other) return alliances[key .. "|" .. other.key] == "defensive" end,
            is_null_interface = function() return false end,
            trade_agreement_with = function(_, other) return trades[key .. "|" .. other.key] == true end,
            at_war_with = function(_, other)
                assert(war_state_readable, "War state unavailable")
                return wars[key .. "|" .. other.key] == true
            end,
            is_dead = function() return absorbed[key] == true end,
            faction_leader = function()
                return { is_null_interface = function() return false end,
                    character_subtype_key = function() return key == owner and is_leader and form or "other" end }
            end,
        }
    end,
    force_non_aggression_pact = function() end,
    force_make_vassal = function() end,
    force_grant_military_access = function() end,
    force_break_non_aggression_pact = function(_, from, to, dissolved)
        assert(dissolved == false); conclude("break_non_aggression", pacts, false)(from, to)
    end,
    force_break_military_access = function(_, from, to, dissolved, hard)
        assert(dissolved == false and hard == false); conclude("break_military_access", access, false)(from, to)
    end,
    force_break_trade_agreement = function(_, from, to) conclude("break_trade", trades, false)(from, to) end,
    force_confederation = function(_, from, to)
        applied = { "confederation", from, to }; if engine_accepts then absorbed[to] = true end
    end,
    force_break_alliance = function(_, from, to) return break_alliance(from, to) end,
    apply_dilemma_diplomatic_bonus = function(_, from, to, bonus)
        bonuses[#bonuses + 1] = { bonus, from, to }
        if not bonus_accepts then return false end
        applied = { bonus, from, to }
    end,
}
local p2 = { post = function(path, request, callback)
    assert(path == "/chat/completions")
    queued = { request = request, callback = callback }
    return "r001"
end }
local core = { add_listener = function(_, id, event, condition, callback)
    listeners[event] = listeners[event] or {}
    listeners[event][id] = { condition = condition, callback = callback }
end }

local native_find, native_match, native_sub = string.find, string.match, string.sub
local u8 = TALKHAMMER_U8 or {
    index_of = function(text, needle, from) return native_find(text, needle, from or 1, true) end,
    sub = native_sub, lower = string.lower,
}
addon.install({
    u8 = u8, cm = cm, core = core, context_value = value, ruler = ruler, state = state, actions = actions,
    world = world, parley = parley, orders = orders, p2 = p2, exposure = exposure, ui = ui, panel = panel,
    json = { decode = function(content) return content end },
})

local function dispatch(event, name)
    local context = { string = name, faction = function() return { name = function() return name end } end }
    for _, listener in pairs(listeners[event] or {}) do
        if listener.condition(context) then listener.callback(context) end
    end
end

local function refresh()
    if scheduled then local callback = scheduled; scheduled = nil; callback() end
end

local function unsafe_pattern() error("The add-on used a native Lua pattern function") end
string.find, string.match = unsafe_pattern, unsafe_pattern
refresh()
in_diplomacy = true
dispatch("PanelOpenedCampaign", "diplomacy_dropdown")
local reads_before = context_reads
ruler.handle_command({ cmd = "mask", text = " \t" })
string.find, string.match = native_find, native_match
assert(context_reads == reads_before, "/mask queried game UI contexts inside diplomacy")
assert(#faction_reads == 1 and faction_reads[1] == "reikland", "/mask read unrelated live factions")
assert(last:find("emp_karl_franz", 1, true), "/mask did not show the equipped form")

dispatch("ComponentLClickUp", "button_shapeshift")
refresh()
assert(context_reads == reads_before, "A form refresh ran while diplomacy was open")
in_diplomacy = false
dispatch("PanelClosedCampaign", "diplomacy_dropdown")
refresh()
assert(context_reads > reads_before, "Closing diplomacy did not refresh the equipped form")
in_diplomacy = true
dispatch("PanelOpenedCampaign", "diplomacy_dropdown")

local function equip()
    in_diplomacy = false
    dispatch("PanelClosedCampaign", "diplomacy_dropdown")
    dispatch("ComponentLClickUp", "button_shapeshift")
    refresh()
    in_diplomacy = true
    dispatch("PanelOpenedCampaign", "diplomacy_dropdown")
end

local function reply(outcome, line)
    local callback = assert(queued).callback
    queued = nil
    callback(nil, { choices = { { message = { content = { line = line or "Agreed.", outcomes = type(outcome) == "table" and outcome or { outcome } } } } } })
end
local function mask_command(command)
    ruler.handle_command({ cmd = "mask", text = command })
end
local function dismiss_narration()
    if queued and queued.request.response_format.json_schema.name == "changeling_mask_incident" then
        reply(nil, "I have questions about this.")
    end
end
local function insist()
    dismiss_narration()
    mask_command("insist")
end
local function assert_pair(action, from, to)
    assert(applied and applied[1] == action and applied[2] == from and applied[3] == to,
        "Diplomacy used the wrong outcome or pair")
end

local deceivers = { key = player, regions = 0 }
local territorial_context = ruler.describe(deceivers, "gelt")
assert(territorial_context:find("cult network", 1, true) and territorial_context:find("not transferable", 1, true),
    "The ordinary dialogue omitted the Deceivers' campaign mechanics")
assert(ruler.describe({ key = "gelt" }, "reikland") == "gelt", "The territorial rules leaked into mask diplomacy")
local court_snapshot = { key = "gelt", faction = { region_list = function()
    return { num_items = function() return 1 end, item_at = function()
        return { name = function() return "gelt_capital" end }
    end }
end } }
assert(ruler.describe(court_snapshot, player):find("Settlements currently owned: gelt_capital", 1, true))

faction_reads = {}
ruler.talk_to("gelt", "Let us sign a peace treaty.")
assert(queued.request.response_format.json_schema.name == "changeling_mask_reply")
assert(string.find(queued.request.messages[2].content, "reikland", 1, true))
assert(not string.find(queued.request.messages[2].content, player, 1, true))
string.find, string.match = unsafe_pattern, unsafe_pattern
reply("peace", " \tСогласна.\r\n")
string.find, string.match = native_find, native_match
assert(last:find("\nСогласна.\n", 1, true), "The reply text was not trimmed")
assert_pair("peace", "reikland", "gelt")
for _, key in ipairs(faction_reads) do
    assert(key == "reikland" or key == "gelt", "Masked dialogue read an unrelated live faction")
end

ruler.talk_to("gelt", "I withdraw our assurances.")
reply("cool")
assert_pair(-2, "reikland", "gelt")

applied = nil
ruler.talk_to("gelt", "I ask for a treaty.")
form, owner = "ksl_katarin", "kislev"
equip()
reply("peace")
assert(not applied, "A reply from a previous disguise was applied")

at_war = false
ruler.talk_to("gelt", "We now speak for Kislev.")
reply("war")
mask_command("confirm")
assert_pair("war", "gelt", "kislev")

applied = nil
at_war = true
actions.blocked = true
ruler.talk_to("gelt", "Will you accept peace?")
reply("peace")
assert(not applied, "TalkHammer /apply off was bypassed")
actions.blocked = false

is_leader = false
ruler.talk_to("gelt", "A hero should not commit any faction.")
assert(not queued and ordinary == 0)
is_leader = true
ruler.talk_to("kislev", "I cannot negotiate with my own faction.")
assert(not queued and ordinary == 0)

ruler.handle_command({ cmd = "mask", text = "off" })
ruler.talk_to("gelt", "This goes through normal TalkHammer.")
assert(ordinary == 1 and not queued)
ruler.handle_command({ cmd = "mask", text = "on" })
form = nil
equip()
ruler.talk_to("gelt", "No form selected.")
assert(ordinary == 2 and not queued)

local function has_outcome(wanted)
    for _, outcome in ipairs(queued.request.response_format.json_schema.schema.properties.outcomes.items.enum) do
        if outcome == wanted then return true end
    end
    return false
end

form, owner, at_war = "ksl_katarin", "kislev", false
equip()
ruler.talk_to("gelt", "Let us sign a non-aggression pact.")
assert(has_outcome("non_aggression"), "A new pact is unavailable in peacetime")
assert(has_outcome("military_access"), "Military access is unavailable in peacetime")
assert(not has_outcome("break_alliance"), "Alliance break was offered without an alliance")
reply("non_aggression")
assert_pair("non_aggression", "gelt", "kislev")
assert(last:find("Заключён договор о ненападении.", 1, true))

ruler.talk_to("gelt", "Grant Kislev military access.")
assert(not has_outcome("non_aggression"), "An existing pact was offered again")
reply("military_access")
assert_pair("military_access", "gelt", "kislev")

for _, alliance in ipairs({ "defensive", "military" }) do
    alliances["gelt|kislev"] = alliance
    ruler.talk_to("gelt", "Break your alliance with Kislev.")
    assert(has_outcome("break_alliance"), "An existing alliance could not be broken")
    assert(not has_outcome("military_access"), "Existing access was offered again")
    reply("break_alliance")
    assert_pair("break_alliance", "gelt", "kislev")
    assert(last:find("Союз расторгнут.", 1, true))
end

access["gelt|kislev"] = false
engine_accepts = false
ruler.talk_to("gelt", "Grant Kislev access again.")
reply("military_access")
assert_pair("military_access", "gelt", "kislev")
assert(last:find("Игра не подтвердила изменение договора.", 1, true), "A refused treaty was reported as successful")
engine_accepts = true

applied = nil
ruler.talk_to("gelt", "Grant Kislev access again.")
at_war = true
reply("military_access")
assert(not applied, "A deal was applied after war began")
ruler.talk_to("gelt", "Can we sign treaties in wartime?")
assert(has_outcome("military_access") and not has_outcome("break_alliance"))
reply("military_access")
assert(not applied, "A post-peace outcome was applied without peace")

at_war = false
actions.blocked = true
alliances["gelt|kislev"] = "military"
ruler.talk_to("gelt", "Break your alliance with Kislev.")
assert(not has_outcome("break_alliance"), "Alliance break bypassed /apply off")
reply("break_alliance")
assert(not applied, "A blocked alliance was broken")

actions.blocked = false
world.factions.gelt.is_human = true
ruler.talk_to("gelt", "Break your alliance with Kislev.")
assert(not has_outcome("break_alliance"), "Alliance break was offered against a human faction")
reply("break_alliance")
assert(not applied, "A human faction was affected by a masked treaty")

world.factions.gelt.is_human = false
ruler.talk_to("gelt", "Kislev declares war.")
assert(has_outcome("declare_war"), "The visitor cannot declare war")
reply("declare_war")
mask_command("confirm")
assert_pair("war", "kislev", "gelt")

ruler.talk_to("gelt", "Kislev grants you military access.")
reply("grant_military_access")
assert_pair("military_access", "kislev", "gelt")
alliances["gelt|kislev"], access["gelt|kislev"] = nil, true
for _, outcome in ipairs({ "break_non_aggression", "break_trade", "break_military_access_incoming", "break_military_access_outgoing" }) do
    if outcome == "break_trade" then trades["gelt|kislev"] = true end
    ruler.talk_to("gelt", "Cancel this agreement.")
    assert(has_outcome(outcome), "Existing agreement cannot be cancelled: " .. outcome)
    reply(outcome)
    if outcome == "break_non_aggression" then insist() end
end
assert_pair("break_military_access", "kislev", "gelt")
assert(not pacts["gelt|kislev"] and not trades["gelt|kislev"] and not access["gelt|kislev"] and not access["kislev|gelt"])

ruler.talk_to("gelt", "Attack them. [цель: unknown]")
assert(not queued, "An unknown third faction reached Codex")
ruler.talk_to("gelt", "Attack them. [цель: Enemy] [цель: reikland]")
assert(not queued, "An ambiguous third faction reached Codex")
ruler.talk_to("gelt", "Attack Enemy.")
assert(not has_outcome("attack_third"), "The model received an unconfirmed third party")
reply("none")
ruler.talk_to("gelt", "Attack them. [цель: Enemy]")
assert(has_outcome("attack_third"), "Named third-party attack is unavailable")
reply("attack_third")
mask_command("confirm")
assert_pair("war", "gelt", "reikland_enemy")
ruler.talk_to("gelt", "Kislev will join your war. [цель: Enemy]")
assert(has_outcome("join_recipient_war"), "The visitor cannot join the recipient war")
reply("join_recipient_war")
assert(last:find("Вступает в войну — kislev", 1, true)
    and last:find("На стороне — gelt", 1, true) and last:find("Против — reikland_enemy", 1, true))
mask_command("confirm")
assert_pair("war", "kislev", "reikland_enemy")
wars["gelt|reikland_enemy"] = false
ruler.talk_to("gelt", "Join our war. [цель: Enemy]")
assert(has_outcome("join_visitor_war"), "The recipient cannot join the visitor war")
reply("join_visitor_war")
assert(last:find("Вступает в войну — gelt", 1, true) and last:find("На стороне — kislev", 1, true))
mask_command("confirm")
assert_pair("war", "gelt", "reikland_enemy")

at_war, applied_actions = true, {}
ruler.talk_to("gelt", "Peace in exchange for trade.")
assert(has_outcome("peace") and has_outcome("trade"), "A peace-and-trade package was not offered")
reply({"trade", "peace"})
assert(table.concat(applied_actions, "|") == "peace|trade", "Peace was not applied before trade")

applied, applied_actions = nil, {}
ruler.talk_to("gelt", "Conclude an alliance and declare war on us.")
reply({"alliance", "declare_war"})
assert(not applied and #applied_actions == 0, "A contradictory package was applied")

at_war, applied_actions, failed_outcome = true, {}, "trade"
ruler.talk_to("gelt", "Peace and trade.")
reply({"peace", "trade"})
assert(table.concat(applied_actions, "|") == "peace", "Partial settlement was not preserved")
assert(last:find("частично", 1, true), "Partial settlement was not reported")
failed_outcome = nil

ruler.talk_to("gelt", "Hello.")
assert(not has_outcome("confederate"), "Confederation was offered without a request")
reply("none")
world.factions.gelt.subculture = "other"
ruler.talk_to("gelt", "Join the confederation of Kislev.")
assert(not has_outcome("confederate"), "Confederation was offered across subcultures")
reply("none")
world.factions.gelt.subculture = "emp"
ruler.talk_to("gelt", "Join the confederation of Kislev.")
assert(has_outcome("confederate"), "Same-subculture confederation was unavailable")
reply("confederate")
mask_command("confirm")
assert_pair("confederation", "kislev", "gelt")
absorbed.gelt = nil
ruler.talk_to("gelt", "Kislev will join your confederation.")
reply("join_confederation")
assert(last:find("Поглощает — gelt", 1, true) and last:find("Входит в состав — kislev", 1, true))
mask_command("confirm")
assert_pair("confederation", "gelt", "kislev")

local function negotiate(target, text, outcome)
    applied, applied_actions = nil, {}
    ruler.talk_to(target, text)
    reply(outcome)
end

form, owner, turn, at_war = "emp_karl_franz", "reikland", 20, false
absorbed.kislev, pacts["gelt|reikland"] = nil, nil
state.data = {}
equip()
negotiate("gelt", "Sign a pact with Reikland.", "non_aggression")
assert(pacts["gelt|reikland"])

alliances["reikland|reikland_enemy"] = "military"
for _ = 1, 2 do
    wars["gelt|reikland_enemy"], wars["reikland|reikland_enemy"] = false, false
    negotiate("gelt", "Attack my ally. [цель: Enemy]", "attack_third")
    assert(not applied and last:find("Двор требует объяснений", 1, true), "A single strong clue did not trigger scrutiny")
    mask_command("confirm")
    assert(not applied, "Confirmation skipped the explanation")
    dismiss_narration()
    mask_command("insist")
    assert_pair("war", "gelt", "reikland_enemy")
end

access["gelt|reikland"] = nil
negotiate("gelt", "Cancel our pact and grant access.", { "military_access", "break_non_aggression" })
assert(not applied and pacts["gelt|reikland"] and not access["gelt|reikland"],
    "Two different clues did not pause every term of a deal before any engine call")
assert(last:find("/mask withdraw", 1, true))
dismiss_narration()
mask_command("withdraw")
assert(not applied and pacts["gelt|reikland"] and not access["gelt|reikland"])

negotiate("gelt", "Cancel the pact.", "break_non_aggression")
assert(not applied and pacts["gelt|reikland"], "Withdrawal cleared the earlier confirmed clue")
dismiss_narration()
mask_command("explain Grant access and keep the pact.")
assert(queued and queued.request.messages[2].content:find("Grant access and keep the pact.", 1, true))
reply("military_access")
assert_pair("military_access", "gelt", "reikland")
assert(pacts["gelt|reikland"], "Clarifying a deal changed the original terms")

negotiate("gelt", "Cancel the pact again.", "break_non_aggression")
dismiss_narration()
mask_command("insist")
assert(not applied and pacts["gelt|reikland"] and last:find("разоблач", 1, true))
dismiss_narration()
for _, blocked_turn in ipairs({ 20, 24 }) do
    turn = blocked_turn
    ruler.talk_to("gelt", "Cancel the pact.")
    assert(not queued and pacts["gelt|reikland"], "An exposed form negotiated during its block")
end
turn = 25
negotiate("gelt", "Cancel the pact.", "break_non_aggression")
assert_pair("break_non_aggression", "gelt", "reikland")
assert(not pacts["gelt|reikland"], "An expired exposure still blocked a deal")

local function prepare_peace_reversal(court)
    local pair_key = court .. "|" .. owner
    at_war, pacts[pair_key], trades[pair_key], alliances[pair_key] = true, nil, nil, nil
    negotiate(court, "Conclude peace.", "peace")
    assert_pair("peace", owner, court)
    negotiate(court, "Sign a pact.", "non_aggression")
    negotiate(court, "Break the pact.", "break_non_aggression")
    dismiss_narration()
    mask_command("insist")
    assert_pair("break_non_aggression", court, owner)
    negotiate(court, "We declare war.", "declare_war")
    assert(not applied, "War after a recent peace did not pause on the second clue")
    dismiss_narration()
end

local function change_form(subtype, faction)
    form, owner = subtype, faction
    equip()
end

local function copy_save(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = copy_save(item) end
    return copy
end

state.data, bonuses, turn = {}, {}, 40
for _, key in ipairs({ "defensive_ally", "military_ally", "bystander", "human_ally" }) do
    factions[key] = true
    world.factions[key] = { is_human = key == "human_ally" }
    world.keys[#world.keys + 1] = key
end
alliances["gelt|defensive_ally"] = "defensive"
alliances["gelt|military_ally"] = "military"
alliances["gelt|human_ally"] = "military"

prepare_peace_reversal("gelt")
mask_command("insist")
dismiss_narration()
assert(#bonuses == 0, "One exposed form caused a scandal")
change_form("ksl_katarin", "kislev")
prepare_peace_reversal("gelt")
mask_command("insist")
assert(applied and applied[1] == -4 and applied[2] == player and applied[3] == "gelt",
    "A second independent exposure did not apply the scandal penalty between the court and the Deceivers")
assert(#bonuses == 1, "The same court applied the scandal penalty more than once")
dismiss_narration()
mask_command("insist")
assert(#bonuses == 1, "Reusing the response command applied the penalty twice")

state.data = copy_save(state.data)
negotiate("defensive_ally", "Sign a pact.", "non_aggression")
assert(not applied and last:find("gelt", 1, true), "A defensive ally lost its warning after reloading the save")
dismiss_narration()
mask_command("withdraw")
negotiate("bystander", "Sign a pact.", "non_aggression")
assert_pair("non_aggression", "bystander", "kislev")
negotiate("human_ally", "Hello.", "none")
assert(not last:find("/mask insist", 1, true))
assert(not exposure.pair(state.data, exposure.form_key({ subtype = form, faction = owner }), "human_ally").warning,
    "The scandal warned a human ally")

for _, identity in ipairs({ { "ksl_katarin", "kislev" }, { "emp_karl_franz", "reikland" } }) do
    change_form(identity[1], identity[2])
    negotiate("military_ally", "Sign a pact.", "non_aggression")
    assert(not applied and last:find("gelt", 1, true), "A military ally was not warned about both forms")
    dismiss_narration()
    mask_command("insist")
    assert_pair("non_aggression", "military_ally", owner)
    negotiate("military_ally", "Break the pact.", "break_non_aggression")
    assert(not applied, "The warning plus a new local clue did not suspend the deal")
    dismiss_narration()
    mask_command("insist")
    assert(not applied and last:find("разоблач", 1, true))
    dismiss_narration()
end
assert(#bonuses == 1, "Two exposures based on warnings cascaded into another scandal")

turn = 45
negotiate("defensive_ally", "Sign a pact.", "non_aggression")
assert_pair("non_aggression", "defensive_ally", "reikland")
prepare_peace_reversal("military_ally")
mask_command("insist")
dismiss_narration()
assert(#bonuses == 1)
change_form("ksl_katarin", "kislev")
prepare_peace_reversal("military_ally")
bonus_accepts = false
mask_command("insist")
assert(#bonuses == 2 and bonuses[2][2] == player and bonuses[2][3] == "military_ally")
assert(not applied and last:find("разоблач", 1, true) and last:find("отклонила", 1, true),
    "A refused penalty lost the exposure or was reported as applied")
dismiss_narration()
ruler.talk_to("military_ally", "Try the exposed form again.")
assert(not queued, "A failed scandal penalty reopened a blocked form")
bonus_accepts = true

turn, state.data = 60, {}
prepare_peace_reversal("gelt")
ruler.select("bystander")
ruler.select("gelt")
mask_command("insist")
assert(not applied and not queued and not last:find("разоблач", 1, true),
    "Switching away and back let the player confirm an old check")

for _, invalidate in ipairs({
    function() turn = turn + 1 end,
    function() state.data = copy_save(state.data) end,
    function() change_form("emp_karl_franz", "reikland") end,
    function() mask_command("off"); mask_command("on") end,
    function()
        ruler.handle_command({ cmd = "apply", text = "off" })
        ruler.handle_command({ cmd = "apply", text = "on" })
    end,
}) do
    state.data = {}
    prepare_peace_reversal("gelt")
    invalidate()
    mask_command("insist")
    assert(not applied and not queued and not last:find("разоблач", 1, true),
        "A check could be confirmed after its session changed")
end

state.data, at_war, failed_outcome = {}, true, "trade"
negotiate("gelt", "Trade and peace.", { "trade", "peace" })
assert(#applied_actions == 1 and applied_actions[1] == "peace")
failed_outcome = nil
alliances[owner .. "|reikland_enemy"] = "military"
wars[owner .. "|reikland_enemy"], wars["gelt|reikland_enemy"] = false, false
negotiate("gelt", "Attack our ally. [цель: Enemy]", "attack_third")
insist()
assert_pair("war", "gelt", "reikland_enemy")
trades["gelt|" .. owner] = true
negotiate("gelt", "Cancel the trade agreement signed separately.", "break_trade")
assert_pair("break_trade", "gelt", owner)
negotiate("gelt", "We declare war.", "declare_war")
assert(not applied and last:find("Двор требует объяснений", 1, true),
    "The successful peace in a partial plan did not contribute a clue")
dismiss_narration()
mask_command("withdraw")

state.data = {}
local form_key = exposure.form_key({ subtype = form, faction = owner })
exposure.warn(state.data, "defensive_ally", { form_key }, "gelt", turn)
exposure.warn(state.data, "defensive_ally", { form_key }, "military_ally", turn)
pacts["defensive_ally|" .. owner] = nil
negotiate("defensive_ally", "Sign a pact.", "non_aggression")
assert(not applied, "Two warnings did not prompt a check")
dismiss_narration()
mask_command("insist")
assert_pair("non_aggression", "defensive_ally", owner)

applied, pacts["bystander|" .. owner] = nil, nil
ruler.handle_command({ cmd = "talk", text = "bystander" })
reply("non_aggression")
assert(applied and pacts["bystander|" .. owner],
    "Selecting a different court and speaking in one command cancelled the new dialogue")

turn, state.data, at_war = 70, {}, false
alliances[owner .. "|reikland_enemy"] = "military"
wars[owner .. "|reikland_enemy"], wars["gelt|reikland_enemy"] = false, false
negotiate("gelt", "Attack my ally. [цель: Enemy]", "attack_third")
dismiss_narration()
mask_command("insist")
alliances["gelt|" .. owner], pacts["gelt|" .. owner] = "defensive", nil
engine_accepts = false
negotiate("gelt", "Upgrade our alliance and sign a pact.", { "alliance", "non_aggression" })
assert(applied and applied[1] == "alliance" and applied[2] == owner and applied[3] == "gelt",
    "A silent alliance refusal allowed a later term to execute")
assert(last:find("Игра не подтвердила", 1, true), "A silent alliance refusal was reported as signed")
engine_accepts = true
negotiate("gelt", "Break the defensive alliance.", "break_alliance")
assert_pair("break_alliance", "gelt", owner)

state.data, pacts["gelt|" .. owner] = {}, nil
wars[owner .. "|reikland_enemy"], wars["gelt|reikland_enemy"] = false, false
negotiate("gelt", "Sign a pact.", "non_aggression")
negotiate("gelt", "Attack my ally. [цель: Enemy]", "attack_third")
dismiss_narration()
mask_command("insist")
access["gelt|" .. owner] = nil
negotiate("gelt", "Cancel our pact and grant access.", { "military_access", "break_non_aggression" })
assert(not applied)
dismiss_narration()
parley.bound = function(from, to)
    if from == "gelt" and to == owner then return "Vassal obligations" end
end
mask_command("insist")
assert(not applied and not queued and pacts["gelt|" .. owner] and last:find("недоступны", 1, true),
    "New obligations did not cancel a suspended deal")
parley.bound = nil

state.data = {}
prepare_peace_reversal("gelt")
ruler.react("bystander")
ruler.react("gelt")
mask_command("insist")
assert(not applied and not queued, "Reactions that switched the court let an old check expose a form")

state.data = {}
ui.frame = { Visible = function() return panel_visible end }
ui.panel, ui.label = ui.frame, {}
ui.init()
local header_reads_before = live_header_reads
dispatch("PanelOpenedCampaign", "diplomacy_dropdown")
ruler.show_conversation("gelt")
string.find = function() error("The campaign's native find must stay out of the masked draw") end
ruler.tick()
string.find = native_find
assert(live_header_reads == header_reads_before, "Drawing while diplomacy is open must not call the CCO header reader")
do
    local get_faction = cm.get_faction
    cm.get_faction = function()
        return { faction_leader = function()
            return { character_subtype_key = function() return "wh2_dlc10_hef_alarielle" end }
        end }
    end
    local facts = ruler.header_facts("wh2_main_hef_avelorn")
    cm.get_faction = get_faction
    assert(facts.portrait:find("hef_alarielle_campaign_0.png", 1, true)
        and facts.crest == "ui/flags/wh2_main_hef_avelorn/mon_256.png")
end
assert(native_draws == 0 and ui_portrait == "gelt-portrait" and ui_sub:find(owner, 1, true),
    "Opening a masked audience used the ordinary conversation view")
assert(buttons.th_mask_regard.visible and buttons.th_mask_regard.text:find(owner, 1, true)
    and buttons.th_mask_regard.text:find("-20", 1, true), "The header must tie the attitude to the masked faction")
assert(ui_sub:find("От имени:", 1, true) and buttons.th_mask_deal_heading.visible,
    "The active speaker and deal heading belong to the masked view")
for _, example in ipairs({ { 181.24761962891, "181" }, { -19.6, "-20" }, { -0.1, "0" }, { nil, "—" } }) do
    masked_attitude = example[1]
    ruler.show_conversation("gelt")
    ruler.tick()
    assert(buttons.th_mask_regard.text == "Отношение к " .. owner .. " · " .. example[2],
        "The masked header must show the rounded attitude or a dash")
end
masked_attitude = -20
ruler.show_conversation("bystander")
assert(native_draws == 0 and not ui_accept, "An old ordinary reply replaced the active masked court")
ruler.press_accept()
assert(native_accepts == 0 and not ui_accept, "Ordinary ACCEPT could act while the mask view was open")

local key = form .. "|" .. owner .. "|gelt"
state.data.mask_diplomacy[key].history[1] = "Legacy conversation"
negotiate("gelt", "Masked greeting.", "none")
ruler.tick()
assert(ui_lines:find("Masked greeting.", 1, true) and ui_lines:find("Agreed.", 1, true),
    "The masked transcript did not display both sides")
assert(type(state.data.mask_diplomacy[key].history[2]) == "string", "The UI wrote records older builds cannot read")
ruler.show_conversation("gelt")
ruler.tick()
assert(ui_lines:find("Legacy conversation", 1, true), "The panel dropped the old saved history")
change_form("ksl_katarin", "kislev")
ruler.tick()
assert(not ui_lines:find("Masked greeting.", 1, true), "Switching masks exposed another mask's conversation")
assert(ui_sub == "От имени: kislev", "The header kept the previous speaker after changing masks")

local function click(button)
    dispatch("ComponentLClickUp", "th_mask_" .. button)
    ruler.tick()
end
assert(buttons.th_mask_toggle.visible and buttons.th_mask_toggle.text == "Снять маску")
click("toggle")
assert(native_draws == 1 and ui_accept == "ACCEPT" and buttons.th_mask_toggle.visible
    and buttons.th_mask_toggle.text == "Надеть маску", "The toggle did not restore ordinary conversation")
assert(not buttons.th_mask_deal_heading.visible and not buttons.th_mask_regard.visible,
    "Ordinary diplomacy kept the mask layout visible")
assert(buttons.speak.visible, "Ordinary diplomacy must retain its send action")
ruler.press_accept()
assert(native_accepts == 1)
click("toggle")
assert(native_draws == 1 and not ui_accept and buttons.th_mask_toggle.text == "Снять маску")
assert(ui_sub == "От имени: kislev")

prepare_peace_reversal("gelt")
ruler.tick()
assert(buttons.th_mask_explain.visible and buttons.th_mask_withdraw.visible and buttons.th_mask_insist.visible)
assert(ui_deal:find("Объявляет войну — " .. owner, 1, true), "The panel did not show what the player was asked to confirm")
assert(not ui_lines:find("Объявляет войну — ", 1, true) and not buttons.speak.visible,
    "The check must leave the terms in the right column and use the explanation action")
assert(ui_lines:find("I have questions about this.", 1, true) and not ui_ledger:find("I have questions about this.", 1, true),
    "The court's spoken reaction replaced part of the clues block")
click("explain")
assert(not queued and buttons.th_mask_explain.visible, "Empty clarification closed the check")
assert(ui_ledger:find("недавнего мира", 1, true), "The clarification hint hid the evidence")
assert(ui_lines:find("Введи новое предложение", 1, true) and not ui_ledger:find("Введи новое предложение", 1, true),
    "The command hint was not kept in the conversation feed")
input_text = "Let us sign a fresh pact."
click("explain")
assert(queued.request.messages[2].content:find("Let us sign a fresh pact.", 1, true))
reply("non_aggression")
ruler.tick()
assert(not buttons.th_mask_insist.visible and pacts["gelt|" .. owner], "Clarification did not settle its own deal")

negotiate("gelt", "We declare war.", "declare_war")
dismiss_narration()
ruler.tick()
click("withdraw")
assert(not buttons.th_mask_insist.visible and not applied, "Withdraw did not cancel the deal")

negotiate("gelt", "We declare war.", "declare_war")
dismiss_narration()
ruler.tick()
dispatch("ComponentLClickUp", "th_mask_insist")
turn = turn + 1
ruler.tick()
assert(not applied and not queued and not buttons.th_mask_insist.visible, "A queued click applied a stale decision")
negotiate("gelt", "We declare war.", "declare_war")
dismiss_narration()
ruler.tick()
click("insist")
assert(not applied and not buttons.th_mask_insist.visible and ui_ledger:find("Облик раскрыт", 1, true),
    "Insist did not use the existing exposure rule")
dismiss_narration()

state.data = {}
ruler.talk_to("gelt", "Wait for a reply.")
ruler.tick()
assert(ui_lines:find("обдумывает", 1, true))
click("toggle")
assert(ui_accept == "ACCEPT")
reply("none")
ruler.tick()
assert(ui_accept == "ACCEPT", "A stale masked response cleared the ordinary panel after switching off")

click("toggle")
ruler.talk_to("gelt", "Reply after the panel closes.")
ruler.tick()
panel_visible = false
reply("none")
ruler.tick()
assert(not panel_visible, "A masked response reopened a panel that the player had closed")
ruler.show_conversation("gelt")
ruler.tick()
assert(ui_lines:find("Reply after the panel closes.", 1, true))
ruler.react("bystander")
assert(ruler.mask_speak_ready and not ruler.mask_speak_ready(),
    "SPEAK could address a court that the displayed panel had not switched to")
ruler.tick()
assert(ui_portrait == "bystander-portrait" and ruler.mask_speak_ready(),
    "The visible masked panel did not follow a new counterpart")
panel_visible = false
mask_command("")
ruler.tick()
assert(panel_visible and ui_lines:find("Облик", 1, true), "The explicit /mask status was lost with a closed panel")
panel_visible = false
mask_command("off")
ruler.tick()
assert(panel_visible and buttons.th_mask_toggle.text == "Надеть маску",
    "Explicit /mask off did not restore the ordinary panel and toggle")

state.data, at_war, turn = {}, false, 85
absorbed[owner], absorbed.gelt = nil, nil
ruler.select("gelt")
mask_command("on")
ruler.tick()
negotiate("gelt", "Declare war on us.", "war")
assert(not applied, "A declaration of war reached the engine before the player confirmed")
ruler.tick()
assert(ui_deal:find("Объявляет войну — gelt", 1, true) and ui_deal:find("Цель — " .. owner, 1, true),
    "The card did not name the attacker and defender")
assert(buttons.th_mask_confirm.visible and buttons.th_mask_confirm.text == "Подтвердить"
    and buttons.th_mask_withdraw.text == "Отказаться"
    and not buttons.th_mask_insist.visible and not buttons.th_mask_explain.visible, "The card showed the wrong decisions")
click("withdraw")
assert(not applied and not buttons.th_mask_confirm.visible, "Rejecting a card did not cancel the war")

negotiate("gelt", "We declare war.", "declare_war")
ruler.tick()
assert(ui_deal:find("Объявляет войну — " .. owner, 1, true) and ui_deal:find("Цель — gelt", 1, true))
click("confirm")
assert_pair("war", owner, "gelt")
assert(#applied_actions == 1 and not buttons.th_mask_confirm.visible)
mask_command("confirm")
assert(#applied_actions == 1, "A repeated confirmation applied the same war twice")

access["gelt|" .. owner] = nil
wars["gelt|reikland_enemy"], wars[owner .. "|reikland_enemy"] = false, false
negotiate("gelt", "Attack Enemy and grant us passage. [цель: Enemy]", { "attack_third", "military_access" })
ruler.tick()
assert(not applied and not access["gelt|" .. owner], "A term escaped the card's confirmation")
assert(ui_deal:find("Цель — reikland_enemy", 1, true) and ui_deal:find("Военный доступ", 1, true))
wars["gelt|reikland_enemy"] = true
click("confirm")
assert(not applied and not access["gelt|" .. owner], "A stale war card applied another term of its package")

negotiate("gelt", "Enter our confederation.", "confederate")
ruler.tick()
assert(not applied and ui_deal:find("Поглощает — " .. owner, 1, true)
    and ui_deal:find("Входит в состав — gelt", 1, true))
dispatch("ComponentLClickUp", "th_mask_confirm")
turn = turn + 1
ruler.tick()
assert(not applied and not absorbed.gelt and not buttons.th_mask_confirm.visible)

exposure.warn(state.data, "gelt", { exposure.form_key({ subtype = form, faction = owner }) }, "bystander", turn)
negotiate("gelt", "We declare war.", "declare_war")
dismiss_narration()
ruler.tick()
assert(not applied and buttons.th_mask_insist.text == "Настоять", "An exposure check was replaced by a normal card")
mask_command("confirm")
assert(not applied, "A plain confirmation bypassed an exposure check")
click("insist")
assert_pair("war", owner, "gelt")
assert(not buttons.th_mask_insist.visible, "The exposure check required a second confirmation")

state.data, pacts["gelt|" .. owner] = {}, nil
wars["gelt|reikland_enemy"], wars[owner .. "|reikland_enemy"] = false, false
alliances[owner .. "|reikland_enemy"] = nil
negotiate("gelt", "Sign a pact.", "non_aggression")
negotiate("gelt", "Break the pact.", "break_non_aggression")
insist()
negotiate("gelt", "Attack Enemy. [цель: Enemy]", "attack_third")
ruler.tick()
assert(buttons.th_mask_confirm.visible and buttons.th_mask_confirm.text == "Подтвердить")
alliances[owner .. "|reikland_enemy"] = "military"
mask_command("confirm")
assert(not applied, "Confirmation did not check the current alliance")
dispatch("ComponentLClickUp", "th_mask_confirm")
ruler.tick()
assert(not buttons.th_mask_confirm.visible and buttons.th_mask_insist.visible and buttons.th_mask_insist.text == "Настоять"
    and ui_deal:find("Условия на проверке", 1, true), "A click on the old card answered an unseen exposure check")
dismiss_narration()
click("insist")
assert(not applied and ui_ledger:find("Облик раскрыт", 1, true))
dismiss_narration()

turn, state.data, at_war = 100, {}, false
local live_treaties = { "trade agreement", "non-aggression pact", "military alliance", "defensive alliance" }
world.treaties_held = function(from, to)
    assert(to == "gelt")
    return from == "kislev" and live_treaties or {}
end
access["kislev|gelt"], access["gelt|kislev"] = true, false
ruler.show_conversation("gelt")
ruler.tick()
assert(ui_ledger:find("торговля", 1, true) and ui_ledger:find("пакт о ненападении", 1, true)
    and ui_ledger:find("военный союз", 1, true) and not ui_ledger:find("оборонительный союз", 1, true)
    and ui_ledger:find("доступ для двора", 1, true), "The summary did not display existing treaties and their direction")
assert(ui_deal:find("Условий сделки пока нет", 1, true))
live_treaties, access["kislev|gelt"], access["gelt|kislev"] = {}, false, true
ruler.show_conversation("gelt")
ruler.tick()
assert(not ui_ledger:find("торговля", 1, true) and ui_ledger:find("доступ для фракции облика", 1, true),
    "Reopening the court did not refresh current treaties")
access["kislev|gelt"] = true
ruler.show_conversation("gelt")
ruler.tick()
assert(ui_ledger:find("взаимный военный доступ", 1, true))
access["kislev|gelt"] = false

local summary_form = exposure.form_key({ subtype = form, faction = owner })
exposure.warn(state.data, "gelt", { summary_form }, "bystander", turn)
ruler.show_conversation("gelt")
ruler.tick()
assert(not ui_ledger:find("bystander", 1, true), "The summary exposed a warning the court had not announced")
pacts["gelt|" .. owner] = nil
ruler.talk_to("gelt", "Sign a pact.")
ruler.tick()
panel_visible = false
reply("non_aggression")
dismiss_narration()
ruler.tick()
assert(not panel_visible and not exposure.pair(state.data, summary_form, "gelt").warning.seen,
    "A check in a closed panel was marked as seen")
ledger_ok = false
ruler.show_conversation("gelt")
ruler.tick()
assert(not exposure.pair(state.data, summary_form, "gelt").warning.seen, "A failed ledger draw marked the warning seen")
ledger_ok = true
ruler.show_conversation("gelt")
ruler.tick()
assert(ui_ledger:find("bystander", 1, true) and not ui_ledger:find("доступ для фракции облика", 1, true),
    "The live check did not take priority over the summary")
click("withdraw")
assert(ui_ledger:find("bystander", 1, true) and ui_ledger:find("доступ для фракции облика", 1, true)
    and ui_lines:find("Предложение отозвано", 1, true), "The summary did not return with the seen warning")
state.data = copy_save(state.data)
ruler.show_conversation("gelt")
ruler.tick()
assert(ui_ledger:find("bystander", 1, true), "A disclosed warning was forgotten after loading")

exposure.warn(state.data, "gelt", { summary_form }, "military_ally", turn + 1)
turn = turn + 1
ruler.show_conversation("gelt")
ruler.tick()
assert(not ui_ledger:find("bystander", 1, true) and not ui_ledger:find("military_ally", 1, true),
    "Replacing a warning exposed the new source before the court named it")
local summary_pair = exposure.pair(state.data, summary_form, "gelt")
exposure.mark_warning_seen(summary_pair, turn, "military_ally")
summary_pair.exposed_until = 105
ruler.show_conversation("gelt")
ruler.tick()
assert(ui_ledger:find("105", 1, true), "The summary did not show when deals reopen")
change_form("emp_karl_franz", "reikland")
ruler.tick()
assert(not ui_ledger:find("105", 1, true), "The summary leaked an exposure from a different form")
change_form("ksl_katarin", "kislev")
turn = 106
ruler.tick()
assert(not ui_ledger:find("105", 1, true) and not ui_ledger:find("military_ally", 1, true),
    "The summary showed an expired block or warning")

state.data, pacts["gelt|" .. owner] = {}, nil
negotiate("gelt", "Sign a pact.", "non_aggression")
negotiate("gelt", "Break the pact.", "break_non_aggression")
insist()
exposure.warn(state.data, "gelt", { summary_form }, "bystander", turn)
ruler.talk_to("gelt", "Sign a pact.")
ruler.tick()
panel_visible = false
reply("non_aggression")
dismiss_narration()
ruler.tick()
assert(not exposure.known_warning(exposure.pair(state.data, summary_form, "gelt"), turn))
mask_command("insist")
ruler.tick()
ruler.tick()
assert(ui_lines:find("bystander", 1, true) and ui_ledger:find("bystander", 1, true)
    and ui_ledger:find("Облик раскрыт", 1, true), "A warning shown in the exposure result was not recorded")
dismiss_narration()

turn, state.data, at_war = 120, {}, false
wars["gelt|" .. owner], wars[owner .. "|gelt"] = nil, nil
ruler.talk_to("gelt", "Приветствую.")
assert(not has_outcome("vassalize") and not has_outcome("become_vassal"), "Vassalage was offered in an unrelated conversation")
reply("none")
at_war = true
ruler.talk_to("gelt", "Примите нас в вассалы.")
assert(not has_outcome("vassalize") and not has_outcome("become_vassal"), "Vassalage was offered while the two factions were at war")
reply("none")
at_war = false
war_state_readable = false
ruler.talk_to("gelt", "Примите нас в вассалы.")
assert(not has_outcome("become_vassal"), "Vassalage was offered with an unreadable war state")
reply("none")
war_state_readable = true
ruler.talk_to("gelt", "Просим принять нас в вассалы.")
assert(has_outcome("become_vassal") and has_outcome("vassalize"), "Vassalage was not offered in both directions")
applied = nil
reply("become_vassal")
ruler.tick()
assert(not applied and ui_deal:find("Сюзерен — gelt", 1, true)
    and ui_deal:find("Вассал — " .. owner, 1, true), "Offering submission skipped or misstated its confirmation")
click("confirm")
assert_pair("vassal", "gelt", owner)
assert(masters[owner] == "gelt" and not masters.gelt)

ruler.talk_to("gelt", "Станьте нашими вассалами.")
assert(not has_outcome("vassalize") and not has_outcome("become_vassal"), "An existing vassalage could be reversed")
reply("none")
masters[owner] = nil
negotiate("gelt", "Станьте нашими вассалами.", "vassalize")
ruler.tick()
assert(not applied and ui_deal:find("Сюзерен — " .. owner, 1, true) and ui_deal:find("Вассал — gelt", 1, true))
click("withdraw")
assert(not applied and not masters.gelt)
negotiate("gelt", "Станьте нашими вассалами и подпишем пакт.", { "vassalize", "non_aggression" })
mask_command("confirm")
assert(not applied and not masters.gelt, "Vassalage was accepted as part of a compound deal")

negotiate("gelt", "Станьте нашими вассалами.", "vassalize")
masters.gelt = "bystander"
mask_command("confirm")
assert(not applied and masters.gelt == "bystander", "A stale card transferred an existing vassal")
masters.gelt = nil
negotiate("gelt", "Станьте нашими вассалами.", "vassalize")
engine_accepts = false
mask_command("confirm")
engine_accepts = true
ruler.tick()
assert(not masters.gelt and ui_lines:find("Игра не подтвердила вассалитет", 1, true))
negotiate("gelt", "Станьте нашими вассалами.", "vassalize")
mask_command("confirm")
assert_pair("vassal", owner, "gelt")
assert(masters.gelt == owner and not masters[owner])

state.data, at_war = {}, false
masters.gelt, pacts["gelt|" .. owner] = nil, nil
masked_attitude = -25
negotiate("gelt", "Become our vassal.", "vassalize")
dismiss_narration()
ruler.tick()
assert(not applied and buttons.th_mask_insist.text == "Настоять" and ui_ledger:find("Двор не доверяет", 1, true),
    "A hostile court did not scrutinize the demand for submission")
mask_command("withdraw")
masked_attitude = -20

local function cheat_command(text)
    ruler.handle_command({ cmd = "cheat", text = text or "" })
end
assert(ruler.COMMANDS.cheat, "The slash command parser did not register /cheat")
cheat_command()
ruler.talk_to("gelt", "Sign a pact.")
assert(queued.request.messages[1].content:find("forced to consent", 1, true))
applied = nil
reply("non_aggression")
assert(not applied and not pacts["gelt|" .. owner], "A forced pact skipped confirmation")
mask_command("confirm")
assert_pair("non_aggression", "gelt", owner)
ruler.talk_to("gelt", "Cancel the pact.")
assert(not queued.request.messages[1].content:find("forced to consent", 1, true), "The cheat leaked to a second dialogue")
reply("break_non_aggression")
dismiss_narration()
mask_command("withdraw")

cheat_command()
ruler.select("bystander")
ruler.select("gelt")
ruler.talk_to("gelt", "Hello.")
assert(not queued.request.messages[1].content:find("forced to consent", 1, true), "The cheat survived a change of court")
reply("none")

cheat_command()
mask_command("off")
assert(not ruler.take_changeling_cheat("gelt"), "Changing speakers preserved the cheat")
cheat_command()
assert(ruler.take_changeling_cheat("gelt") and not ruler.take_changeling_cheat("gelt"), "Ordinary diplomacy did not consume the cheat once")
cheat_command()
cheat_command("off")
assert(not ruler.take_changeling_cheat("gelt"), "Cancelling did not disarm the cheat")
cheat_command()
turn = turn + 1
assert(not ruler.take_changeling_cheat("gelt"), "The cheat survived the end of the turn")

do
    local deal_key = "gelt|" .. owner
    local function open_envoy_check()
        state.data = {}
        pacts[deal_key], access[deal_key], trades[deal_key] = nil, nil, true
        negotiate("gelt", "Sign a pact.", "non_aggression")
        negotiate("gelt", "Break the pact.", "break_non_aggression")
        dismiss_narration()
        ruler.tick()
        assert(not applied and pacts[deal_key] and ui_ledger:find("посланник", 1, true)
            and ui_ledger:find(owner, 1, true), "A suspicious court with a trade route did not send an envoy")
    end

    turn = 160
    mask_command("on")
    ruler.select("gelt")
    ruler.show_conversation("gelt")
    open_envoy_check()
    ruler.select("bystander")
    ruler.show_conversation("bystander")
    ruler.tick()
    assert(not ui_ledger:find("посланник", 1, true), "A different court showed the envoy")
    turn = turn + 1
    state.data = copy_save(state.data)
    ruler.select("gelt")
    ruler.show_conversation("gelt")
    ruler.tick()
    assert(buttons.th_mask_withdraw.visible and ui_ledger:find("162", 1, true),
        "Loading on the next turn did not restore the inquiry and deadline")
    click("withdraw")
    turn = 162
    ruler.tick()
    assert(pacts[deal_key] and not ui_ledger:find("Облик раскрыт", 1, true), "A withdrawn case exposed the mask")

    open_envoy_check()
    input_text = "I have nothing more to propose."
    click("explain")
    reply("none")
    ruler.tick()
    assert(buttons.th_mask_withdraw.visible and ui_ledger:find("164", 1, true),
        "An explanation without a new deal cancelled or restarted the envoy")
    input_text = "Keep the pact and grant passage instead."
    click("explain")
    reply("military_access")
    ruler.tick()
    assert(pacts[deal_key] and not buttons.th_mask_withdraw.visible and ui_lines:find("отозвал посланника", 1, true),
        "A verified alternative did not end the inquiry")
    assert_pair("military_access", "gelt", owner)

    open_envoy_check()
    assert(not buttons.th_mask_insist.visible and not buttons.speak.visible
        and buttons.th_mask_status.text:find("164", 1, true), "The envoy state must show its deadline instead of the insist button")
    mask_command("insist")
    assert(not applied and pacts[deal_key], "Insisting applied the deal before the envoy returned")
    ruler.select("bystander")
    turn = 164
    dispatch("FactionTurnStart", player)
    ruler.select("gelt")
    ruler.show_conversation("gelt")
    ruler.tick()
    assert(pacts[deal_key] and ui_ledger:find("Облик раскрыт", 1, true) and ui_ledger:find("169", 1, true)
        and ui_lines:find("Посланник", 1, true), "The envoy did not expose the form at the deadline")
    turn = 165
    state.data = copy_save(state.data)
    dispatch("FactionTurnStart", player)
    ruler.tick()
    assert(ui_ledger:find("169", 1, true), "Loading an envoy result reset the exposure clock")

    turn = 169
    ruler.tick()
    assert(not ui_ledger:find("Облик раскрыт", 1, true), "The envoy caused a longer exposure block than normal")

    open_envoy_check()
    trades[deal_key], alliances[deal_key] = nil, nil
    turn = 171
    dispatch("FactionTurnStart", player)
    ruler.tick()
    assert(not ui_ledger:find("Облик раскрыт", 1, true) and not buttons.th_mask_withdraw.visible
        and ui_lines:find("Посланник не смог", 1, true), "A court obtained a witness after losing contact")
end

do
    local before, ordinary_before, accepts_before, setting_before = state.data, ordinary, native_accepts, settings.changeling_mask_enabled
    local field = buttons.speak
    field.text = "draft to preserve"
    ui.field, ui.compose = field, "cached draft"
    ruler.accept_shown = { key = "gelt" }
    mask_command("preview deal")
    ruler.tick()
    assert(ruler.mask_preview_active() and ui_lines:find("Предпросмотр", 1, true)
        and buttons.th_mask_preview_next.visible)
    local real_accept = ruler.accept_shown
    ruler.press_accept()
    click("confirm")
    assert(ui_lines:find("Конфедерация заключена", 1, true) and ruler.accept_shown == real_accept)
    ruler.talk_to("gelt", "Declare war.")
    ruler.handle_command({ cmd = "accept" })
    assert(ordinary == ordinary_before and native_accepts == accepts_before and not queued and not applied)
    assert(settings.changeling_mask_enabled == setting_before and state.data == before and not ruler.mask_speak_ready())
    click("preview_exit")
    assert(not ruler.mask_preview_active() and field.text == "draft to preserve" and ui.compose == "cached draft")

    mask_command("preview check")
    click("preview_next")
    assert(ruler.mask_preview_active() and ui_ledger:find("Посланник вернётся", 1, true))
    field.text = "test-only draft"
    turn = turn + 1
    ruler.tick()
    assert(not ruler.mask_preview_active() and field.text == "" and ui.compose == "",
        "A changed turn must discard preview input before returning to diplomacy")

    local original_out = out
    local traces = {}
    out = function(line) traces[#traces + 1] = line end
    mask_command("debug")
    dispatch("ComponentLClickUp", "th_gift_open")
    ruler.mask_trace_input("gift_search")
    mask_command("debug off")
    local trace = table.concat(traces, "\n")
    out = original_out
    assert(trace:find("UI|click th_gift_open", 1, true) and trace:find("UI|input gift_search", 1, true))
    assert(not trace:find("draft to preserve", 1, true))
end

print("Mask diplomacy tests passed")
