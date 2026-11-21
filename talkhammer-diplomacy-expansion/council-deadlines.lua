local features = {}

local council_commands = { ["совет вассалов"] = true, ["vassal council"] = true }
local demands = { ["ультиматум"] = true, ultimatum = true }
local promises = { ["обещание"] = true, promise = true }
local demand_verbs = {
    ["верни"] = true, ["верните"] = true, ["передай"] = true, ["передайте"] = true,
    ["отдай"] = true, ["отдайте"] = true, ["подари"] = true, ["подарите"] = true,
    ["уступи"] = true, ["уступите"] = true,
    ["return"] = true, give = true, transfer = true, gift = true,
}
local next_turn = {
    "до начала моего следующего хода", "до начала следующего хода", "до моего следующего хода",
    "by the start of my next turn", "before the start of my next turn", "by my next turn", "before my next turn",
}
local city_prefixes = {
    ["своё"] = true, ["свое"] = true, ["свой"] = true, ["поселение"] = true,
    ["город"] = true, ["крепость"] = true, your = true, my = true, the = true, settlement = true, city = true,
}
local faction_prefixes = {
    ["фракции"] = true, ["ведьме"] = true, ["леди"] = true, ["лорду"] = true,
    ["королю"] = true, ["королеве"] = true, to = true, the = true, faction = true,
}
local council_verdicts = {
    accept = { "Willing", "Готовы" },
    counter = { "Set terms", "Выдвинули условия" },
    decline = { "Declined", "Отказались" },
}

local function trim(text)
    return text:match("^%s*(.-)%s*$")
end

local function clean_entity(text)
    text = trim(text)
    return text:match('^"(.-)"$') or text:match("^«(.-)»$") or text
end

local function resolve_entity(text, prefixes, resolver)
    local key = resolver(clean_entity(text))
    while not key do
        local first, rest = text:match("^(%S+)%s+(.+)$")
        if not prefixes[first] then break end
        text = rest
        key = resolver(clean_entity(text))
    end
    return key
end

local function council_target(text, command, value)
    if council_commands[command] then return value end
    if council_commands[text] or text == "созови совет вассалов" or text == "call a vassal council" then return "" end
    return text:match("^созови совет вассалов по войне против%s+(.+)$")
        or text:match("^созови совет вассалов против%s+(.+)$")
        or text:match("^совет вассалов против%s+(.+)$")
        or text:match("^call a vassal council against%s+(.+)$")
        or text:match("^vassal council against%s+(.+)$")
end

local function deadline_request(text, command, value, turn)
    local promise, body = promises[command] == true, value
    if not (promise or demands[command]) then
        local verb
        verb, body = text:match("^(%S+)%s+(.+)$")
        if not demand_verbs[verb] then
            body = text:match("^я обещаю передать%s+(.+)$")
                or text:match("^i promise to give%s+(.+)$")
                or text:match("^i promise to transfer%s+(.+)$")
            promise = body ~= nil
        end
        if not body or not (body:match("%sдо%s") or body:match("%sк%s")
            or body:match("%sby%s") or body:match("%sbefore%s")) then
            return
        end
    end

    local timed, consequence = body:match("^(.-),?%s+иначе%s+(.+)$")
    if not timed then timed, consequence = body:match("^(.-),?%s+otherwise%s+(.+)$") end
    timed = trim(timed or body):gsub("[%s%.,!]+$", "")
    local subject, due = timed:match("^(.-)%s+до хода%s+(%d+)$")
    if not subject then subject, due = timed:match("^(.-)%s+by turn%s+(%d+)$") end
    if subject then return true, promise, subject, tonumber(due), consequence end
    for _, deadline in ipairs(next_turn) do
        subject = timed:match("^(.-)%s+" .. deadline .. "$")
        if subject then return true, promise, subject, turn + 1, consequence end
    end
    return true
end

local function settlement_pair(subject, donor, key, player, api)
    local function resolve_region(text)
        return api.resolve_region(text, donor)
    end
    local function resolve_faction(text)
        return api.resolve_faction(text, player, key)
    end
    local function resolve(left, right)
        local region = resolve_entity(left, city_prefixes, resolve_region)
        if region then return region, resolve_entity(right, faction_prefixes, resolve_faction) end
    end

    local left, right = subject:match("^(.-)%s*%-%>%s*(.-)$")
    if left then return resolve(trim(left), trim(right)) end
    local region, receiver
    local word, rest = nil, subject
    left = ""
    while rest do
        word, rest = rest:match("^(%S+)%s+(.+)$")
        if word then
            left = left == "" and word or left .. " " .. word
            local candidate, recipient = resolve(left, rest)
            if candidate and recipient then
                if region and (region ~= candidate or receiver ~= recipient) then return end
                region, receiver = candidate, recipient
            end
        end
    end
    return region, receiver
