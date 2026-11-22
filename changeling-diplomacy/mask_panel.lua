local panel = {}
local buttons = {
    toggle = "th_mask_toggle",
    explain = "th_mask_explain",
    withdraw = "th_mask_withdraw",
    insist = "th_mask_insist",
    preview_next = "th_mask_preview_next",
    preview_exit = "th_mask_preview_exit",
}
local labels = { "regard", "status", "deal_heading", "ledger_heading", "hint" }

function panel.new(deps)
    local ui, ruler = deps.ui, deps.ruler
    if not ui or not ui.show_history then return end
    local u8 = deps.u8 or TALKHAMMER_U8
    local components, shown, root = {}, {}
    local suppressed_speak
    local using_header
    local view = {}

    function view.ready()
        return ui.label ~= nil
    end

    function view.in_news()
        return ui.mode == "news"
    end

    function view.visible()
        local frame = ui.frame or ui.panel or ui.label
        if not frame then return false end
        local ok, visible = pcall(function() return frame:Visible() end)
        return ok and visible == true
    end

    local function set_button(mode, label)
        local button = components[mode]
        shown[mode] = nil
        if not button then return end
        local ok = pcall(function()
            if label then button:SetStateText(label) end
            button:SetVisible(label ~= nil)
        end)
        if ok then shown[mode] = label end
    end

    local function set_label(id, text)
        local control = components[id]
        if not control then return end
        pcall(function()
            if text then control:SetStateText(text) end
            control:SetVisible(text ~= nil)
        end)
    end

    local function use_header(masked)
        if masked == using_header then return end
        using_header = masked
        for _, name in ipairs({ "att", "reg", "mood" }) do
            local badge = ui.badges and ui.badges[name]
            if badge then pcall(function() badge:SetVisible(not masked) end) end
        end
    end

    function view.release_speak()
        if not suppressed_speak then return end
        local button = suppressed_speak
        suppressed_speak = nil
        pcall(function() button:SetVisible(true) end)
    end

    function view.controls(available, enabled, decision, preview)
        if not decision then
            for _, name in ipairs(labels) do set_label(name) end
            use_header(false)
            view.release_speak()
        end
        local checking = decision == "check" or decision == "envoy"
        set_button("toggle", available and (enabled and "Снять маску" or "Надеть маску") or nil)
        set_button("explain", checking and "Отправить объяснение" or nil)
        set_button("withdraw", checking and "Отозвать предложение" or (decision == "confirm" and "Отказаться" or nil))
        set_button("insist", decision == "check" and "Настоять" or (decision == "confirm" and "Подтвердить" or nil))
        set_button("preview_next", preview and "Далее" or nil)
        set_button("preview_exit", preview and "Выйти" or nil)
    end

    function view.command(id)
        if ui.mode ~= "talk" or not view.visible() then return end
        for mode, button in pairs(buttons) do
            if id == button and shown[mode] then return mode end
        end
    end

    function view.take_text()
        if ui.compose_take then return ui.compose_take() end
        return ""
    end

    function view.begin_preview()
        if not ui.init() then return end
        local draft = { field = ui.field, compose = ui.compose }
        if draft.field then
            local ok, text = pcall(function() return draft.field:GetStateText() end)
            if not ok then return end
            if not pcall(function() draft.field:SetStateText("") end) then return end
            draft.text = text
        end
        ui.compose = ""
        return draft
    end

    function view.end_preview(draft, restore)
        view.controls(false)
        ui.compose = restore and draft.compose or ""
        if draft.field and draft.field == ui.field then
            pcall(function() draft.field:SetStateText(restore and draft.text or "") end)
        end
    end

    function view.hide_accept()
        ruler.accept_shown, ruler.accept_armed, ui.pending_accept = nil, nil, nil
        if ui.set_accept then ui.set_accept(nil) end
    end

    local original_init, original_clear = ui.init, ui.clear_ledger
    ui.init = function(...)
        local result = original_init(...)
        if root ~= ui.panel then
            root, components = ui.panel, {}
            using_header, suppressed_speak = nil, nil
            if root and ui.deep_find then
                for mode, button in pairs(buttons) do components[mode] = ui.deep_find(root, button) end
                for _, name in ipairs(labels) do components[name] = ui.deep_find(root, "th_mask_" .. name) end
            end
            view.controls(false)
        end
        return result
    end
    if original_clear then
        ui.clear_ledger = function(...)
            local result = original_clear(...)
            if ui.mode ~= "talk" then
                view.controls(false)
            end
            set_button("explain")
            set_button("withdraw")
            set_button("insist")
            return result
        end
    end

    local function coloured(kind, text)
        if deps.state and deps.state.colour then return deps.state.colour(kind, text) end
        return text
    end

    local function append(lines, value, shade)
        if not value or value == "" then return end
        local function line(text)
            lines[#lines + 1] = shade and coloured(shade, text) or text
        end
        local from = 1
        local stop = u8.index_of(value, "\n", from)
        while stop do
            line(u8.sub(value, from, stop - 1))
            from = stop + 1
            stop = u8.index_of(value, "\n", from)
        end
        line(u8.sub(value, from))
    end

    function view.render(data)
        local label = data.preview and "Ведьма Хелеброн" or ruler.label_for(data.target)
        local checking = data.pending and data.pending.checking
        local envoy_turn = data.envoy_turn
        local has_deal = ui.set_deal and (not ui.has_deal or ui.has_deal())
        local has_ledger = ui.set_ledger and (not ui.has_ledger or ui.has_ledger())
        local author = data.identity or "Перевёртыш"
        local from, reply = coloured("you", author .. " — "), coloured("ruler", label .. " — ")
        local lines = {}
        for _, entry in ipairs(data.history) do
            if type(entry) == "string" then
                append(lines, entry)
            else
                append(lines, from .. entry.text)
                append(lines, reply .. entry.reply)
                append(lines, entry.result, "dim")
            end
            lines[#lines + 1] = ""
        end
        if data.speech then append(lines, from .. data.speech) end
        if data.waiting then lines[#lines + 1] = label .. " обдумывает ответ…" end
        if data.pending then
            append(lines, reply .. data.pending.line)
        end
        if #lines == 0 then lines[1] = data.fallback or "Введи реплику и нажми «Сказать»." end
        for _, note in ipairs(data.notice) do append(lines, note) end
        if not has_deal then append(lines, data.deal) end
        if not has_ledger then
            for _, note in ipairs(data.detail) do append(lines, note) end
        end

        ui.mode = "talk"
        if data.preview then
            if ui.set_accept then ui.set_accept(nil) end
        else
            view.hide_accept()
        end
        local history_shown = ui.show_history("", lines, label)
        if not data.preview and ruler.update_news_label then ruler.update_news_label() end
        if ui.set_sub then
            local identity = data.identity
            if identity and data.faction and not identity:find(data.faction, 1, true) then
                identity = identity .. " · " .. data.faction
            end
            ui.set_sub(identity and ("От имени: " .. identity) or "Выбери облик правителя")
        end
        if data.preview and ui.set_image then
            ui.set_image("crest")
            ui.set_image("portrait")
        elseif ruler.header_facts and ui.set_image then
            local ok, facts = pcall(ruler.header_facts, data.target)
            facts = ok and facts or {}
            ui.set_image("crest", facts.crest)
            ui.set_image("portrait", facts.portrait)
        end
        local status = data.blocked and ("Облик раскрыт · сделки с хода " .. data.blocked)
            or (envoy_turn and ("Посланник в пути · ответ на ходу " .. envoy_turn))
            or (checking and "Двор требует объяснений") or (data.pending and "Ожидает подтверждения") or nil
        view.controls(true, data.masked ~= false,
            data.pending and (envoy_turn and "envoy" or checking and "check" or "confirm") or "talk", data.preview)
        use_header(components.regard ~= nil)
        if components.regard then
            set_label("regard", data.faction and ("Отношение к " .. data.faction .. " · " .. tostring(data.attitude or "—")))
            set_label("status", status)
        elseif ui.set_badge then
            ui.set_badge("att", "ОТНОШЕНИЕ\n" .. tostring(data.attitude or "—"))
            ui.set_badge("reg", data.blocked and "Облик раскрыт" or "")
            ui.set_badge("mood", status or "")
        end
        set_label("deal_heading", has_deal and "На столе" or nil)
        local detail_heading = envoy_turn and "Проверка личности" or checking and "Что заметил двор" or "Этот разговор"
        set_label("ledger_heading", has_ledger and detail_heading or nil)
        set_label("hint", data.blocked and "Сними маску, чтобы продолжить разговор."
            or checking and "Обоснуй предложение или предложи другие условия." or nil)
        if (data.pending or data.blocked) and ui.speak_btn then
            pcall(function()
                if ui.speak_btn:Visible() then
                    suppressed_speak = ui.speak_btn
                    ui.speak_btn:SetVisible(false)
                end
            end)
        else
            view.release_speak()
        end
        local deal = data.deal or "Условий сделки пока нет."
        if has_deal then ui.set_deal(components.deal_heading and deal or "На столе\n" .. deal) end
        local ledger_shown
        if has_ledger then
            local detail = table.concat(data.detail, "\n")
            ledger_shown = ui.set_ledger(components.ledger_heading and detail or detail_heading .. "\n" .. detail)
        end
        local visible = history_shown == true and view.visible()
        return visible, visible and (not has_ledger or ledger_shown == true)
    end
    return view
end

return panel
