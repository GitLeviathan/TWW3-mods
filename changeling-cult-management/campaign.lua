local layout_root = "ui/campaign ui/changeling_cult_management/"
local saved_key = "changeling_cult_management_preset"
local inbox_key = "changeling_cult_management_new_cults"
local per_page = 6
local empty = {gold={}, books={}, spread={}, remove={}}
local tabs = {"gold", "books", "spread", "remove"}
local tab_names = {gold="Доход", books="Гримуары", spread="Распространение", remove="Снос"}
local criteria = {
    gold = "Сначала быстрее окупится · только постройки с долей дохода поселения",
    books = "Сначала дешевле по золоту, затем по ресурсам культа",
    spread = "Сначала без постройки, затем больше доступных провинций",
    remove = "Постройки распространения в культах без доступных соседних поселений",
}
local modes = {"off", "offer", "auto"}
local mode_name = {off="Вручную", offer="Предложить пресет", auto="Автоматически при основании"}
local preset = {mode="off", levels={"", "", ""}}
local draft = {mode="off", levels={"", "", ""}}
local options = {""}
for key, building in pairs(catalog.builds) do
    if building.tier == 1 and (building.group ~= "gold" or building.share) then options[#options + 1] = key end
end
table.sort(options)

local opener, panel
local controls, pending, selections, selected_slots, recent = {}, {}, {}, {}, {}
local rows, tab, page = empty, "gold", 1
local queue_page, offer_index = 1, 1
local reviewing, scanning, busy = nil, false, false
local scan_id = 0
local feedback = ""
local show_preset = false
local page_jobs = {}
local render, refresh, drain_presets

local function log(value)
    out("CULT_MANAGEMENT|" .. tostring(value))
end

local function localise(key, fallback)
    local value = common.get_localised_string(key)
    return type(value) == "string" and value ~= "" and value ~= key and value or fallback
end

local function settlement_name(key)
    return localise("regions_onscreen_" .. key, key)
end

local function building_name(key)
    if key == "" then return "Пропустить" end
    local level = catalog.builds[key]
    local generic = tab_names[level.group] .. (level.branch == "symbiotic" and " · симбиоз" or " · паразитизм")
    local name = localise("building_culture_variants_name_" .. key .. catalog.faction,
        localise("building_levels_onscreen_name_" .. key, generic))
    return name .. " " .. ({"I", "II", "III"})[level.tier]
end

local function player()
    return cm:get_faction(catalog.faction)
end

local function player_turn()
    return cm:get_local_faction_name(true) == catalog.faction and cm:is_local_players_turn()
end

local function balances()
    local faction = player()
    local resource = faction:pooled_resource_manager():resource(catalog.resource)
    return faction:treasury(), resource:is_null_interface() and 0 or resource:value()
end

local function target_counts(region)
    local provinces, province_count, settlement_count = {}, 0, 0
    local neighbors = region:adjacent_region_list()
    for i = 0, neighbors:num_items() - 1 do
        local neighbor = neighbors:item_at(i)
        local owner = neighbor:owning_faction()
        if not neighbor:is_abandoned() and not owner:is_null_interface() and owner:name() ~= catalog.faction
            and neighbor:foreign_slot_manager_for_faction(catalog.faction):is_null_interface() then
            settlement_count = settlement_count + 1
            local province = neighbor:province_name()
            if not provinces[province] then
                provinces[province] = true
                province_count = province_count + 1
            end
        end
    end
    return province_count, settlement_count
end

local function site_of(region, manager)
    local key = region:name()
    local provinces, targets = target_counts(region)
    local has_spread = false
    local slots = manager:slots()
    for i = 0, slots:num_items() - 1 do
        local slot = slots:item_at(i)
        if slot:has_building() then
            local level = catalog.builds[slot:building()]
            if level and level.group == "spread" then has_spread = true; break end
        end
    end
    local province = region:province_name()
    return {name=settlement_name(key), province=localise("provinces_onscreen_" .. province, nil),
        gdp=region:gdp(), provinces=provinces, targets=targets, has_spread=has_spread}
end

local function control(id)
    local element = controls[id]
    if not element then
        element = find_uicomponent(panel, "cmgr_" .. id)
        controls[id] = element
    end
    return element
end

local function visible(id, value)
    local child = control(id)
    if child then child:SetVisible(value) end
end

local function write(id, value)
    local child = control(id)
    if child then child:SetStateText(value or "") end
end

local function button(id, value, enabled, active)
    local child = control(id)
    if child then
        child:SetState(enabled and (active and "selected" or "active") or "inactive")
        child:SetStateText(value)
        child:SetInteractive(enabled)
    end
end

local function update_opener()
    if opener then
        local count = 0
        for _ in pairs(pending) do count = count + 1 end
        opener:SetStateText(count > 0 and ("Культы · " .. count) or "Управление культами")
    end
end

local function reset_selection()
    selections, selected_slots, reviewing = {}, {}, nil
    queue_page = 1
end

local function choose(job, enabled)
    local current = selected_slots[job.slot]
    if current then
        selected_slots[job.slot] = nil
        for index, value in ipairs(selections) do
            if value == current then table.remove(selections, index); break end
        end
    end
    if enabled then
        selections[#selections + 1] = job
        selected_slots[job.slot] = job
    end
    reviewing = nil
    queue_page = 1
end

local function is_selected(job)
    local selected = selected_slots[job.slot]
    return selected and management.same(selected, job)
end

local function effect(job)
    if job.group == "gold" then
        return string.format("+%d зол. / ход\n%d → %d%% · %.1f х.", job.gain, job.old_share * 100, job.share * 100, job.payback)
    elseif job.group == "books" then
        return "+" .. tostring(job.gain) .. " гримуаров / ход"
    end
    return tostring(job.site.provinces) .. " пров. · " .. tostring(job.site.targets) .. " посел."
end

local function short_place(job)
    local name = job.site and job.site.name or settlement_name(job.region)
    return job.kind == "remove" and ("Снести · " .. name) or name
end

local function offers()
    local candidates = {}
    for key in pairs(pending) do candidates[#candidates + 1] = key end
    table.sort(candidates)
    return candidates
end

local function current_offer()
    local keys = offers()
    offer_index = math.min(offer_index, math.max(1, #keys))
    return keys[offer_index], #keys
end

local function allowance(gold, supplies)
    local purse, stock = balances()
    if purse >= gold and stock >= supplies then return end
    return "Не хватает " .. math.max(0, gold - purse) .. " зол. и " .. math.max(0, supplies - stock) .. " ресурсов культа."
end

function render()
    if not panel or not panel:Visible() then return end
    local gold, supplies = balances()
    write("title", "Управление культами")
    write("faction", "Обманщики")
    write("balance", gold .. " золота     ·     " .. supplies .. " ресурсов культа")
    button("close", "×", true)
    for _, key in ipairs(tabs) do button(key, tab_names[key], not busy, not show_preset and key == tab) end
    button("preset", "Пресет построек", not busy, show_preset)
    local active = not show_preset
    for _, id in ipairs({"sort", "header", "heading_place", "heading_effect", "heading_cost", "previous", "next", "all", "page"}) do
        visible(id, active)
    end
    write("sort", scanning and "Читаю доступные работы в культах…" or criteria[tab])
    write("heading_place", "Поселение и постройка")
    write("heading_effect", tab == "gold" and "Прибавка и окупаемость" or tab == "books" and "Прибавка" or "Доступные цели")
    write("heading_cost", "Цена и срок")
    local current = rows[tab]
    local last_page = math.max(1, math.ceil(#current / per_page))
    page = math.min(page, last_page)
    page_jobs = {}
    local all_selected = true
    for i = 1, per_page do
        local job = active and not scanning and current[(page - 1) * per_page + i]
        local selected = job and is_selected(job)
        for _, id in ipairs({"row_bg", "place", "building", "effect", "price", "pick"}) do visible(id .. i, not not job) end
        visible("row_mark" .. i, not not selected)
        if job then
            page_jobs[i] = job
            all_selected = all_selected and selected
            write("place" .. i, job.site.name)
            write("building" .. i, (job.kind == "remove" and "Снести · " or "") .. building_name(job.level)
                .. (job.site.province and ("\n" .. job.site.province) or ""))
            write("effect" .. i, effect(job))
            local cost = job.kind == "remove" and "Снос" or string.format("%d зол. · %d рес.\n%d х.", job.gold, job.supplies, job.turns)
            write("price" .. i, cost)
            button("pick" .. i, selected and "Убрать" or "Выбрать", not busy, selected)
        end
    end
    write("page", page .. " / " .. last_page)
    button("previous", "Назад", page > 1 and not busy)
    button("next", "Далее", page < last_page and not busy)
    button("all", all_selected and #page_jobs > 0 and "Снять на странице" or "Выбрать страницу", #page_jobs > 0 and not busy)
    write("disclosure", active and (tab == "gold" and "Окупаемость приблизительная. Она рассчитана по приросту дохода от одной работы." or "Цены, срок и наличие ресурсов проверяются при отправке работ.") or "Очередь создаётся для нового культа только при наличии всех выбранных построек и ресурсов.")

    visible("preset_heading", show_preset)
    visible("mode_label", show_preset)
    visible("mode", show_preset)
    visible("preset_save", show_preset)
    visible("preset_offer", show_preset)
    visible("preset_next", show_preset)
    visible("preset_apply", show_preset)
    write("preset_heading", "Пресет нового культа")
    local offer, offer_count = current_offer()
    write("preset_offer", offer and string.format("Новый культ %d / %d · %s", offer_index, offer_count, settlement_name(offer))
        or "Нет новых культов для применения пресета.")
    button("preset_next", "Следующий культ", offer_count > 1 and not busy)
    button("preset_apply", "Подготовить работы для нового культа", offer ~= nil and not busy)
    for i = 1, 3 do
        visible("preset_label" .. i, show_preset)
        visible("preset_slot" .. i, show_preset)
        write("preset_label" .. i, ({"Первая постройка", "Вторая постройка", "Третья постройка"})[i])
        button("preset_slot" .. i, building_name(draft.levels[i]), not busy)
    end
    write("mode_label", "При основании")
    button("mode", mode_name[draft.mode], not busy)
    button("preset_save", "Сохранить пресет", not busy)

    local queue = reviewing and reviewing.jobs or selections
    local cost_gold, cost_supplies = management.total(queue)
    local display = #queue > 0 and queue or recent
    local names = {}
    local demolition = false
    local last_queue_page = math.max(1, math.ceil(#display / per_page))
    queue_page = math.min(queue_page, last_queue_page)
    for i, job in ipairs(display) do
        if job.kind == "remove" then demolition = true end
        if i > (queue_page - 1) * per_page and i <= queue_page * per_page then
            names[#names + 1] = short_place(job) .. "\n" .. building_name(job.level)
        end
    end
    local shortage = allowance(cost_gold, cost_supplies)
    write("queue_title", busy and "Работы отправляются" or reviewing and "Подтверждение работ"
        or (#queue == 0 and #recent > 0 and "Последние принятые работы" or "К постановке в очередь"))
    write("queue_items", #names > 0 and table.concat(names, "\n") or (#current == 0 and active and not scanning and "Подходящих работ на вкладке нет." or "Выбери работы слева."))
    write("queue_page", #display > 0 and ("Работ " .. #display .. " · " .. queue_page .. " / " .. last_queue_page) or "")
    button("queue_previous", "←", queue_page > 1)
    button("queue_next", "→", queue_page < last_queue_page)
    write("total", "Всего   " .. cost_gold .. " зол. · " .. cost_supplies .. " рес.")
    write("feedback", feedback ~= "" and feedback or shortage or "")
    button("clear", "Очистить", #queue > 0 and not busy)
    local ready = #queue > 0 and (not reviewing or not shortage) and not busy and not scanning and player_turn()
    button("review", reviewing and (demolition and "Подтвердить работы и снос" or "Поставить в очередь") or "Проверить очередь", ready)
end

function refresh()
    if not panel or not panel:Visible() then return end
    scan_id = scan_id + 1
    local token = scan_id
    scanning = true
    rows = empty
    render()
    local managers = player():foreign_slot_managers()
    local count, index = managers:num_items(), 0
    local jobs, sites = {}, {}
    local function scan()
        if token ~= scan_id then return end
        if not panel:Visible() then scanning = false; return end
        local ok, message = pcall(function()
            for i = index, math.min(index + 2, count - 1) do
                local manager = managers:item_at(i)
                local region = manager:region()
                local prior_count = #jobs
                native.scan_manager(manager, catalog.builds, jobs)
                if #jobs > prior_count then sites[region:name()] = site_of(region, manager) end
            end
        end)
        if not ok then
            scanning = false
            feedback = "Не удалось прочитать культы. Подробности в журнале игры."
            log(message)
            render()
            return
        end
        index = index + 3
        if index < count then cm:real_callback(scan, 25); return end
        rows = management.rank(jobs, sites, catalog.builds)
        scanning = false
        log("scan|cults=" .. count .. "|jobs=" .. #jobs)
        render()
    end
    cm:real_callback(scan, 25)
end

local function save_inbox()
    cm:set_saved_value(inbox_key, pending)
    update_opener()
end

local function prune_inbox()
    local changed = false
    for key in pairs(pending) do
        local region = cm:get_region(key)
        if region:is_null_interface() or region:foreign_slot_manager_for_faction(catalog.faction):is_null_interface() then
            pending[key], changed = nil, true
        end
    end
    if changed then save_inbox() end
end

local function queue_valid(job)
    if not player_turn() then return false end
    if job.kind == "remove" then
        local region = cm:get_region(job.region)
        if region:is_null_interface() then return false end
        local _, nearby = target_counts(region)
        return nearby == 0
    end
    return true
end

local function execute(queue, origin)
    if busy or not player_turn() or #queue == 0 then return false end
    local gold, supplies = management.total(queue)
    local shortage = allowance(gold, supplies)
    if shortage then feedback = shortage; render(); return false end
    busy = true
    local index, completed = 1, 0
    local function finish(reason)
        busy = false
        if completed > 0 then
            recent = {}
            for i = 1, completed do recent[i] = queue[i] end
        end
        reset_selection()
        feedback = completed .. " из " .. #queue .. " работ приняты игрой." .. (reason and ("\n" .. reason) or "")
        if origin and completed > 0 then
            local remaining = {}
            for i = completed + 1, #queue do remaining[#remaining + 1] = queue[i].level end
            pending[origin] = #remaining > 0 and remaining or nil
            save_inbox()
        end
        refresh()
        if not panel or not panel:Visible() then log(feedback) end
        if not reason and drain_presets then cm:real_callback(drain_presets, 200) end
    end
    local function advance()
        local job = queue[index]
        if not job then finish(); return end
        if not queue_valid(job) then finish("Условия изменились. Проверь оставшиеся работы."); return end
        local call_ok, issued, detail = pcall(native.issue, job)
        if not call_ok or not issued then
            log("issue failed|" .. tostring(detail or issued))
            finish("Игра отклонила работу в поселении " .. settlement_name(job.region) .. ".")
            return
        end
        local attempts = 0
        local function verify()
            attempts = attempts + 1
            local checked, queued = pcall(native.queued, job)
            if checked and queued then
                completed, index = completed + 1, index + 1
                log("queued|" .. job.region .. "|" .. job.level .. "|" .. job.kind)
                advance()
            elseif attempts < 8 then
                cm:real_callback(verify, 125)
            else
                if not checked then log(queued) end
                finish("Очередь поселения " .. settlement_name(job.region) .. " не подтвердилась.")
            end
        end
        cm:real_callback(verify, 125)
    end
    render()
    advance()
    return true
end

local function prepare_preset(region)
    local levels = {}
    local offered = type(pending[region]) == "table" and pending[region] or preset.levels
    for _, value in ipairs(offered) do if value ~= "" then levels[#levels + 1] = value end end
    if #levels == 0 then return nil, "В пресете нет построек." end
    local ok, jobs = pcall(native.scan, player(), catalog.builds, region)
    if not ok then log(jobs); return nil, "Не удалось прочитать новый культ." end
    local plan = management.preset(jobs, catalog.builds, region, levels)
    if not plan then return nil, "Не все постройки пресета доступны в этом культе." end
    local gold, supplies = management.total(plan)
    local shortage = allowance(gold, supplies)
    if shortage then return nil, shortage end
    return plan
end

function drain_presets()
    if busy or #selections > 0 or not player_turn() or preset.mode ~= "auto" then return end
    prune_inbox()
    for _, key in ipairs(offers()) do
        local plan = prepare_preset(key)
        if plan then execute(plan, key); return end
    end
end

local function save_preset()
    local groups = {}
    for _, key in ipairs(draft.levels) do
        if key ~= "" then
            local group = catalog.builds[key].group
            if groups[group] then feedback = "Выбери только одну постройку из каждой категории."; return end
            groups[group] = true
        end
    end
    if next(groups) == nil and draft.mode ~= "off" then feedback = "Выбери постройки для пресета."; return end
    preset = {mode=draft.mode, levels={unpack(draft.levels)}}
    cm:set_saved_value(saved_key, preset)
    feedback = "Пресет сохранён."
    if preset.mode == "auto" then cm:real_callback(drain_presets, 200) end
end

local function open_management()
    if not panel then
        panel = core:get_or_create_component("changeling_cult_management", layout_root .. "panel")
        if not panel then log("could not create panel"); return end
    end
    panel:SetVisible(true)
    refresh()
end

local function review_selection()
    local jobs, skipped = {}, {}
    for _, job in ipairs(selections) do
        local current = queue_valid(job)
        local ok, valid, reason = pcall(native.validate, job)
        if current and ok and valid then
            jobs[#jobs + 1] = job
        else
            skipped[#skipped + 1] = settlement_name(job.region)
            log("review skipped|" .. job.region .. "|" .. tostring(reason or valid))
        end
    end
    queue_page = 1
    if #jobs > 0 then reviewing = {jobs=jobs} end
    if #skipped > 0 then feedback = "Условия изменились. Пропущено работ · " .. #skipped .. "\n" .. table.concat(skipped, ", ", 1, math.min(3, #skipped)) end
end

local function click(id)
    if id == "cmgr_open" then
        if panel and panel:Visible() then panel:SetVisible(false) else open_management() end
        return
    end
    if not panel or not panel:Visible() then return end
    local action = id:sub(6)
    if action == "close" then panel:SetVisible(false); return end
    if busy then return end
    feedback = ""
    if tab_names[action] then
        tab, page, show_preset = action, 1, false
    elseif action == "preset" then
        show_preset = not show_preset
    elseif action == "previous" then
        page = math.max(1, page - 1)
    elseif action == "next" then
        page = page + 1
    elseif action == "queue_previous" then
        queue_page = math.max(1, queue_page - 1)
    elseif action == "queue_next" then
        queue_page = queue_page + 1
    elseif action == "all" and not scanning then
        local all_selected = #page_jobs > 0
        for _, job in ipairs(page_jobs) do all_selected = all_selected and is_selected(job) end
        for _, job in ipairs(page_jobs) do choose(job, not all_selected) end
    elseif action == "clear" then
        reset_selection()
        if preset.mode == "auto" then cm:real_callback(drain_presets, 200) end
    elseif action == "mode" then
        for index, mode in ipairs(modes) do
            if mode == draft.mode then draft.mode = modes[index % #modes + 1]; break end
        end
    elseif action == "preset_save" then
        save_preset()
    elseif action == "preset_next" then
        local _, count = current_offer()
        if count > 0 then offer_index = offer_index % count + 1 end
    elseif action == "preset_apply" then
        local offer = current_offer()
        if offer then
            local plan, reason = prepare_preset(offer)
            if plan then
                reset_selection()
                for _, job in ipairs(plan) do choose(job, true) end
                reviewing = {jobs=selections, origin=offer}
            else feedback = reason end
        end
    elseif action == "review" and not scanning and player_turn() then
        if reviewing then execute(reviewing.jobs, reviewing.origin); return end
        if #selections > 0 then review_selection() end
    else
        local row = tonumber(action:match("^pick(%d)$"))
        local job = row and page_jobs[row]
        if job and not scanning then choose(job, not is_selected(job)) end
        local slot = tonumber(action:match("^preset_slot(%d)$"))
        if slot then
            for i, key in ipairs(options) do
                if key == draft.levels[slot] then draft.levels[slot] = options[i % #options + 1]; break end
            end
        end
    end
    render()
end

cm:add_first_tick_callback(function()
    if cm:get_local_faction_name(true) ~= catalog.faction or cm:is_multiplayer() then return end
    local saved = cm:get_saved_value(saved_key)
    if type(saved) == "table" and mode_name[saved.mode] and type(saved.levels) == "table" then
        preset.mode = saved.mode
        for i = 1, 3 do
            local key = saved.levels[i]
            if type(key) == "string" and catalog.builds[key] and catalog.builds[key].tier == 1 then preset.levels[i] = key end
        end
    end
    draft = {mode=preset.mode, levels={unpack(preset.levels)}}
    local stored_inbox = cm:get_saved_value(inbox_key)
    if type(stored_inbox) == "table" then pending = stored_inbox end
    local hud = find_uicomponent(core:get_ui_root(), "hud_campaign") or core:get_ui_root()
    opener = core:get_or_create_component("cmgr_open", layout_root .. "open", hud)
    if not opener then log("could not create launcher button"); return end
    update_opener()
    core:add_listener("changeling_cult_management_click", "ComponentLClickUp", function(ctx)
        return ctx.string:sub(1, 5) == "cmgr_"
    end, function(ctx)
        local ok, error = pcall(click, ctx.string)
        if not ok then log(error) end
    end, true)
    core:add_listener("changeling_cult_management_found", "ForeignSlotManagerCreatedEvent", function(ctx)
        return ctx:requesting_faction():name() == catalog.faction and not ctx:is_allied()
    end, function(ctx)
        if preset.levels[1] == "" and preset.levels[2] == "" and preset.levels[3] == "" then return end
        pending[ctx:region():name()] = true
        save_inbox()
        if preset.mode == "auto" then cm:real_callback(drain_presets, 250) end
    end, true)
    core:add_listener("changeling_cult_management_turn", "FactionTurnStart", function(ctx)
        return ctx:faction():name() == catalog.faction
    end, function()
        reset_selection()
        prune_inbox()
        refresh()
        if preset.mode == "auto" then cm:real_callback(drain_presets, 500) end
    end, true)
    core:add_listener("changeling_cult_management_lost", "ForeignSlotManagerRemovedEvent", function(ctx)
        return ctx:owner():name() == catalog.faction
    end, function()
        cm:real_callback(function()
            prune_inbox()
            if not busy then refresh() end
        end, 150)
    end, true)
    log("ready|test.2")
end)
