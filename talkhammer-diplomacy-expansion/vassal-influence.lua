local influence = {}

function influence.install(deps, helpers)
    local cm, core, fold, world = deps.cm, deps.core, deps.fold, deps.world
    local current, living_faction, tr = helpers.current, helpers.living_faction, helpers.tr
    local consents = {}

    local function pair(proposal)
        return proposal.from .. "|" .. proposal.to
    end

    local function valid(proposal)
        local player = living_faction(proposal.player)
        local absorbed, absorber = living_faction(proposal.from), living_faction(proposal.to)
        if not (player and absorbed and absorber) or absorbed:is_human() or absorber:is_human() then
            return false, tr("Choose two active AI factions.", "Выбери две действующие фракции под управлением ИИ.")
        end
        if absorbed:subculture() ~= absorber:subculture() then
            return false, tr("These factions belong to different subcultures.", "Эти фракции относятся к разным субкультурам.")
        end
        if absorbed:at_war_with(absorber) then
            return false, tr("The factions must make peace first.", "Сначала этим фракциям нужно заключить мир.")
        end
        if not (absorbed:is_vassal_of(player) or absorber:is_vassal_of(player)) then
            return false, tr("At least one faction must be your vassal.", "Хотя бы одна из фракций должна быть твоим вассалом.")
        end
        if type(cm.force_confederation) ~= "function" or not core then
            return false, tr("Confederation is unavailable.", "Конфедерация недоступна.")
        end
        return true
    end

    local function parse_fields(command, value)
        command = fold((command:match("^%s*(.-)%s*$")))
        if command == "конфедерация" or command == "confederation" then
            local absorbed, absorber = value:match("^%s*(.-)%s*%-%>%s*(.-)%s*$")
            return absorbed, absorber, true
        end
    end

    local function parse(text)
        local label, text_after_label = text:match("^%s*([^:%[%]]+):([^%[%]]*)$")
        if label then
            local absorbed, absorber, explicit = parse_fields(label, text_after_label)
            if explicit then return absorbed, absorber, explicit end
        end
        for command, value in text:gmatch("%[([^:%]]+):([^%]]*)%]") do
            local absorbed, absorber, explicit = parse_fields(command, value)
            if explicit then return absorbed, absorber, explicit end
        end
        return nil, nil, false
    end

    local function agreement(proposal)
        local key = pair(proposal)
        local entry = consents[key]
        if entry and not current(entry.proposal) then
            consents[key], entry = nil, nil
        end
        return entry
    end

    local function ready(proposal)
        local entry = agreement(proposal)
        return entry and entry[proposal.from] and entry[proposal.to]
    end

    local function consent(proposal, agreed)
        local entry = agreement(proposal) or { proposal = proposal }
        entry[proposal.key] = agreed and true or nil
        consents[pair(proposal)] = entry
        return ready(proposal)
    end

    local function other_party(proposal)
        return proposal.key == proposal.from and proposal.to or proposal.from
    end

    local function prompt(proposal)
        local other = other_party(proposal)
        local entry = agreement(proposal)
        local they_agreed = entry and entry[other]
        local self = cm:get_faction(proposal.key)
        local player = cm:get_faction(proposal.player)
        local is_vassal = self:is_vassal_of(player)
        return "\n\nCONFEDERATION MEDIATED BY THE PLAYER: " .. world.name_of(proposal.to)
            .. " would absorb " .. world.name_of(proposal.from) .. "."
            .. (is_vassal and " The player is your overlord and is explicitly asking for your agreement."
                or " The player is mediating a decision involving their vassal.")
            .. (they_agreed and " The other faction has already agreed to this exact direction."
                or " The other faction has not agreed in this negotiation yet.")
            .. " Answer for your faction alone. Set influence_agreed=true only if you consent to the exact"
            .. " direction with no outstanding condition. Otherwise use false. The confederation needs"
            .. " both decisions and the player's confirmation. Do not say it has happened. Use action=none."
    end

    local function apply(proposal)
        proposal.listener = "TalkHammerDiplomacyExpansionConfederation" .. proposal.id
        core:add_listener(proposal.listener, "FactionJoinsConfederation", function(context)
            return context:faction():name() == proposal.from and context:confederation():name() == proposal.to
        end, function()
            proposal.listener = nil
            proposal.confirmed = true
        end, false)
        return cm:force_confederation(proposal.to, proposal.from)
    end

    local function completed(proposal)
        return proposal.confirmed == true
    end

    local function cleanup(proposal)
        if proposal.listener then
            core:remove_listener(proposal.listener)
            proposal.listener = nil
        end
    end

    return {
        parse = parse, valid = valid, ready = ready, consent = consent, other_party = other_party,
        prompt = prompt, apply = apply, completed = completed, cleanup = cleanup,
    }
end

return influence
