local military = {}

local verbs = {
    "атакуйте", "осадите", "отбейте", "захватите", "attack", "besiege", "retake", "capture",
}
local help_verbs = {
    "атаковать", "осадить", "отбить", "захватить", "attack", "besiege", "retake", "capture",
}
local grammar = {
    { "^(.+)%s+within%s+(%d+)%s+turns?$", true },
    { "^(.+)%s+в течение%s+(%d+)%s+ходов$", true },
    { "^(.+)%s+за%s+(%d+)%s+ходов$", true },
    { "^(.+)%s+за%s+(%d+)%s+хода$", true },
    { "^(.+)%s+за%s+(%d+)%s+ход$", true },
    { "^(.+)%s+by turn%s+(%d+)$", false },
    { "^(.+)%s+к%s+(%d+)%-му%s+ходу$", false },
    { "^(.+)%s+к%s+(%d+)%s+ходу$", false },
    { "^(.+)%s+до%s+(%d+)%-го%s+хода$", false },
    { "^(.+)%s+до%s+(%d+)%s+хода$", false },
}

local function trim(text)
    return text:match("^%s*(.-)%s*$")
end

local function unquote(text)
    return trim(text):gsub('^"(.-)"$', "%1"):gsub("^«(.-)»$", "%1")
end

local function arguments(line)
    line = line:gsub("^please%s*,?%s+", ""):gsub("^пожалуйста%s*,?%s+", "")
    local verb, rest = line:match("^(%S+)%s*(.*)$")
    if not verb then return end
    for _, direct in ipairs(verbs) do
        if verb == direct then return rest end
    end
    if verb == "помогите" or verb == "помоги" or verb == "help" then
        local words = " " .. rest .. " "
        for _, attack in ipairs(help_verbs) do
            local beneficiary, region = words:match("^(.-) " .. attack .. " (.*)$")
            if beneficiary then
                return trim(region), trim(beneficiary)
            end
        end
    end
end

local function parse(text, fold, turn)
    local line = trim(fold(text)):gsub("[!.]+$", "")
    if line:match("%?") then return end
    local words = " " .. line:gsub("[,;]", " ") .. " "
    for _, condition in ipairs({ " если ", " когда ", " при условии ", " if ", " unless ", " when " }) do
        if words:match(condition) then return end
    end
    local region, beneficiary = arguments(line)
    if not region then
        local after_greeting = line:match("^[^,%.;]+,%s*(.+)$")
        if after_greeting then region, beneficiary = arguments(after_greeting) end
    end
    if not region then return end

    local deadline = turn + 5
    for _, form in ipairs(grammar) do
        local name, value = region:match(form[1])
        if name then
            local number = tonumber(value)
            deadline = form[2] and (number > 0 and turn + number or turn - 1) or number
            region = name:gsub(",%s*$", "")
            break
        end
    end
    return unquote(region), beneficiary and unquote(beneficiary), deadline
end

