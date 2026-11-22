local negotiation = {}
local commission_verbs = { ["договорись"] = true, ["договоритесь"] = true,
    ["прекрати"] = true, ["прекратите"] = true, ["передай"] = true, ["передайте"] = true }
local letter_verbs = { ["передай"] = true, ["передайте"] = true, ["отправь"] = true, ["отправьте"] = true,
    ["напиши"] = true, ["напишите"] = true }
local thanks_verbs = { ["поблагодари"] = true, ["поблагодарите"] = true }

local function trim(text)
    return text:match("^%s*(.-)%s*$")
end

local function unsigned(text)
    if not text or not text:match("^%d[%d ]*$") then return end
    local amount = tonumber((text:gsub(" ", "")))
    if amount and amount >= 0 and amount < math.huge then return amount end
end

function negotiation.install(deps, api)
    local cm, state, actions, world = deps.cm, deps.state, deps.actions, deps.world
    local tr, live, report = api.tr, api.live, api.report
    local label_ruler = api.label_ruler or world.name_of
    local open, sequence = {}, 0

    local function order(key, text, player)
        text = trim(text)
        local address, message = text:match("^([^,]+),%s+(.+)$")
        local addressed_verb = message and deps.fold(message:match("^(%S+)") or "")
        if addressed_verb and (commission_verbs[addressed_verb] or letter_verbs[addressed_verb] or thanks_verbs[addressed_verb])
            and api.resolve_faction(address, player, key) == key then text = message end
        local verb, remaining = text:match("^(%S+)%s+(.+)$")
        if not verb then return end
        verb = deps.fold(verb)
        local function faction(raw) return raw and api.resolve_faction(trim(raw), player, key) end
        local addressee, content, thank = nil, nil, thanks_verbs[verb]
        if thank and not remaining:match("[?;\r\n]") then
            addressee, content = remaining:match("^(.-)%s+за%s+(.+)$")
            addressee = addressee or remaining:gsub("[.!]+$", "")
        elseif letter_verbs[verb] then
            addressee, content = remaining:match("^([^:]+):%s*(.*)$")
            if addressee then addressee = addressee:gsub("%s+сообщение%s*$", ""):gsub("%s+письмо%s*$", "") end
        end
        if addressee then
            if not thank and trim(content) == "" then
                return nil, tr("Write the message after the colon.", "Добавь текст сообщения после двоеточия.")
            end
            local recipient = faction(addressee)
            if not recipient or recipient == key or recipient == player then
                return nil, tr("Name one other ruler to receive the message.", "Назови другого правителя, которому нужно доставить сообщение.")
            end
            return { kind = "letter", key = key, target = recipient, player = player, content = content, thank = thank }
        end
        if remaining:match("[?;\r\n]") then return end
        remaining = remaining:gsub("[.!]+$", "")
        local kind, target, from, to, first, second, cap, pact
        if verb == "договорись" or verb == "договоритесь" then
            local named, direction = remaining:match("^с (.-) о конфедерации%.%s*(.+)$")
            if named then
                local a, b = direction:match("^(.-) должен войти в (.+)$")
                if not a then a, b = direction:match("^(.-) должна войти в (.+)$") end
                kind, target, from, to = "union", faction(named), faction(a), faction(b)
            else
                local partner, budget = remaining:match("^о мире с ([^.]+)%.%s*(.+)$")
                if not partner then partner = remaining:match("^о мире с ([^.]+)$") end
                if partner then
                    kind, target = "peace", faction(partner)
                    cap = budget and unsigned(deps.fold(budget):match("^можешь предложить до ([%d ]+) золота$")) or 0
                    if budget and cap == 0 then
                        return nil, tr("Specify a positive gold limit.", "Укажи предел золотом, например «Можешь предложить до 5000 золота».")
                    end
                end
            end
        elseif verb == "прекрати" or verb == "прекратите" then
            local named = remaining:match("^войну с (.-) и заключите пакт о ненападении$")
            if not named then named = remaining:match("^войну с (.-) и заключи пакт о ненападении$") end
            if not named then named = remaining:match("^войну с (.+)$") else pact = true end
            if named then kind, target, cap = "peace", faction(named), 0 end
        elseif verb == "передай" or verb == "передайте" then
            local offered, subject, wanted = remaining:match("^(.-),%s*если (%S+) уступит тебе (.+)$")
            if not offered or (subject ~= "он" and subject ~= "она") then return end
            kind = "exchange"
            wanted = trim(wanted)
            for split in offered:gmatch("()%s+") do
                local other = faction(offered:sub(1, split - 1))
                if other and other ~= key and other ~= player then
                    local outgoing = api.resolve_region(trim(offered:sub(split)), key)
                    local incoming = api.resolve_region(wanted, other)
                    if outgoing and incoming then
                        if target and (target ~= other or first ~= outgoing or second ~= incoming) then
                            return nil, tr("Name both settlements and one recipient.", "Укажи два точных названия поселений и одного получателя.")
                        end
                        target, first, second = other, outgoing, incoming
                    end
                end
            end
        end
        if not kind then return end
        if not target or target == key or target == player
            or (kind == "union" and not ((from == key and to == target) or (from == target and to == key))) then
            return nil, tr("Identify the other faction and the exact terms.", "Уточни вторую фракцию и условия сделки.")
        end
        return { kind = kind, key = key, target = target, player = player, from = from, to = to,
            first = first, second = second, cap = cap, pact = pact }
    end

    local function fresh(deal)
        return deal.campaign == state.data and deal.turn == cm:turn_number()
            and deal.player == cm:get_local_faction_name(true)
    end

    local function active(key)
        local deal = open[key]
        if deal and (deal.campaign ~= state.data or (not fresh(deal) and deal.phase ~= "applying")) then
            if deal.listener then deps.core:remove_listener(deal.listener) end
            open[key], deal = nil, nil
        end
        return deal
    end

    local function busy(key)
        for actor in pairs(open) do
            local deal = active(actor)
            if deal and (deal.key == key or deal.target == key) then return true end
        end
        return false
    end

    local function eligible(deal)
        if not fresh(deal) or (deal.kind ~= "letter" and not api.direct()) or actions.blocked then
            return false, tr("This commission is no longer available.", "Это поручение больше недоступно.")
        end
        local first, second, player = live(deal.key), live(deal.target), live(deal.player)
        if not (first and second and player) or first:is_human() or second:is_human()
            or not first:is_vassal_of(player) then
            return false, tr("Address your active AI vassal.", "Обратись к действующему вассалу под управлением ИИ.")
        end
        if deal.kind == "letter" then return true end
        if deal.kind == "union" then
            if first:subculture() ~= second:subculture() or first:at_war_with(second) then
                return false, tr("Confederation requires peace and a shared subculture.", "Для конфедерации нужен мир и общая субкультура.")
            end
            return type(cm.force_confederation) == "function" and deps.core ~= nil,
                tr("Confederation is unavailable.", "Действие конфедерации недоступно.")
        end
        if deal.kind == "exchange" then
            if api.owner_of(deal.first) ~= deal.key or api.owner_of(deal.second) ~= deal.target then
                return false, tr("One of the settlements has changed hands.", "Одно из поселений сменило владельца.")
            end
            if first:at_war_with(second) then
                return false, tr("Both sides must be at peace to exchange settlements.", "Для обмена поселениями стороны должны заключить мир.")
            end
            return true
        end
        if not first:at_war_with(second) then
            return false, tr("The two factions are already at peace.", "Эти фракции уже находятся в мире.")
        end
        if deal.cap > (actions.max_payment or 100000) or (deal.gold or 0) > player:treasury() then
            return false, tr("The payment exceeds the available treasury or game limit.", "Платёж превышает доступную казну или предел сделки.")
        end
        return true
    end

    local function details(deal)
        local a, b = world.name_of(deal.key), world.name_of(deal.target)
        if deal.kind == "union" then
            return world.name_of(deal.from) .. " → " .. world.name_of(deal.to)
        elseif deal.kind == "exchange" then
            return a .. " → " .. api.place_name(deal.first) .. " → " .. b
                .. "\n" .. b .. " → " .. api.place_name(deal.second) .. " → " .. a
        end
        return a .. " ↔ " .. b .. (deal.pact and tr(" · peace and non-aggression", " · мир и пакт о ненападении") or "")
    end

    local function conditions(deal)
        if deal.kind == "union" then
            return "Confederation: " .. world.name_of(deal.to) .. " absorbs " .. world.name_of(deal.from)
                .. ". " .. world.name_of(deal.from) .. " ceases to be independent."
        elseif deal.kind == "exchange" then
            return "Settlement exchange. " .. world.name_of(deal.key) .. " gives " .. api.place_name(deal.first)
                .. " to " .. world.name_of(deal.target) .. " in exchange for " .. api.place_name(deal.second) .. "."
        end
        return "End the war between " .. world.name_of(deal.key) .. " and " .. world.name_of(deal.target)
            .. (deal.pact and " and immediately sign a non-aggression pact." or ".")
            .. (deal.cap > 0 and " The player will pay the second party up to " .. deal.cap
                .. " gold if needed. Request the least you accept. This is the only permitted concession." or " No payment.")
    end

    local function conclude(deal, message, recipient)
        if deal.listener then
            deps.core:remove_listener(deal.listener)
            deal.listener = nil
        end
        if open[deal.key] == deal then open[deal.key] = nil end
        if deal.campaign == state.data then report(deal.key, message, recipient) end
    end

    local function attempt(method, ...)
        if type(cm[method]) ~= "function" then return false end
        local ok, result = pcall(cm[method], cm, ...)
        return ok and result ~= false
    end

    local function verify(deal, check, then_do)
        local ok, changed = pcall(check)
        if ok and changed then return then_do(true) end
        cm:callback(function()
            if open[deal.key] ~= deal then return end
            if deal.campaign ~= state.data then open[deal.key] = nil; return end
            local worked, confirmed = pcall(check)
            then_do(worked and confirmed == true)
        end, 1)
    end

    local function did_not_apply(deal)
        conclude(deal, tr("The game did not confirm the agreement.", "Игра не подтвердила исполнение сделки.") .. " · " .. details(deal))
    end

    local function apply_union(deal)
        local listener = "TalkHammerEnvoyConfederation" .. deal.id
        local confirmed
        deal.listener = listener
        deps.core:add_listener(listener, "FactionJoinsConfederation", function(context)
            return context:faction():name() == deal.from and context:confederation():name() == deal.to
        end, function() deal.listener, confirmed = nil, true end, false)
        attempt("force_confederation", deal.to, deal.from)
        verify(deal, function() return confirmed == true end, function(result)
            if result then conclude(deal, tr("Confederation concluded", "Конфедерация заключена") .. " · " .. details(deal))
            else did_not_apply(deal) end
        end)
    end

    local function pay(deal)
        if deal.gold == 0 then return true end
        local player, recipient = live(deal.player), live(deal.target)
        if not player or not recipient then return false end
        local before, funds = player:treasury(), recipient:treasury()
        if before < deal.gold then return false end
        attempt("treasury_mod", deal.player, -deal.gold)
        if player:treasury() ~= before - deal.gold then return false end
        attempt("treasury_mod", deal.target, deal.gold)
        if recipient:treasury() == funds + deal.gold then return true end
        if recipient:treasury() == funds then attempt("treasury_mod", deal.player, deal.gold) end
        return false
    end

    local function apply_peace(deal)
        local function at_peace()
            local a, b = live(deal.key), live(deal.target)
            return a and b and not a:at_war_with(b)
        end
        if deal.gold > 0 and type(cm.treasury_mod) ~= "function" then return did_not_apply(deal) end
        attempt("force_make_peace", deal.key, deal.target)
        verify(deal, at_peace, function(result)
            if not result then return did_not_apply(deal) end
            local message = tr("Peace concluded", "Мир заключён") .. " · " .. details(deal)
            if deal.gold > 0 then
                local paid = pay(deal)
                message = message .. " · " .. (paid and tr("Paid ", "Уплачено ") .. deal.gold
                    or tr("Payment could not be confirmed", "Платёж не подтверждён"))
            end
            if not deal.pact then return conclude(deal, message) end
            attempt("force_non_aggression_pact", deal.key, deal.target)
            verify(deal, function()
                local a, b = live(deal.key), live(deal.target)
                return a and b and a:non_aggression_pact_with(b) == true
            end, function(pact)
                conclude(deal, message .. " · " .. (pact and tr("Pact signed", "Пакт заключён")
                    or tr("Pact was not confirmed", "Пакт не подтверждён")))
            end)
        end)
    end

    local function apply_exchange(deal)
        attempt("transfer_region_to_faction", deal.first, deal.target)
        verify(deal, function() return api.owner_of(deal.first) == deal.target end, function(outgoing)
            if not outgoing then return did_not_apply(deal) end
            if api.owner_of(deal.second) == deal.target and live(deal.key) then
                attempt("transfer_region_to_faction", deal.second, deal.key)
            end
            verify(deal, function()
                return api.owner_of(deal.first) == deal.target and api.owner_of(deal.second) == deal.key
            end, function(exchanged)
                if exchanged then return conclude(deal, tr("Exchange completed", "Обмен завершён") .. " · " .. details(deal)) end
                if api.owner_of(deal.first) == deal.target and api.owner_of(deal.second) ~= deal.key and live(deal.key) then
                    attempt("transfer_region_to_faction", deal.first, deal.key)
                end
                verify(deal, function() return api.owner_of(deal.first) == deal.key end, function(restored)
                    conclude(deal, restored and tr("The game refused the exchange. The first settlement was returned.",
                        "Игра отклонила обмен. Первое поселение вернулось владельцу.")
                        or tr("The exchange was only partially completed. Check both owners.",
                            "Обмен исполнен частично. Проверь владельцев обоих поселений."))
                end)
            end)
        end)
    end

    local handlers = { union = apply_union, peace = apply_peace, exchange = apply_exchange }
    local function start_applying(deal)
        deal.phase = "applying"
        local ok = pcall(handlers[deal.kind], deal)
        if not ok then did_not_apply(deal) end
    end

    local function hear(deal, who, first_party)
        local phase = first_party and "envoy" or "recipient"
        deal.phase = phase
        local prompt = (first_party and "Your overlord asks you to serve as their envoy and give consent for your own faction."
            or world.name_of(deal.key) .. " sent an envoy on the player's behalf and agreed to the exact stated conditions.")
            .. "\n" .. conditions(deal)
            .. "\nDecide for your own faction only. Return accept only for the exact deal. "
            .. "Use counter for any additional condition, decline for refusal. No agreement has taken effect yet."
            .. ((first_party or deal.kind ~= "peace") and " Set gold to zero."
                or " Set gold to the required payment within the stated limit, zero if you accept with no payment.")
        local requested, sent = pcall(api.ask, who, prompt, function(line, decision)
            if active(deal.key) ~= deal or deal.phase ~= phase then return end
            if line and line ~= "" then report(deal.key, world.name_of(who) .. " · " .. line) end
            if not decision or decision.verdict ~= "accept" then
                return conclude(deal, tr("The envoy has no agreement from ", "Посланник не получил согласия от ") .. world.name_of(who))
            end
            local gold = decision.gold
            if type(gold) ~= "number" or gold ~= math.floor(gold) or gold < 0
                or gold > ((not first_party and deal.kind == "peace") and deal.cap or 0) then
                return conclude(deal, tr("The requested payment exceeds the approved terms.",
                    "Запрошенный платёж выходит за пределы поручения."))
            end
            deal.gold = gold
            local ok, reason = eligible(deal)
            if not ok then return conclude(deal, reason) end
            if first_party then return hear(deal, deal.target, false) end
            if api.occupied(deal.key, deal.turn) then
                return conclude(deal, tr("Another deal is already on the table.", "На столе уже есть другая сделка."))
            end
            if deal.kind == "exchange" then
                deal.phase = "confirm"
                report(deal.key, tr("Both sides agreed. Confirm the exchange on its card.",
                    "Обе стороны согласны. Подтверди обмен на карточке."))
            else
                start_applying(deal)
            end
        end)
        if (not requested or not sent) and active(deal.key) == deal and deal.phase == phase then
            conclude(deal, tr("The envoy could not contact the court.", "Посланнику не удалось связаться с двором."))
        end
    end

    local function correspond(deal, letter)
        local from, to = label_ruler(deal.key), label_ruler(deal.target)
        local turn_phase = letter and "letter_reply" or "letter_write"
        deal.phase = turn_phase
        local who, prompt
        if letter then
            who = deal.target
            prompt = "A diplomatic message addressed to you from " .. from .. ":\n" .. letter
                .. "\nReply in your own voice. You may acknowledge it or refuse. Set gold to zero."
                .. " This correspondence cannot conclude a treaty, spend money, or order a campaign action."
        else
            who = deal.key
            local assignment = deal.thank and ("Thank the recipient" .. (deal.content and (" for: " .. deal.content) or "."))
                or ("Convey the following message in your own words: " .. deal.content)
            prompt = "Your overlord asks you to address a diplomatic message to " .. to .. ". " .. assignment
                .. "\nIf you agree, return accept and write the message addressed to the recipient in line."
                .. " If you refuse, return decline and give the overlord your reason instead. Set gold to zero."
                .. " This correspondence cannot conclude a treaty or order a campaign action."
        end

        local function reply(line, decision)
            if open[deal.key] ~= deal or deal.phase ~= turn_phase then return end
            local ok, reason = eligible(deal)
            if not ok then return conclude(deal, reason) end
            line = type(line) == "string" and trim(line:gsub("%s+", " ")) or ""
            if not decision or decision.gold ~= 0 or line == "" then
                return conclude(deal, tr("The exchange could not be completed.", "Не удалось завершить обмен сообщениями."))
            end
            if not letter then
                if decision.verdict == "accept" then return correspond(deal, line) end
                return conclude(deal, tr("%s declined to send the message. %s", "Отказ от отправки. %s: %s"):format(from, line))
            end
            local exchange = tr("Correspondence between %s and %s", "Переписка между %s и %s"):format(from, to)
                .. "\n" .. from .. ": " .. letter .. "\n" .. to .. ": " .. line
            conclude(deal, exchange, deal.target)
        end
        local requested, sent = pcall(api.ask, who, prompt, reply, true)
        if not requested or not sent then reply() end
    end

    local function handle(key, text, player, turn)
        if not api.direct() then return false end
        local deal, why = order(key, text, player)
        if not deal then return why ~= nil, why end
        if busy(key) or busy(deal.target) or api.occupied(key, turn) then
            return true, tr("Resolve the current proposal first.", "Сначала заверши текущее поручение или сделку.")
        end
        deal.turn, deal.campaign = turn, state.data
        local ok, reason = eligible(deal)
        if not ok then return true, reason end
        sequence = sequence + 1
        deal.id = sequence
        open[key] = deal
        if deal.kind == "letter" then
            report(key, tr("Preparing a message for ", "Готовится сообщение для ") .. label_ruler(deal.target) .. ".")
            correspond(deal)
        else
            report(key, tr("Commission given · ", "Поручение принято к рассмотрению · ") .. details(deal))
            hear(deal, key, true)
        end
        return true
    end

    local function card(key)
        local deal = active(key)
        if not deal or deal.phase ~= "confirm" then return end
        return {
            kind = "settlement_exchange", expansion = true, print = "exchange|" .. deal.turn .. "|" .. deal.id,
            label = tr("ACCEPT EXCHANGE", "ПРИНЯТЬ ОБМЕН"), confirm = tr("CONFIRM EXCHANGE", "ПОДТВЕРДИТЬ ОБМЕН"),
            what = details(deal),
        }
    end

    local function settle(key, accept, confirmation)
        local deal = active(key)
        local spec = card(key)
        if not spec then return false, tr("The exchange has expired.", "Предложение об обмене уже снято.") end
        if not accept then
            open[key] = nil
            return true, tr("Exchange declined.", "Обмен отклонён.")
        end
        if confirmation ~= spec.print then
            return false, tr("Confirm the exchange on its card.", "Подтверди обмен кнопкой на карточке.")
        end
        local ok, why = eligible(deal)
        if not ok then open[key] = nil; return false, why end
        start_applying(deal)
        return true, tr("Applying the agreed exchange.", "Игра оформляет согласованный обмен.")
    end

    return { handle = handle, card = card, settle = settle, busy = busy }
end

return negotiation
