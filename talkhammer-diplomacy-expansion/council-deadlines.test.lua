local directory = (... or ".") .. "/"
local module_path = directory .. "council-deadlines.lua"
local install = assert(loadfile(module_path), "The council and deadline module is missing")().install

local turn, state = 80, { data = {} }
local requests, reports, timers = {}, {}, {}
local owner, unavailable = "donor", {}
local names = {
    player = "Обманщики", donor = "Культ удовольствий", target = "Кара Кадрин",
    har_ganeth = "Хар Ганет", third = "Хаг Греф", ready = "Армия Наггаронда",
    demands = "Клар Каронд", silent = "Нагарит", busy = "Наггаронд", warring = "Грондская стража",
    human = "Игрок 2", dead = "Клар Конд", freed = "Изгнанники",
}
local vassals = { ready = true, demands = true, silent = true, busy = true, warring = true, human = true, dead = true }
local factions, sequence = {}, {}
for key in pairs(names) do
    factions[key] = {
        name = function() return key end,
        is_human = function() return key == "player" or key == "human" end,
        is_vassal_of = function(_, overlord)
            return overlord:name() == "player" and vassals[key] == true
        end,
        at_war_with = function(_, other)
            return key == "warring" and other:name() == "target"
        end,
        is_null_interface = function() return false end,
        is_dead = function() return key == "dead" end,
    }
    sequence[#sequence + 1] = factions[key]
end
local cm = {
    get_local_faction_name = function() return "player" end,
    turn_number = function() return turn end,
    model = function()
        return { world = function()
            return { faction_list = function()
                return {
                    num_items = function() return #sequence end,
                    item_at = function(_, i) return sequence[i + 1] end,
                }
            end }
        end }
    end,
    callback = function(_, cb) timers[#timers + 1] = cb end,
}
local function fold(text)
    local upper = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
    local lower = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
    for i = 1, #upper, 2 do text = text:gsub(upper:sub(i, i + 1), lower:sub(i, i + 1)) end
    return text:lower()
end
local deps = { cm = cm, state = state, fold = fold, world = { name_of = function(key) return names[key] end } }
local api = {
    tr = function(_, ru) return ru end,
    live = function(key) return key ~= "dead" and not unavailable[key] and factions[key] or nil end,
    owner_of = function(region) if region == "grond" then return owner end end,
    place_name = function() return "Гронд" end,
    resolve_faction = function(raw)
        if fold(raw) == "хелеброн" then return "har_ganeth" end
        for key, name in pairs(names) do
            if raw == key or fold(raw) == fold(name) then return key end
        end
    end,
    resolve_region = function(raw, donor)
        if (fold(raw) == "гронд" or raw == "grond") and owner == donor then return "grond" end
    end,
    ask = function(key, prompt, callback)
        assert(not requests[key], "The council sent redundant requests")
        requests[key] = { prompt = prompt, reply = callback }
        if key == "busy" then return false end
        return true
    end,
    report = function(key, text)
        reports[#reports + 1] = { key = key, text = text }
    end,
}
local feature = install(deps, api)
local function command(line)
    local handled, note = feature.handle("donor", line, "player", turn)
    assert(handled, "The command fell through to ordinary diplomacy: " .. line)
    return note or ""
end
local function contains(text, expected)
    assert(text:find(expected, 1, true), "Missing '" .. expected .. "' in '" .. text .. "'")
end

assert(not feature.handle("donor", "Почему мы ссоримся?", "player", turn))
assert(not feature.handle("donor", "Передай Гронд Хелеброн", "player", turn))
contains(command("совет вассалов: никто"), "фракц")
command("Созови совет вассалов по войне против Кара Кадрин")
assert(requests.ready and requests.demands and requests.silent and requests.busy, "Current AI vassals were skipped")
assert(not (requests.human or requests.dead or requests.warring or requests.freed or requests.target),
    "The council sent an irrelevant request")
contains(requests.ready.prompt, "Кара Кадрин")
contains(requests.ready.prompt, "action=none")
contains(command("совет вассалов: Кара Кадрин"), "уже")
requests.ready.reply("Мы готовы сражаться.", { verdict = "accept" })
requests.demands.reply("Нам нужно золото.", { verdict = "counter" })
assert(#reports == 0, "The council reported results while still waiting")
timers[1]()
assert(#reports == 1 and reports[1].key == "donor")
local report = reports[1].text
contains(report, "Кара Кадрин")
contains(report, "Армия Наггаронда")
contains(report, "Готовы")
contains(report, "Мы готовы сражаться.")
contains(report, "Клар Каронд")
contains(report, "Выдвинули условия")
contains(report, "Нам нужно золото.")
contains(report, "Нагарит")
contains(report, "Не ответил")
contains(report, "Грондская стража")
contains(report, "Уже воюет")
requests.silent.reply("Слишком поздно.")
assert(#reports == 1, "A late reply changed the completed council report")

requests, reports, timers = {}, {}, {}
command("[совет вассалов: target]")
local first_campaign = state.data
state.data = {}
requests.ready.reply("Старая кампания.", { verdict = "accept" })
timers[1]()
assert(#reports == 0, "A previous campaign's result reached the new save")
state.data = first_campaign

local function copy_save(value)
    if type(value) ~= "table" then
        assert(type(value) ~= "function" and type(value) ~= "userdata")
        return value
    end
    local copy = {}
    for key, element in pairs(value) do copy[key] = copy_save(element) end
    return copy
end

contains(command("Верни Гронд Хелеброн до начала моего следующего хода, иначе я разорву союз"), "81")
contains(command("ультиматум: Гронд -> Хелеброн до хода 81"), "уже")
contains(command("Верни Гронд Хелеброн до конца хода"), "до хода")
assert(owner == "donor", "Recording an ultimatum transferred the settlement")
local saved_campaign = copy_save(state.data)
state.data = {}
turn = 81
feature.start_turn("player", turn)
assert(#reports == 0, "The ultimatum leaked into a new campaign")
state.data = saved_campaign
feature = install(deps, api)
feature.start_turn("human", turn)
assert(#reports == 0, "The ultimatum was checked on another player's turn")
feature.start_turn("player", turn)
assert(#reports == 1 and reports[1].key == "donor")
contains(reports[1].text, "не выполнен")
contains(reports[1].text, "я разорву союз")
feature.start_turn("player", turn)
assert(#reports == 1, "A checked ultimatum was reported twice")

contains(command("[ультиматум: Гронд -> Хар Ганет до хода 83]"), "83")
owner, turn = "har_ganeth", 82
feature.start_turn("player", turn)
assert(#reports == 1, "The explicit deadline was checked too early")
turn = 83
feature.start_turn("player", turn)
assert(#reports == 2)
contains(reports[2].text, "Гронд")
contains(reports[2].text, "Хар Ганет")
contains(reports[2].text, "Ультиматум выполнен")

owner = "player"
contains(command("Я обещаю передать Гронд Культ удовольствий до начала моего следующего хода"), "84")
owner, turn = "third", 84
feature.start_turn("player", turn)
assert(#reports == 3)
contains(reports[3].text, "Хаг Греф")
contains(reports[3].text, "не выполнен")
print("Council and settlement deadline tests passed")
