local gifts = {}

local function has_completion_note(entry, record, donor, settlement, recipient)
    local triplet = donor .. " → " .. settlement .. " → " .. recipient
    local russian = settlement .. " · Даритель: " .. donor .. " · Получатель: " .. recipient
    local english = settlement .. " · Donor: " .. donor .. " · Recipient: " .. recipient
    for _, note in ipairs(record.history or record.memory or {}) do
        if note.speaker == "note" and note.turn == entry.t then
            if note.line == "Поселение передано · " .. triplet or note.line == "Settlement transferred · " .. triplet
                or note.line == "Поселение передано · " .. russian or note.line == "Settlement transferred · " .. english then
                return true
            end
        end
    end
    return false
end

function gifts.install(chronicle, state, world, cm, region_name)
    local tracked, tracked_turn = {}, cm:turn_number()
    local function current_transfers()
        local turn = cm:turn_number()
        if turn ~= tracked_turn then tracked, tracked_turn = {}, turn end
        return tracked
    end

    function chronicle.begin_settlement_gift(gift)
        current_transfers()[gift.region] = { gift = gift }
    end

    function chronicle.finish_settlement_gift(gift, confirmed)
        local transfers = current_transfers()
        local transfer = transfers[gift.region]
        if not transfer or transfer.gift ~= gift or gift.campaign ~= state.data then return end
        if not confirmed then
            transfers[gift.region] = nil
        elseif not transfer.confirmed then
            transfer.confirmed = true
            chronicle.add("settlement_gift", gift.from, gift.to, gift.region)
        end
    end

    function chronicle.is_settlement_gift_change(region, previous, owner)
        local transfers = current_transfers()
        local transfer = transfers[region]
        if not transfer then return false end
        local gift = transfer.gift
        if gift.campaign == state.data and gift.to == owner and (not previous or gift.from == previous) then
            return true
        end
        transfers[region] = nil
        return false
    end

    local factions = state.data and state.data.factions or {}
    for _, entry in ipairs(state.data and state.data.chronicle or {}) do
        local record = entry.k == "region" and entry.b and factions[entry.b]
        if record and entry.r and entry.a then
            local donor, recipient = world.name_of(entry.b), world.name_of(entry.a)
            if type(donor) == "string" and type(recipient) == "string"
                and has_completion_note(entry, record, donor, region_name(entry.r), recipient) then
                entry.k, entry.a, entry.b = "settlement_gift", entry.b, entry.a
            end
        end
    end
end

return gifts
