local gifts = {}
local gift_kind = "settlement_gift"
local influence_kind = "vassal_confederation"
local gift_words = { ["подарите"] = true, ["подарить"] = true, ["дарите"] = true,
    ["дарю"] = true, ["дарим"] = true, gift = true }
local titles = { ["царица"] = true, ["ведьма"] = true, ["король"] = true, ["королева"] = true,
    ["лорд"] = true, ["леди"] = true, ["император"] = true, ["герцог"] = true,
    crone = true, tsarina = true, king = true, queen = true, lord = true, lady = true, emperor = true, duke = true }

local function trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

local function fields(text, fold)
    local input = trim(text)
    if input:sub(1, 1) == "[" and input:sub(-1) == "]" then
        input = input:sub(2, -2)
    end
    local command, sequence = input:match("^([^:%[%]]+):%s*(.-)%s*$")
    if command and (fold(trim(command)) == "дар" or fold(trim(command)) == "gift") then
        local region, receiver = sequence:match("^(.-)%s*%-%>%s*([^%[%]]-)%s*$")
        if not region then return nil, nil, true end
        return trim(region), trim(receiver), true
    end
    if fold(text):match("^%s*%[дар%s*:") or fold(text):match("^%s*%[gift%s*:") then
        return nil, nil, true
    end

    local quoted = text:gsub("«", '"'):gsub("»", '"'):gsub("„", '"'):gsub("“", '"'):gsub("”", '"')
    local prefix, first, middle, second = quoted:match('^([^"]*)"([^"]+)"([^"]*)"([^"]+)"')
    if not prefix then return nil, nil, false end
    for word in fold(prefix):gmatch("%S+") do
        if gift_words[word:gsub("[,%.!?]+$", "")] then return trim(first), trim(second), true end
    end
    if (" " .. fold(middle) .. " "):match(" в дар ") then
        return trim(first), trim(second), true
    end
    return nil, nil, false
end

local function copy(table_to_copy)
    local result = {}
    for key, value in pairs(table_to_copy) do result[key] = value end
    return result
end

local function valid(interface)
    return interface and not interface:is_null_interface()
end