function military.install(deps, api)
    local cm, state, core = deps.cm, deps.state, deps.core
    local world, actions, fold = deps.world, deps.actions, deps.fold
    local tr, report = api.tr, api.report or api.remember
    local function objectives(create)
        if type(state.data) ~= "table" then return end
        if type(state.data.military_objectives) ~= "table" then
            if not create then return end
            state.data.military_objectives = {}
        end
        return state.data.military_objectives
    end

    local function vassal_of(key, player)
        local subject, overlord = api.live(key), api.live(player)
        if subject and overlord and not subject:is_human() and subject:is_vassal_of(overlord) then
            return subject
        end
    end

    local function finish(task, message)
        objectives()[task.vassal] = nil
        report(task.vassal, message)
    end

    local function reconcile(task, turn)
        local place = api.place_name(task.region)
        local owner = api.owner_of(task.region)
        if turn > task.deadline then
            local message
            if task.captured and owner == task.vassal then
                message = tr("Partial result. %s still holds %s when the deadline for returning it to %s expires.",
                    "Частичный результат. %s удерживает %s, срок передачи фракции %s истёк.")
                    :format(world.name_of(task.vassal), place, world.name_of(task.beneficiary))
            else
                message = tr("Military objective expired. The deadline passed without taking %s.",
                    "Срок военного поручения истёк. Поселение %s не взято."):format(place)
                if not task.last_attempt then
                    message = message .. tr(" No attack order was issued.", " Приказ об атаке не был отдан.")
                end
            end
            finish(task, message)
            return
        end
        local intended_owner = task.beneficiary or task.vassal
        if owner == intended_owner then
            local message = tr("Military objective achieved. %s now controls %s.",
                "Военное поручение выполнено. %s теперь контролирует %s.")
                :format(world.name_of(owner), place)
            if task.beneficiary and not task.captured then
                message = message .. tr(" Vassal contribution unverified.", " Вклад вассала не подтверждён.")
            end
            finish(task, message)
            return
        end
        local subject = vassal_of(task.vassal, task.player)
        if not subject then
            finish(task, tr("Military objective cancelled. The faction is no longer your AI vassal.",
                "Военное поручение отменено. Фракция больше не является твоим вассалом под управлением ИИ."))
            return
        end
        if task.beneficiary and not api.live(task.beneficiary) then
            finish(task, tr("Military objective cancelled. The beneficiary faction has fallen.",
                "Военное поручение отменено. Фракция, которой требовалась помощь, больше не действует."))
            return
        end
        if task.beneficiary and owner == task.vassal then
            if not task.captured then
                task.captured = true
                report(task.vassal, tr("Partial result. %s holds %s. %s has yet to obtain it.",
                    "Частичный результат. %s удерживает %s. Фракция %s пока не получила поселение.")
                    :format(world.name_of(task.vassal), place, world.name_of(task.beneficiary)))
            end
            return
        end
        local defender = owner and api.live(owner)
        if owner ~= task.defender then
            finish(task, tr("Military objective ended. The original enemy no longer holds %s.",
                "Военное поручение прекращено. Прежний противник больше не контролирует %s."):format(place))
        elseif not defender or not subject:at_war_with(defender) then
            finish(task, tr("Military objective ended. The vassal and the settlement's owner are no longer at war.",
                "Военное поручение прекращено. Вассал и владелец поселения больше не воюют."))
        elseif task.beneficiary and subject:at_war_with(api.live(task.beneficiary)) then
            finish(task, tr("Military objective ended. The vassal is now at war with the beneficiary.",
                "Военное поручение прекращено. Вассал теперь воюет с фракцией, которой требовалась помощь."))
        else
            return subject
        end
    end

    local function start_turn(player, turn)
        for _, task in pairs(objectives() or {}) do
            if task.player == player then reconcile(task, turn) end
        end
    end

    local function handle(key, text, player, turn)
        local target, intended_beneficiary, deadline = parse(text, fold, turn)
        if not target then return false end
        if deadline < turn or deadline == math.huge or deadline > 2147483647 then
            return true, tr("Choose a valid deadline in turns.", "Укажи допустимый срок в ходах.")
        end
        if actions.blocked then return true, tr("Diplomatic actions are disabled.", "Дипломатические действия выключены.") end
        local subject = vassal_of(key, player)
        if not subject or player ~= cm:get_local_faction_name(true) then
            return true, tr("Only your active AI vassal can receive military orders.",
                "Военное поручение можно отдать своему действующему вассалу под управлением ИИ.")
        end
        local tasks = objectives(true)
        if not tasks or not core or type(cm.attack_region) ~= "function"
            or type(cm.character_can_reach_settlement) ~= "function" then
            return true, tr("Campaign settlement attack orders are unavailable.", "Приказ об атаке поселения недоступен.")
        end
        local region = target ~= "" and api.resolve_region(target)
        if not region then
            return true, tr("Specify one unambiguous settlement for the military objective.",
                "Однозначно укажи поселение для военного поручения.")
        end
        local beneficiary
        if intended_beneficiary then
            beneficiary = intended_beneficiary ~= "" and api.resolve_faction(intended_beneficiary, player, key)
            local faction = beneficiary and api.live(beneficiary)
            if not faction or key == beneficiary or subject:at_war_with(faction) then
                return true, tr("Specify one active beneficiary faction at peace with the vassal.",
                    "Однозначно укажи действующую фракцию, которая находится в мире с вассалом.")
            end
        end
        local owner = api.owner_of(region)
        if owner == (beneficiary or key) then
            return true, tr("The intended faction already controls this settlement.",
                "Указанная фракция уже контролирует это поселение.")
        end
        local defender = owner and api.live(owner)
        if not defender or not subject:at_war_with(defender) then
            return true, tr("The vassal must already be at war with the settlement's current owner.",
                "Вассал уже должен воевать с нынешним владельцем поселения.")
        end
        if tasks[key] then reconcile(tasks[key], turn) end
        if tasks[key] then
            return true, tr("This vassal already has a military objective at %s through turn %d.",
                "У вассала уже есть военное поручение у поселения %s до конца %d-го хода.")
                :format(api.place_name(tasks[key].region), tasks[key].deadline)
        end
        tasks[key] = { player = player, vassal = key, region = region, beneficiary = beneficiary,
            defender = owner, deadline = deadline }
        if beneficiary then
            return true, tr("Military objective recorded. Help %s retake %s through turn %d when a vassal army can reach it.",
                "Военное поручение записано. Помочь фракции %s отбить %s до конца %d-го хода, когда армия вассала сможет добраться.")
                :format(world.name_of(beneficiary), api.place_name(region), deadline)
        end
        return true, tr("Military objective recorded. Attack %s through turn %d when a vassal army can reach it.",
            "Военное поручение записано. Атаковать %s до конца %d-го хода, когда армия вассала сможет добраться.")
            :format(api.place_name(region), deadline)
    end

    local function on_vassal_turn(context)
        local tasks = objectives()
        local task = tasks and tasks[context:faction():name()]
        if not task or task.player ~= cm:get_local_faction_name(true) then return end
        local turn = cm:turn_number()
        local subject = reconcile(task, turn)
        if not subject or actions.blocked or task.last_attempt == turn then return end
        local region = cm:get_region(task.region)
        if not region or region:is_null_interface() or region:is_abandoned() then return end
        local settlement, forces = region:settlement(), subject:military_force_list()
        for i = 0, forces:num_items() - 1 do
            local force = forces:item_at(i)
            if force:is_army() and force:has_general() then
                local general = force:general_character()
                if not general:is_null_interface() and not general:is_wounded() and not general:is_besieging()
                    and cm:character_can_reach_settlement(general, settlement) then
                    -- CA's invasion manager uses attack_region with the character lookup and region key.
                    task.last_attempt = turn
                    local ok, result = pcall(cm.attack_region, cm, "character_cqi:" .. general:command_queue_index(), task.region)
                    if (not ok or result == false) and tasks[task.vassal] == task then
                        finish(task, tr("The game rejected the attack order for %s.",
                            "Игра отклонила приказ об атаке поселения %s."):format(api.place_name(task.region)))
                    end
                    return
                end
            end
        end
    end

    if core then
        core:add_listener("TalkHammerMilitaryObjectiveVassalTurn", "FactionBeginTurnPhaseNormal", true, on_vassal_turn, true)
        core:add_listener("TalkHammerMilitaryObjectiveRegionChanged", "RegionFactionChangeEvent", true, function(context)
            local key, player = context:region():name(), cm:get_local_faction_name(true)
            for _, task in pairs(objectives() or {}) do
                if task.region == key and task.player == player then reconcile(task, cm:turn_number()) end
            end
        end, true)
    end

    local function prompt(key)
        local tasks = objectives()
        local task = tasks and tasks[key]
        if not task or task.player ~= cm:get_local_faction_name(true) then return "" end
        return ("\n\nCAMPAIGN MILITARY OBJECTIVE: %s through turn %d%s%s."
            .. " Only game messages verify orders, battles, and ownership changes."):format(
            api.place_name(task.region), task.deadline,
            task.beneficiary and " for " .. world.name_of(task.beneficiary) or "",
            task.captured and ". Your faction took control earlier" or "")
    end

    return { handle = handle, start_turn = start_turn, prompt = prompt }
end

return military
