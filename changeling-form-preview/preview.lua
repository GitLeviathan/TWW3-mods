-- View-only: load the selected unit's static battle asset, never a campaign character.
local models = __MODEL_MAP__
local current_key, current_page
local function log(text) if out then out('MASK_PREVIEW|' .. text) end end
local function describe(label, component)
    local x,y=component:Position()
    local width,height=component:Dimensions()
    log(label .. '|id=' .. component:Id() .. '|position=' .. tostring(x) .. ',' .. tostring(y)
        .. '|size=' .. tostring(width) .. ',' .. tostring(height)
        .. '|visible=' .. tostring(component:Visible()) .. '|children=' .. tostring(component:ChildCount()))
end
local function update()
    local root = core:get_ui_root()
    local page = find_uicomponent(root, 'mask_model_page')
    if not page or not page:Visible() then current_key, current_page = nil, nil; return end
    local label = find_uicomponent(root, 'button_mask_view', 'button_txt')
    if label then label:SetText('Показать характеристики') end
    local name = find_uicomponent(page, 'mask_model_name')
    local holder = find_uicomponent(page, 'mask_asset_holder')
    local notice = find_uicomponent(page, 'mask_model_unavailable')
    if not name or not holder then return end
    local context = name:GetContextObjectId('CcoMainUnitRecord')
    local key = context and common.get_context_value('CcoMainUnitRecord', context, 'Key')
    if not key or key == '' then
        if current_key ~= 'no-key' then
            holder:DestroyChildren()
            current_key, current_page = 'no-key', nil
            if notice then notice:SetText('Не удалось определить выделенную форму'); notice:SetVisible(true) end
            log('selection context missing')
        end
        return
    end
    local address = tostring(page:Address())
    if key == current_key and address == current_page then return end
    -- Destroy the previous model before attempting another, so a failed lookup cannot
    -- display a stale model or the equipment window's placeholder captain.
    holder:DestroyChildren()
    current_key, current_page = key, address
    local layout = models[key]
    if not layout then
        if notice then notice:SetText('Модель этой формы пока не найдена'); notice:SetVisible(true) end
        log('unsupported|' .. tostring(key))
        return
    end
    local ok, created = pcall(function()
        local address = holder:CreateComponent('mask_current_model', layout)
        assert(address, 'CreateComponent returned no address')
        local scene = UIComponent(address)
        local viewport = find_uicomponent(scene, 'mask_model_renderer')
        describe('holder',holder)
        describe('scene-before',scene)
        assert(viewport, 'Created layout has no mask_model_renderer child')
        describe('viewport-before',viewport)
        -- MoveTo uses screen coordinates. A dynamically-created root is not
        -- guaranteed to start at its parent's current position.
        scene:MoveTo(holder:Position())
        describe('scene-after',scene)
        describe('viewport-after',viewport)
        return address
    end)
    if notice then
        notice:SetVisible(not (ok and created))
        if not ok or not created then notice:SetText('Не удалось загрузить модель формы') end
    end
    log((ok and created and 'loaded|' or 'failed|') .. tostring(key) .. '|' .. tostring(layout))
    if not ok then log('create-error|' .. tostring(created)) end
end
cm:add_first_tick_callback(function()
    log('direct battle asset loader v4 bounds diagnostics')
    cm:repeat_real_callback(function()
        local ok, err = pcall(update)
        if not ok then
            local text = tostring(err)
            if current_key ~= 'error:' .. text then log('error|' .. text); current_key = 'error:' .. text end
        end
    end, 200, 'tww3_mask_direct_asset_preview')
    core:add_listener('tww3_mask_preview_caption', 'ComponentLClickUp',
        function(context) return context.string == 'button_mask_view' end,
        function()
            cm:real_callback(function()
                local root = core:get_ui_root()
                local page = find_uicomponent(root, 'mask_model_page')
                local label = find_uicomponent(root, 'button_mask_view', 'button_txt')
                if page and label then label:SetText(page:Visible() and 'Показать характеристики' or 'Показать 3D-модель') end
                update()
            end, 50)
        end, true)
end)