function gifts.install(deps)
    local cm, ruler, state, world = deps.cm, deps.ruler, deps.state, deps.world
    local actions, fold = deps.actions, deps.fold
    local pending, requested, moving = {}, {}, {}
    local next_id = 0
    local stock_table_action, stock_ledger, stock_settle = ruler.table_action, ruler.ledger_text, ruler.settle

    local function tr(en, ru)
        return deps.language() == "ru" and ru or en
    end

    local function living_faction(key)
        local faction = cm:get_faction(key)
        if valid(faction) and not faction:is_dead() then return faction end
    end

    local function owner_of(key)
        local region = cm:get_region(key)
        if not valid(region) then return nil end
        local owner = region:owning_faction()
        return valid(owner) and owner:name() or nil
    end

    local function place_name(key)
        local name = deps.localise("regions_onscreen_" .. key)
        if name and name ~= "" and name ~= "regions_onscreen_" .. key then return name end
        return key
    end

    local function title(gift)
        if gift and gift.kind == influence_kind then return tr("Mediated confederation", "Конфедерация по договорённости") end
        return tr("Settlement gift", "Дар поселения")
    end

    local function parties(gift, separator)
        local from, to = world.name_of(gift.from), world.name_of(gift.to)
        if gift.kind == influence_kind then
            return tr("Joins: ", "Вступает: ") .. from .. separator .. tr("Remains: ", "Остаётся: ") .. to
        end
        return tr("Donor: ", "Даритель: ") .. from .. separator .. tr("Recipient: ", "Получатель: ") .. to
    end

    local function details(gift)
        local sides = parties(gift, " · ")
        return gift.region and (place_name(gift.region) .. " · " .. sides) or sides
    end

    local function note(key, text)
        state.remember(key, cm:turn_number(), text, "note", { short = text })
    end

    local function show(key)
        if ruler.counterpart == key then ruler.show_conversation(key) end
    end

    local function current(gift, turn)
        return gift.campaign == state.data and gift.turn == (turn or cm:turn_number())
            and gift.player == cm:get_local_faction_name(true)
    end
    local influence = deps.influence.install(deps, { current = current, living_faction = living_faction, tr = tr })

    local function on_table(key, turn)
        local gift = pending[key]
        if gift and not current(gift, turn) then
            pending[key] = nil
            return nil
        end
        return gift
    end

    local function can_transfer(gift)
        if actions.blocked then
            return false, tr("Diplomatic actions are disabled.", "Дипломатические действия выключены.")
        end
        if gift.kind == influence_kind then return influence.valid(gift) end
        local counterpart = living_faction(gift.key)
        if not counterpart or counterpart:is_human() then
            return false, tr("The counterpart must be an active AI faction.", "Собеседником должна быть действующая фракция ИИ.")
        end
        if not living_faction(gift.from) or owner_of(gift.region) ~= gift.from then
            return false, tr("The settlement no longer belongs to the donor.", "Поселение уже не принадлежит дарителю.")
        end
        if not living_faction(gift.to) then
            return false, tr("The recipient is no longer an active faction.", "Фракция получателя больше не действует.")
        end
        return true
    end

    local function resolve_faction(raw, player, counterpart)
        if (raw == player or raw == counterpart or raw:match("^[%w%-]+_[%w_%-]+$")) and living_faction(raw) then
            return raw
        end
        local needle = fold(raw)
        local match, ambiguous
        local function consider(key)
            if key == raw and living_faction(key) then return key end
            if key ~= match and fold(world.name_of(key)) == needle and living_faction(key) then
                ambiguous = match ~= nil
                match = key
            end
        end
        consider(player)
        consider(counterpart)
        for _, key in ipairs(world.keys or {}) do
            if key ~= player and key ~= counterpart then
                local exact = consider(key)
                if exact then return exact end
            end
        end
        if not ambiguous then return match end
    end

    local function resolve_region(raw, player, counterpart)
        local needle = fold(raw)
        local found, donor
        for _, key in ipairs({ player, counterpart }) do
            local faction = living_faction(key)
            if faction then
                local regions = faction:region_list()
                for index = 0, regions:num_items() - 1 do
                    local name = regions:item_at(index):name()
                    if name == raw then return name, key end
                    if fold(place_name(name)) == needle then
                        if found then return nil end
                        found, donor = name, key
                    end
                end
            end
        end
        return found, donor
    end

    local function labels_for(faction_key, faction, player)
        local labels = { world.name_of(faction_key) }
        local name = world.leader_name(faction_key)
        if name and name ~= "" then
            labels[#labels + 1] = name
            local words = deps.words(name)
            if #words > 1 then
                -- A surname or a first name can identify a live ruler; the resolver still rejects collisions.
                if not titles[words[1]] then labels[#labels + 1] = words[1] end
                labels[#labels + 1] = words[#words]
            end
        end
        local leader = faction:faction_leader()
        if valid(leader) and leader:character_subtype_key() == "wh2_dlc10_def_crone_hellebron" then
            labels[#labels + 1] = "Хелеброн"
            labels[#labels + 1] = "Хеллеброн"
            labels[#labels + 1] = "Hellebron"
        end
        if faction_key == player then
            labels[#labels + 1] = "мне"
            labels[#labels + 1] = "me"
        end
        return labels
    end

    local function natural_order(key, text, player)
        if ruler.expansion_mask_active and ruler.expansion_mask_active() then return end
        local tokens, has_town = deps.natural.command(text, deps.words)
        if not tokens then return end
        local counterpart = living_faction(key)
        if not counterpart or key == player or counterpart:is_human() then return end
        local cities = {}
        local regions = counterpart:region_list()
        for index = 0, regions:num_items() - 1 do
            local region = regions:item_at(index):name()
            cities[#cities + 1] = { key = region, labels = { place_name(region) } }
        end
        local function recipients()
            local choices, seen = {}, {}
            local function add(faction_key)
                if faction_key == key or seen[faction_key] then return end
                seen[faction_key] = true
                local faction = living_faction(faction_key)
                if not faction then return end
                choices[#choices + 1] = { key = faction_key, labels = labels_for(faction_key, faction, player) }
            end
            add(player)
            for _, faction_key in ipairs(world.keys or {}) do add(faction_key) end
            return choices
        end
        local region, recipient, missing = deps.natural.resolve(tokens, cities, recipients, deps.words, deps.stem)
        if region then return region, recipient end
        if missing == "city" and not has_town then return end
        local why = missing == "city"
            and tr("Which of my settlements should I give away? Name one.", "Какое из моих поселений передать? Укажи одно название.")
            or tr("Who should receive the settlement? Name one faction or ruler.", "Кому передать поселение? Назови одну фракцию или её правителя.")
        return nil, nil, why
    end

    local function direct()
        return not (ruler.expansion_mask_active and ruler.expansion_mask_active())
    end

    local function named_resolvers()
        local function named(raw, label)
            if fold(raw) == fold(label) then return true end
            local input, name = deps.words(raw), deps.words(label)
            if #input ~= #name or #input == 0 then return false end
            for i, word in ipairs(input) do
                if word ~= name[i] and (not deps.stem or deps.stem(word) ~= deps.stem(name[i])) then return false end
            end
            return true
        end
        local function faction(raw, player, key)
            raw = trim(raw)
            if raw == "" then return end
            if raw:match("^[%w_%-]+$") and living_faction(raw) then return raw end
            local found, seen, ambiguous = nil, {}, false
            local function visit(candidate)
                if not candidate or seen[candidate] then return end
                seen[candidate] = true
                local entry = living_faction(candidate)
                if not entry then return end
                for _, label in ipairs(labels_for(candidate, entry, player)) do
                    if named(raw, label) then
                        ambiguous = found ~= nil
                        found = candidate
                        break
                    end
                end
            end
            visit(player)
            visit(key)
            for _, candidate in ipairs(world.keys or {}) do
                visit(candidate)
                if ambiguous then return end
            end
            if not ambiguous then return found end
        end
        local function region(raw, holder)
            raw = trim(raw)
            if raw == "" then return end
            if raw:match("^[%w_%-]+$") then
                local owner = owner_of(raw)
                if owner and (not holder or holder == owner) then return raw end
            end
            local found, ambiguous
            local function visit(candidate)
                local entry = living_faction(candidate)
                if not entry then return end
                local regions = entry:region_list()
                for i = 0, regions:num_items() - 1 do
                    local region_key = regions:item_at(i):name()
                    if named(raw, place_name(region_key)) and found ~= region_key then
                        ambiguous = found ~= nil
                        found = region_key
                    end
                    if ambiguous then return end
                end
            end
            if holder then visit(holder)
            else
                for _, candidate in ipairs(world.keys or {}) do
                    visit(candidate)
                    if ambiguous then return end
                end
            end
            if not ambiguous then return found end
        end
        return faction, region
    end

    local function occupied(key, turn)
        return on_table(key, turn) or stock_table_action(key, turn)
    end

    local queued_reports
    local function report(key, text)
        if queued_reports then
            queued_reports[#queued_reports + 1] = { key, text }
            return
        end
        local turn = cm:turn_number()
        for line in text:gmatch("[^\n]+") do state.remember(key, turn, line, "ruler") end
        if ruler.news_add then ruler.news_add(turn, text, "audience", {key}, true) end
        local ok, visible = pcall(deps.is_open)
        if ok and visible and direct() then show(key) end
    end
    local resolve_named_faction, resolve_named_region = named_resolvers()
    local api = { direct = direct, resolve_faction = resolve_named_faction, resolve_region = resolve_named_region,
        tr = tr, live = living_faction, remember = note, report = report, ask = deps.ask_envoy,
        place_name = place_name, owner_of = owner_of, occupied = occupied }
    local negotiation = deps.negotiation and deps.negotiation.install(deps, api)
    local council = deps.council and deps.council.install(deps, api)
    local military = deps.military and deps.military.install(deps, api)
    local services = { negotiation, council, military }

    local function handle(key, text, player, turn)
        if not direct() or type(text) ~= "string" then return false end
        local ok, handled, line = true
        queued_reports = {}
        for _, service in ipairs(services) do
            ok, handled, line = pcall(service.handle, key, text, player, turn)
            if not ok or handled then break end
        end
        local buffered = queued_reports
        queued_reports = nil
        if not ok then error(handled) end
        if not handled then return false end
        state.remember(key, turn, text, "you")
        if line then report(key, line) end
        for _, entry in ipairs(buffered) do report(entry[1], entry[2]) end
        return true
    end

    if deps.core and (council or military) then
        deps.core:add_listener("TalkHammerDiplomacyExpansionPlayerTurn", "FactionTurnStart", function(context)
            return context:faction():name() == cm:get_local_faction_name(true)
        end, function(context)
            local player, turn = context:faction():name(), cm:turn_number()
            if council then council.start_turn(player, turn) end
            if military then military.start_turn(player, turn) end
        end, true)
    end

    local function prepare(key, text, player, turn, selection)
        local subject, receiver, explicit
        if selection then
            subject, receiver, explicit = selection.region, selection.recipient, true
        else
            subject, receiver, explicit = fields(text or "", fold)
        end
        local kind = gift_kind
        local automatic
        if not explicit then
            local why
            subject, receiver, why = natural_order(key, text or "", player)
            if why then return nil, why end
            automatic = subject ~= nil
            explicit = automatic
        end
        if not explicit then
            subject, receiver, explicit = influence.parse(text or "")
            kind = influence_kind
        end
        if not explicit then return nil end
        if not subject or subject == "" or not receiver or receiver == "" then
            if kind == influence_kind then
                return nil, tr("Use [confederation: joining faction -> absorbing faction].",
                    "Укажи стороны: [конфедерация: присоединяемая фракция -> поглощающая фракция].")
            end
            return nil, tr("Use [gift: settlement -> faction].", "Укажи город и фракцию: [дар: поселение -> фракция].")
        end
        local counterpart = living_faction(key)
        if key == player or not counterpart or counterpart:is_human() then
            return nil, tr("Choose an active AI counterpart.", "Выбери действующую фракцию ИИ.")
        end
        if occupied(key, turn) or (negotiation and negotiation.busy(key)) then
            return nil, tr("Resolve the offer on the table first.", "Сначала подтверди или отклони сделку на столе.")
        end
        local recipient = automatic and receiver or resolve_faction(receiver, player, key)
        if not recipient then
            return nil, tr("Name one active recipient faction.", "Укажи точное название одной действующей фракции-получателя.")
        end
        local region, donor
        if kind == gift_kind then
            if automatic then region, donor = subject, key
            else region, donor = resolve_region(subject, player, key) end
            if not region then
                return nil, tr("Name one settlement held by you or the counterpart.", "Укажи точное название одного поселения игрока или собеседника.")
            end
            if donor == recipient or (donor == player and recipient ~= key) then
                return nil, tr("The counterpart must be the donor or the recipient.", "Собеседник должен быть дарителем или получателем, а стороны должны различаться.")
            end
        else
            donor = resolve_faction(subject, player, key)
            if not donor or donor == recipient or (key ~= donor and key ~= recipient) then
                return nil, tr("Address one of the two factions joining this confederation.",
                    "Назови две разные фракции и обратись к одной из сторон конфедерации.")
            end
        end
        next_id = next_id + 1
        local gift = { kind = kind, campaign = state.data, turn = turn, player = player, key = key,
            from = donor, to = recipient, region = region, id = next_id, automatic = automatic }
        local ok, why = can_transfer(gift)
        if not ok then return nil, why end
        requested[key] = gift
        return gift
    end

    local talk_to = ruler.talk_to
    function ruler.gift_choices(counterpart, settlement)
        local player = cm:get_local_faction_name(true)
        local choices, seen = {}, {}
        local function add(key, label)
            if seen[key] then return end
            seen[key] = true
            choices[#choices + 1] = { key = key, label = label, order = fold(label) }
        end
        if settlement then
            local donor = owner_of(settlement)
            if donor == player then
                if living_faction(counterpart) then add(counterpart, world.name_of(counterpart)) end
            elseif donor == counterpart then
                if living_faction(player) then add(player, world.name_of(player)) end
                for _, key in ipairs(world.keys or {}) do
                    if key ~= donor and not seen[key] and living_faction(key) then add(key, world.name_of(key)) end
                end
            end
        else
            for _, key in ipairs({ counterpart, player }) do
                local faction = living_faction(key)
                if faction then
                    local regions = faction:region_list()
                    for index = 0, regions:num_items() - 1 do
                        local city = regions:item_at(index):name()
                        local name = place_name(city)
                        if key == player then name = name .. " · " .. world.name_of(player) end
                        add(city, name)
                    end
                end
            end
        end
        table.sort(choices, function(a, b)
            if a.order == b.order then return a.key < b.key end
            return a.order < b.order
        end)
        return choices
    end

    function ruler.offer_settlement_gift(counterpart, region, recipient)
        if counterpart ~= ruler.counterpart or (ruler.expansion_mask_active and ruler.expansion_mask_active()) then return end
        local mine = owner_of(region) == cm:get_local_faction_name(true)
        local line = mine and tr("I offer «%s» as a gift to «%s».", "Предлагаю подарить поселение «%s» фракции «%s».")
            or tr("Would you give «%s» to «%s» as a gift?", "Передайте поселение «%s» в дар фракции «%s».")
        return talk_to(counterpart, line:format(place_name(region), world.name_of(recipient)),
            { region = region, recipient = recipient })
    end

    local function prompt(gift)
        if not gift then return "" end
        if gift.kind == influence_kind then return influence.prompt(gift) end
        local timing = gift.automatic and " The player has already authorized this exact transfer if you agree."
            .. " Acknowledge your decision; the transfer has not been executed yet."
            or " The gift awaits the player's confirmation; no settlement has changed hands."
        return "\n\nSETTLEMENT GIFT FOR THIS AUDIENCE: " .. details(gift)
            .. ". This is one unconditional gift. You are " .. world.name_of(gift.key)
            .. (gift.key == gift.from and ", its donor." or ", its recipient.")
            .. " You may agree or decline in character. Set gift_agreed=true only for clear agreement"
            .. " to this exact gift with no price or condition. Otherwise set gift_agreed=false."
            .. " Negotiating or asking for payment is not agreement."
            .. timing .. " Use action=none and make no other deal."
    end

    local function consent_field(gift)
        return gift.kind == influence_kind and "influence_agreed" or "gift_agreed"
    end

    local function schema(format, gift)
        if not gift then return format end
        format = copy(format)
        format.json_schema = copy(format.json_schema)
        local specification = copy(format.json_schema.schema)
        format.json_schema.schema = specification
        specification.properties = copy(specification.properties)
        specification.properties.action = { type = "string", enum = { "none" } }
        local field = consent_field(gift)
        specification.properties[field] = { type = "boolean",
            description = "True only if you agree to the exact proposal with no further condition." }
        specification.required = copy(specification.required)
        table.insert(specification.required, field)
        return format
    end

    local apply_deal
    local function finish(gift, decision)
        local key = gift.key
        if requested[key] ~= gift then return false end
        requested[key] = nil
        if not current(gift) then return false end

        if type(decision.line) == "string" and decision.line ~= "" then
            state.remember(key, gift.turn, decision.line, "ruler")
            deps.transcript("ruler", decision.line)
            if deps.speak and ruler.counterpart == key then pcall(deps.speak, key, decision.line) end
        end
        local agreed = decision[consent_field(gift)] == true
        if gift.kind == influence_kind and not agreed then influence.consent(gift, false) end
        if agreed and gift.automatic then
            if occupied(key, gift.turn) or (negotiation and negotiation.busy(key))
                or (ruler.counterpart == key and ruler.expansion_mask_active and ruler.expansion_mask_active()) then
                note(key, tr("Repeat the request in direct conversation with no other offer on the table.",
                    "Повтори просьбу в прямом разговоре, когда на столе не будет другой сделки."))
            else
                local ok, why = apply_deal(gift)
                if not ok then note(key, why) end
            end
        elseif agreed then
            local ok, why = can_transfer(gift)
            if ok then
                if gift.kind == gift_kind or influence.consent(gift, true) then
                    pending[key] = gift
                    note(key, title(gift) .. " · " .. details(gift))
                else
                    note(key, tr("Consent recorded. Ask the other side about the same confederation.",
                        "Согласие записано. Обсуди ту же конфедерацию со второй стороной.") .. " " .. world.name_of(influence.other_party(gift)))
                end
            else
                note(key, why)
            end
        end
        show(key)
        if ruler.counterpart == key then ruler.publish_status(nil, { activity = "idle" }) end
        return true
    end

    local function fingerprint(gift)
        return table.concat({ gift.kind, gift.id, gift.turn, gift.from, gift.region or "", gift.to }, "|")
    end

    ruler.table_action = function(key, turn)
        local gift = on_table(key, turn)
        if not gift then return (negotiation and negotiation.card(key)) or stock_table_action(key, turn) end
        local confederation = gift.kind == influence_kind
        return {
            kind = gift.kind, expansion = true,
            label = confederation and tr("ACCEPT CONFEDERATION", "ПРИНЯТЬ КОНФЕДЕРАЦИЮ")
                or tr("ACCEPT SETTLEMENT GIFT", "ПРИНЯТЬ ДАР ПОСЕЛЕНИЯ"),
            confirm = confederation and tr("CONFIRM CONFEDERATION", "ПОДТВЕРДИТЬ КОНФЕДЕРАЦИЮ")
                or tr("CONFIRM GIFT: ", "ПОДТВЕРДИТЬ ДАР: ") .. place_name(gift.region),
            what = details(gift),
            print = fingerprint(gift),
        }
    end

    ruler.ledger_text = function(key, label, split)
        local text, card = stock_ledger(key, label, split)
        if type(text) == "string" then text = text:gsub(" → ", " / ") end
        local gift = on_table(key)
        local exchange = negotiation and negotiation.card(key)
        if exchange then
            local description = tr("Settlement exchange", "Обмен поселениями") .. "\n" .. exchange.what:gsub(" → ", " / ")
                .. "\n" .. tr("Confirm or /reject.", "Подтверди или введи /reject.")
            if split then return text, description end
            return description .. "\n\n" .. (text or ""), description
        end
        if not gift then return text, card end
        local body = parties(gift, "\n")
        if gift.region then body = tr("Settlement: ", "Поселение: ") .. place_name(gift.region) .. "\n" .. body end
        local description = title(gift) .. "\n" .. body .. "\n" .. tr("Confirm or /reject.", "Подтверди или введи /reject.")
        if split then return text, description end
        return description .. "\n\n" .. (text or ""), description
    end

    local function completed(gift)
        if gift.kind == influence_kind then return influence.completed(gift) end
        return owner_of(gift.region) == gift.to
    end

    local function conflicts(first, second)
        if first.region and second.region then return first.region == second.region end
        return first.from == second.from or first.from == second.to or first.to == second.from or first.to == second.to
    end

    apply_deal = function(gift)
        local key = gift.key
        local ok, why = can_transfer(gift)
        if not ok then
            if not actions.blocked then pending[key] = nil end
            return false, why
        end
        if gift.kind == influence_kind and not influence.ready(gift) then
            pending[key] = nil
            return false, tr("Both factions must still agree.", "Нужно действующее согласие обеих фракций.")
        end
        for _, running in pairs(moving) do
            if current(running) and conflicts(running, gift) then
                return false, tr("A related campaign action is already pending.", "Связанное действие уже выполняется.")
            end
        end
        pending[key] = nil
        moving[gift.id] = gift
        ok, why = pcall(function()
            if gift.kind == influence_kind then return influence.apply(gift) end
            return cm:transfer_region_to_faction(gift.region, gift.to)
        end)
        if not ok or why == false then
            moving[gift.id] = nil
            if gift.kind == influence_kind then influence.cleanup(gift) end
            return false, tr("The game rejected the action.", "Игра отклонила действие.")
        end
        local success = (gift.kind == influence_kind and tr("Confederation concluded · ", "Конфедерация заключена · ")
            or tr("Settlement transferred · ", "Поселение передано · ")) .. details(gift)
        if completed(gift) then
            moving[gift.id] = nil
            note(key, success)
            return true, success
        end
        cm:callback(function()
            moving[gift.id] = nil
            if gift.kind == influence_kind then influence.cleanup(gift) end
            if gift.campaign ~= state.data then return end
            note(key, completed(gift) and success
                or tr("The game did not confirm the result.", "Игра не подтвердила результат."))
            show(key)
        end, 1)
        return true, tr("Waiting for the game to confirm the result.", "Ожидаю подтверждения результата.")
    end

    ruler.settle = function(key, accept, me, confirmation)
        if negotiation and (negotiation.card(key) or (confirmation and confirmation:match("^exchange|"))) then
            return negotiation.settle(key, accept, confirmation)
        end
        local gift = on_table(key)
        if not gift then
            if confirmation then return false, tr("That offer has expired.", "Это предложение уже снято.") end
            return stock_settle(key, accept, me)
        end
        if not accept then
            pending[key] = nil
            return true, tr("The proposal was declined.", "Предложение отклонено.")
        end
        if confirmation ~= fingerprint(gift) then
            return false, tr("Confirm this proposal with the button on its card.", "Подтверди предложение кнопкой на карточке.")
        end
        return apply_deal(gift)
    end

    return { prepare = prepare, prompt = prompt, schema = schema, finish = finish, title = title, handle = handle,
        context = function(key) return military and military.prompt(key) or "" end }
end

return gifts
