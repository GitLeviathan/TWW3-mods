            -- One-shot repair scoped to the explicitly marked turn-75 campaign save.
            -- Seed the original mod's pending-AI-defeat branch; its own loop below
            -- increments counters and queues its original stage-three dilemmas.
            local repair_key = "codex_turn75_rep_miao_pending"
            local repair_done_key = "codex_turn75_rep_miao_done"
            local repair_token = "__SAVE_TOKEN__"
            if player_faction_key == "wh3_dlc24_tze_the_deceivers"
                and context:faction():name() == player_faction_key
                and cm:model():turn_number() == 76
                and cm:get_saved_value(repair_key) == repair_token
                and not cm:get_saved_value(repair_done_key)
            then
                if cm:get_saved_value("rep_defeat_count") == 2
                    and cm:get_saved_value("miao_defeat_count") == 2
                then
                    ai_defeat_flags["wh2_dlc14_brt_repanse"] = true
                    ai_defeat_flags["wh3_main_cth_miao_ying"] = true
                    cm:set_saved_value(repair_key, false)
                    cm:set_saved_value(repair_done_key, true)
                    write_to_debug_log("Turn-75 repair: queued original Repanse and Miao stage-three defeat dilemmas on Deceivers turn 76")
                else
                    write_to_debug_log("Turn-75 repair skipped: target defeat counts changed; avoiding replay or counter rollback")
                end
            end