end

function features.install(deps, api)
    local cm, state, world, fold = deps.cm, deps.state, deps.world, deps.fold
    local tr, live = api.tr, api.live
    local active_council

    local function council_summary(council)
        local name = world.name_of(council.target)
        local lines = { tr("Vassal council on the war against %s.", "Совет вассалов о войне против %s."):format(name) }
        for _, member in ipairs(council.members) do
            local line = member.line or tr("No reply in time.", "Не ответил в срок.")
            lines[#lines + 1] = world.name_of(member.key) .. " — " .. line
        end
        return table.concat(lines, "\n")
    end

    local function finish_council(council)
        if active_council ~= council then return end
        active_council = nil
        if council.campaign == state.data and council.player == cm:get_local_faction_name(true) then
            api.report(council.key, council_summary(council))
        end
    end

    local function summon(key, target_name, player, turn)
        local target = api.resolve_faction(clean_entity(target_name:gsub("[%s%.!?]+$", "")), player, key)
        local enemy, overlord = target and live(target), live(player)
        if not (enemy and overlord) or target == player then
            return tr("Name one active target faction for the council.", "Укажи одну действующую фракцию для совета.")
        end
        if not state.data then
            return tr("Campaign state is unavailable.", "Данные кампании пока недоступны.")
        end
        if active_council and active_council.campaign == state.data then
            if active_council.turn == turn then
                return tr("The council is already waiting for replies.", "Совет уже ждёт ответов.")
            end
            finish_council(active_council)
        end
        local council = { key = key, target = target, player = player, turn = turn,
            campaign = state.data, members = {}, waiting = 0 }
        local list = cm:model():world():faction_list()
        for index = 0, list:num_items() - 1 do
            local faction = list:item_at(index)
            if not faction:is_null_interface() and not faction:is_dead() and not faction:is_human()
                and faction:name() ~= target and faction:is_vassal_of(overlord) then
                local member = { key = faction:name() }
                if faction:at_war_with(enemy) then
                    member.line = tr("Already at war.", "Уже воюет.")
                else
                    council.waiting = council.waiting + 1
                end
                council.members[#council.members + 1] = member
            end
        end
        if #council.members == 0 then
            return tr("You have no AI vassals to consult about this faction.",
                "У тебя нет вассалов ИИ, с которыми можно обсудить войну против этой фракции.")
        end
        table.sort(council.members, function(a, b) return a.key < b.key end)
        active_council = council
        local prompt = "VASSAL COUNCIL: Your current overlord " .. world.name_of(player)
            .. " asks whether you would join a war against " .. world.name_of(target) .. " (" .. target .. ")."
            .. " In one short in-character reply, state your willingness or refusal and any terms."
            .. " Use verdict=accept for unconditional willingness, verdict=counter for willingness on terms,"
            .. " or verdict=decline for refusal."
            .. " This consultation does not change a treaty or start a war. Use action=none."
        local dispatching = true
        for _, member in ipairs(council.members) do
            if not member.line then
                local participant = member
                local function reply(line, decision)
                    if active_council ~= council or council.campaign ~= state.data
                        or council.player ~= cm:get_local_faction_name(true) or council.turn ~= cm:turn_number()
                        or participant.line then return end
                    local faction = live(participant.key)
                    if not faction or not faction:is_vassal_of(overlord) then
                        participant.line = tr("No longer your vassal.", "Больше не твой вассал.")
                    elseif type(line) == "string" and line ~= "" then
                        local verdict = decision and council_verdicts[decision.verdict]
                        participant.line = verdict and tr(verdict[1], verdict[2]) .. " · " .. line or line
                    else
                        participant.line = tr("No reply in time.", "Не ответил в срок.")
                    end
                    council.waiting = council.waiting - 1
                    if council.waiting == 0 and not dispatching then finish_council(council) end
                end
                local ok, scheduled = pcall(api.ask, participant.key, prompt, reply)
                if not (ok and scheduled) and not participant.line then
                    participant.line = tr("Could not request a reply.", "Не удалось запросить ответ.")
                    council.waiting = council.waiting - 1
                end
            end
        end
        dispatching = false
        if council.waiting == 0 then
            active_council = nil
            return council_summary(council)
        end
        cm:callback(function() finish_council(council) end, 90)
        return tr("The council is awaiting replies on the war against %s.",
            "Совет ждёт ответов о войне против %s."):format(world.name_of(target))
    end

    local function schedule(key, player, turn, promise, subject, due, consequence)
        if not subject or not due or due == math.huge or due <= turn then
            return tr("Use [ultimatum: settlement -> faction by turn N] with a future turn.",
                "Укажи город, фракцию и будущий ход: [ультиматум: город -> фракция до хода N].")
        end
        if not state.data then
            return tr("Campaign state is unavailable.", "Данные кампании пока недоступны.")
        end
        local donor = promise and player or key
        local region, receiver = settlement_pair(subject, donor, key, player, api)
        if not region or not receiver or receiver == donor or not live(receiver) or api.owner_of(region) ~= donor
            or (promise and receiver ~= key) then
            return promise and tr("Name one settlement of yours and the faction you are speaking with.",
                "Укажи одно своё поселение и фракцию собеседника.")
                or tr("Name one settlement held by the counterpart and one active recipient faction.",
                    "Укажи одно поселение собеседника и одну действующую фракцию-получателя.")
        end
        local deadlines = state.data.diplomacy_expansion_deadlines
        if not deadlines then
            deadlines = {}
            state.data.diplomacy_expansion_deadlines = deadlines
        end
        for _, previous in ipairs(deadlines) do
            if previous.player == player and previous.region == region and previous.from == donor
                and previous.to == receiver and previous.due == due then
                return tr("This deadline is already recorded.", "Этот срок уже записан.")
            end
        end
        deadlines[#deadlines + 1] = { key = key, player = player, region = region, from = donor,
            to = receiver, due = due, consequence = consequence, promise = promise }
        return tr("Deadline recorded for the start of turn %d. %s → %s.",
            "Срок записан до начала хода %d. %s → %s."):format(due, api.place_name(region), world.name_of(receiver))
    end

    local function start_turn(player, turn)
        if player ~= cm:get_local_faction_name(true) then return end
        if active_council and active_council.player == player and active_council.turn < turn then
            finish_council(active_council)
        end
        local deadlines = state.data and state.data.diplomacy_expansion_deadlines
        if not deadlines then return end
        for index = #deadlines, 1, -1 do
            local entry = deadlines[index]
            if entry.player == player and entry.due <= turn then
                table.remove(deadlines, index)
                local owner = api.owner_of(entry.region)
                local title
                if owner == entry.to then
                    title = entry.promise and tr("Promise fulfilled", "Обещание выполнено")
                        or tr("Ultimatum fulfilled", "Ультиматум выполнен")
                else
                    title = entry.promise and tr("Promise unfulfilled", "Обещание не выполнено")
                        or tr("Ultimatum unfulfilled", "Ультиматум не выполнен")
                end
                local line = tr("%s. Deadline turn %d. %s → %s.", "%s. Срок — ход %d. %s → %s."):format(
                    title, entry.due, api.place_name(entry.region), world.name_of(entry.to))
                if entry.due < turn then
                    line = line .. tr(" Checked on turn %d.", " Проверено на ходу %d."):format(turn)
                end
                if owner ~= entry.to then
                    line = line .. (owner and tr(" Current owner — %s.", " Текущий владелец — %s."):format(world.name_of(owner))
                        or tr(" The settlement has no confirmed owner.", "Владелец поселения не подтверждён."))
                    if entry.consequence then
                        line = line .. tr(" Your stated consequence — %s", " Напоминание об условии — %s"):format(entry.consequence)
                    end
                end
                api.report(entry.key, line)
            end
        end
    end

    local function handle(key, text, player, turn)
        text = trim(fold(text))
        text = text:match("^%[(.*)%]$") or text
        local command, value = text:match("^([^:]+):%s*(.*)$")
        if command then command = trim(command) end
        local target = council_target(text, command, value)
        if target then return true, summon(key, target, player, turn) end
        local handled, promise, subject, due, consequence = deadline_request(text, command, value, turn)
        if handled then return true, schedule(key, player, turn, promise, subject, due, consequence) end
        return false
    end

    return { handle = handle, start_turn = start_turn }
end

return features
