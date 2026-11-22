local panel = {}
local prefix = "th_gift_"
local page_size = 8
local control_ids = { "open", "header", "previous", "next", "back", "send" }
local exits = { th_mask_toggle = true, th_news = true, th_close = true }

function panel.install(deps)
    local ui, ruler, cm, state = deps.ui, deps.ruler, deps.cm, deps.state
    local components, root, selection, open_shown = {}, nil, nil, nil
    local queued
    local function tr(en, ru) return deps.language() == "ru" and ru or en end
    local function available()
        if ui.mode ~= "talk" or not ui.frame or not ui.field or not ui.speak_btn or not ruler.counterpart or ruler.accept_shown
            or (ruler.expansion_mask_active and ruler.expansion_mask_active())
            or (ruler.awaiting and ruler.awaiting[ruler.counterpart]) then return false end
        local ok, visible = pcall(function() return ui.frame:Visible() end)
        return ok and visible
    end
    local function current()
        return selection and available() and selection.key == ruler.counterpart
            and selection.turn == cm:turn_number() and selection.campaign == state.data
    end
    local function set(id, label)
        local control = components[id]
        if label then control:SetStateText(label) end
        control:SetVisible(label ~= nil)
    end
    local function close()
        local draft = selection and selection.draft
        selection = nil
        queued = nil
        if components.picker then pcall(function() components.picker:SetVisible(false) end) end
        if draft then
            pcall(function()
                draft.field:SetStateText(draft.text)
                draft.field:SetVisible(draft.field_visible)
            end)
            pcall(function()
                draft.button:SetStateText(draft.caption)
                draft.button:SetVisible(draft.button_visible)
            end)
        end
    end
    local function guard(fn, ...)
        local ok, reason = pcall(fn, ...)
        if ok then return end
        close()
        if deps.log then deps.log("EXPANSION|picker: " .. tostring(reason)) end
    end
    local function refresh()
        if not components.picker then return end
        if selection and not current() then close() end
        local visible = not selection and not not available()
        if visible ~= open_shown then
            open_shown = visible
            set("open", visible and tr("Settlement gift", "Дар поселения") or nil)
        end
    end

    local function draw()
        local step = selection.step
        local review = step == "review"
        local choices = {}
        local query = review and "" or deps.fold(selection.filter)
        for _, choice in ipairs(selection.choices) do
            if query == "" or deps.index_of(deps.fold(choice.label), query) then choices[#choices + 1] = choice end
        end
        local pages = math.max(1, math.ceil(#choices / page_size))
        selection.page = math.min(pages, math.max(selection.page, 1))
        local start = (selection.page - 1) * page_size
        selection.displayed = {}
        for index = 1, page_size do
            local choice = not review and choices[start + index] or nil
            selection.displayed[index] = choice
            set("choice_" .. index, choice and choice.label)
        end
        local heading = step == "city" and tr("Choose a settlement", "Выбери поселение")
            or tr("Choose the recipient", "Выбери получателя")
        if review then
            heading = tr("Propose a gift", "Предложить дар") .. "\n" .. selection.city.label .. " → " .. selection.recipient.label
        else
            if pages > 1 then heading = heading .. "  •  " .. selection.page .. "/" .. pages end
            if #choices == 0 then heading = heading .. "\n" .. tr("No matches", "Ничего не найдено") end
        end
        set("header", heading)
        set("previous", not review and selection.page > 1 and tr("Previous", "Назад ←") or nil)
        set("next", not review and selection.page < pages and tr("Next", "Далее →") or nil)
        set("back", step == "city" and tr("Cancel", "Отмена") or tr("Back", "Назад"))
        set("send", review and tr("Propose gift", "Предложить дар") or nil)
        components.picker:SetVisible(true)
        refresh()
    end
    local function choose_step(step, choices)
        selection.step, selection.choices, selection.page, selection.filter = step, choices, 1, ""
        local searching = step ~= "review"
        ui.field:SetStateText("")
        ui.field:SetVisible(searching)
        ui.speak_btn:SetStateText(tr("Search", "Найти"))
        ui.speak_btn:SetVisible(searching)
        draw()
    end
    local function update_search()
        if selection.step == "review" then return end
        local raw = ui.field:GetStateText()
        local query = type(raw) == "string" and raw:match("^%s*(.-)%s*$") or ""
        if query ~= selection.filter then
            selection.filter, selection.page = query, 1
            draw()
        end
    end
    local function click(id)
        if id == "open" then
            if not open_shown or not available() or not components.picker then return end
            local key = ruler.counterpart
            selection = { key = key, turn = cm:turn_number(), campaign = state.data, draft = {
                field = ui.field, button = ui.speak_btn, text = ui.field:GetStateText() or "",
                caption = ui.speak_btn:GetStateText() or tr("Speak", "Сказать"),
                field_visible = ui.field:Visible(), button_visible = ui.speak_btn:Visible(),
            } }
            choose_step("city", ruler.gift_choices(key))
            return
        end
        if not current() then close(); refresh(); return end
        if id == "back" then
            if selection.step == "review" then
                choose_step("recipient", ruler.gift_choices(selection.key, selection.city.key))
            elseif selection.step == "recipient" then
                choose_step("city", ruler.gift_choices(selection.key))
            else
                close()
                refresh()
            end
        elseif id == "send" and selection.step == "review" then
            local key, region, recipient = selection.key, selection.city.key, selection.recipient.key
            close()
            refresh()
            ruler.offer_settlement_gift(key, region, recipient)
        elseif id == "previous" or id == "next" then
            selection.page = selection.page + (id == "next" and 1 or -1)
            draw()
        else
            local index = tonumber(id:match("^choice_(%d+)$"))
            local picked = index and selection.displayed[index]
            if picked and selection.step == "city" then
                selection.city = picked
                choose_step("recipient", ruler.gift_choices(selection.key, picked.key))
            elseif picked and selection.step == "recipient" then
                selection.recipient = picked
                choose_step("review", {})
            end
        end
    end

    local init, tick, hide = ui.init, ruler.tick, ui.hide
    ui.init = function(...)
        local result = init(...)
        if result and ui.panel and ui.panel ~= root then
            root, components, selection, open_shown = ui.panel, {}, nil, nil
            components.picker = ui.deep_find(root, prefix .. "picker")
            if components.picker then
                components.picker:SetVisible(false)
                for _, id in ipairs(control_ids) do components[id] = ui.deep_find(root, prefix .. id) end
                for index = 1, page_size do
                    components["choice_" .. index] = ui.deep_find(root, prefix .. "choice_" .. index)
                end
                refresh()
            end
        end
        return result
    end
    ruler.tick = function(...)
        -- Release the field before the mask or native conversation redraws it.
        if selection and not current() then close() end
        local result = tick(...)
        local event = queued
        queued = nil
        guard(function()
            refresh()
            if event and event.key == ruler.counterpart and event.selection == selection and event.root == root then
                click(event.id)
            end
            if selection then update_search() end
        end)
        return result
    end
    ui.hide = function(...)
        close()
        return hide(...)
    end
    deps.core:add_listener("TalkHammerGiftPicker", "ComponentLClickUp", function(context)
        local id = context.string
        return type(id) == "string" and (exits[id] or id:sub(1, #prefix) == prefix)
    end, function(context)
        local id = context.string
        if exits[id] then
            close()
        else
            queued = { id = id:sub(#prefix + 1), key = ruler.counterpart, selection = selection, root = root }
        end
    end, true)
    return { consume_speak = function()
        if not selection then return false end
        if current() then guard(update_search) else close(); guard(refresh) end
        return true
    end }
end

return panel
