local faction_key = "wh3_dlc24_tze_the_deceivers"
local stance_key = "MILITARY_FORCE_ACTIVE_STANCE_TYPE_TUNNELING"
local resource_cost = "wh3_main_tunnel_tze_winds_of_magic"
local teleport_technology = "wh3_dlc24_tech_the_changeling_teleport"
local button_id = "changeling_long_jump_button"
local dialog_id = "changeling_long_jump_dialog"
local button
local armed_lord
local status
local previous_state
local last_x, last_y
local placement_logged = false

local function eligible_lord(cqi)
    local lord = cqi and cm:get_character_by_cqi(cqi)
    if not lord or lord:is_null_interface() or lord:faction():name() ~= faction_key
        or not lord:has_military_force() or lord:action_points_remaining_percent() <= 0
        or lord:is_besieging() or lord:is_blockading() or lord:in_settlement() then
        return nil
    end
    local force = lord:military_force()
    if not force:is_army() or not force:has_general() or force:active_stance() ~= stance_key
        or force:general_character():command_queue_index() ~= cqi then
        return nil
    end
    return lord
end

local function position_button(root, hud)
    local bar = hud and find_uicomponent(hud, "BL_parent")
    local land = bar and find_uicomponent(bar, "land_stance_button_stack")
    local naval = bar and find_uicomponent(bar, "naval_stance_button_stack")
    local stack = land and land:Visible(true) and land
        or naval and naval:Visible(true) and naval
    local shield = stack and find_uicomponent(stack, "button_default")
    local anchor = shield and shield:Visible(true) and shield or stack
    if anchor then
        local x, y = anchor:Position()
        local width, height = anchor:Dimensions()
        if width > 0 and height > 0 then
            last_x = x + width + 22
            last_y = y + math.floor((height - button:Height()) / 2) - 7
        end
    end
    local left, top = root:Position()
    local _, height = root:Dimensions()
    local x = last_x or left + 220
    local y = last_y or top + height - 49
    button:MoveTo(x, y)
    if not placement_logged then
        out("[ChangelingLongJump] icon placement " .. (anchor and "stance" or "fallback") .. " " .. x .. "," .. y)
        placement_logged = true
    end
end

local function refresh()
    local active = cm:is_local_players_turn()
    local selected = active and cm:get_campaign_ui_manager():get_char_selected_cqi()
    local root = core:get_ui_root()
    local hud = find_uicomponent(root, "hud_campaign")
    local visible = active and (not hud or hud:Visible(true))
        and (armed_lord or status or eligible_lord(selected))
    local tooltip = status or (armed_lord and "Выбери поселение. Нажми значок ещё раз для отмены."
        or "Дальний прыжок. Нажми и выбери поселение на карте.")
    local state = visible and tooltip or false
    if state ~= previous_state then
        if visible then
            button:SetState(armed_lord and "selected" or "active")
            button:SetTooltipText(tooltip, "", true)
        end
        button:SetVisible(not not visible)
        previous_state = state
    end
    if visible then position_button(root, hud) end
end

local function feedback(message)
    status = message
    refresh()
    cm:callback(function()
        status = nil
        refresh()
    end, 3)
end

local function jump_is_free()
    return cm:get_faction(faction_key):has_technology(teleport_technology)
end

local function jump(cqi, region_key)
    if not cm:is_local_players_turn() then return end
    local lord = eligible_lord(cqi)
    if not lord then
        feedback("Армия больше не готова к прыжку")
        return
    end
    local force = lord:military_force()
    local free_jump = jump_is_free()
    if not free_jump then
        local resources = force:pooled_resource_manager()
        if resources:is_null_interface() or not resources:can_afford_resource_cost(resource_cost) then
            feedback("Недостаточно Ветров Магии")
            return
        end
    end
    local x, y = cm:find_valid_spawn_location_for_character_from_settlement(faction_key, region_key, false, true, 8)
    if not x or not y or x < 0 or y < 0 or (x == lord:logical_position_x() and y == lord:logical_position_y()) then
        feedback("Нет доступной точки рядом с поселением")
        return
    end

    local lookup = cm:char_lookup_str(cqi)
    if not cm:teleport_military_force_to(force, x, y) then
        feedback("Игра отклонила телепортацию")
        return
    end
    lord = cm:get_character_by_cqi(cqi)
    if lord and not lord:is_null_interface() and lord:has_military_force() then
        if not free_jump then
            cm:pooled_resource_transaction(lord:military_force():pooled_resource_manager(), resource_cost)
        end
        cm:zero_action_points(lookup)
    end
    out("[ChangelingLongJump] lord=" .. cqi .. " destination=" .. region_key .. " x=" .. x .. " y=" .. y)
    feedback("Армия телепортирована")
end

local function confirm(cqi, region_key)
    local name_key = "regions_onscreen_" .. region_key
    local region_name = common.get_localised_string(name_key)
    local destination = "выбранному поселению"
    if region_name and region_name ~= "" and region_name ~= name_key and region_name ~= region_key then
        destination = "поселению «" .. region_name .. "»"
    end
    local prompt = "Телепортировать армию к " .. destination .. "?\nАрмия потратит оставшиеся очки хода."
    if not jump_is_free() then
        prompt = prompt .. "\nПрыжок также расходует Ветра Магии."
    end

    local root = core:get_ui_root()
    local dialog = core:get_or_create_component(dialog_id, "UI/Common UI/dialogue_box", root)
    local body = find_uicomponent(dialog, "DY_text")
    body:SetStateText(prompt)
    dialog:PropagatePriority(99)
    dialog:LockPriority()
    core:add_listener(dialog_id, "ComponentLClickUp", function(ctx)
        if ctx.string ~= "button_tick" and ctx.string ~= "button_cancel" then return false end
        local control = UIComponent(ctx.component)
        return control:Address() == find_uicomponent(dialog, ctx.string):Address()
    end, function(ctx)
        dialog:UnLockPriority()
        dialog:Destroy()
        if ctx.string == "button_tick" then jump(cqi, region_key) end
    end, false)
end

cm:add_first_tick_callback(function()
    if cm:is_multiplayer() or cm:get_local_faction_name(true) ~= faction_key then return end
    button = core:get_or_create_component(button_id, "UI/Templates/changeling_long_jump_button")
    button:PropagatePriority(30)
    button:SetVisible(false)

    core:add_listener(button_id, "ComponentLClickUp", function(ctx)
        return ctx.string == button_id
    end, function()
        status = nil
        if armed_lord then
            armed_lord = nil
        else
            local selected = cm:get_campaign_ui_manager():get_char_selected_cqi()
            if cm:is_local_players_turn() and eligible_lord(selected) then
                armed_lord = selected
            end
        end
        refresh()
    end, true)

    core:add_listener("changeling_long_jump_destination", "SettlementSelected", function()
        return armed_lord ~= nil and cm:is_local_players_turn()
    end, function(ctx)
        local region_key = ctx:garrison_residence():region():name()
        local cqi = armed_lord
        armed_lord = nil
        refresh()
        confirm(cqi, region_key)
    end, true)

    core:add_listener("changeling_long_jump_turn_end", "FactionTurnEnd", function(ctx)
        return ctx:faction():name() == faction_key
    end, function()
        armed_lord = nil
        status = nil
        refresh()
    end, true)

    cm:repeat_callback(refresh, 0.3, "changeling_long_jump_ui")
    refresh()
    out("[ChangelingLongJump] ready")
end)

