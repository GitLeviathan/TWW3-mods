-- Proposed standalone campaign script. Does not acquire, upgrade, or move a sword.
-- Keep the native confederation/shrine/ownership listeners and repair only their
-- hard-coded stage-1 cache reconstruction.
cm:add_first_tick_callback(function()
    local controller = sword_of_khaine
    if not controller or controller._codex_stage_cache_guard then return end
    local native_correct_script_cache = controller.correct_script_cache
    controller.correct_script_cache = function(self, cqi)
        if not cqi then return native_correct_script_cache(self, cqi) end
        local character = cm:get_character_by_cqi(cqi)
        if not character or character:is_null_interface() then
            return native_correct_script_cache(self, cqi)
        end
        local stage
        for i = 1, #self.key_index do
            if character:has_ancillary(self.key_index[i]) then
                stage = i
                break
            end
        end
        if not stage then return native_correct_script_cache(self, cqi) end
        local previous = self.owner
        local countdown = self.growth_time[stage]
        if previous.character_cqi == cqi and previous.lv == stage
            and type(previous.cd) == "number" and previous.cd >= 0 then
            countdown = previous.cd
        end
        self.owner = {
            character_cqi = cqi,
            faction = character:faction():name(),
            lv = stage,
            cd = countdown,
            ready = true
        }
        self:set_sword_button_state()
    end
    controller._codex_stage_cache_guard = true
end)
