-- Undamaged building effects from the installed campaign DB. Spread is in percentage points.
return {
    faction = "wh3_dlc24_tze_the_deceivers",
    slot_set = "wh3_dlc24_slot_set_tze_changeling",
    slot_template = "wh3_dlc24_tze_cult_changeling",
    resource = "wh3_dlc24_tze_cult_supplies",
    grimoire = "wh3_main_tze_grimoires",
    category_names = {
        gold = "Доход",
        books = "Гримуары",
        spread = "Распространение",
    },
    builds = {
        ["wh3_dlc24_tze_the_changeling_income_symbiotic_1"] = {group = "gold", tier = 1, branch = "symbiotic", share = 0.50, host_bonus = 0.10},
        ["wh3_dlc24_tze_the_changeling_income_symbiotic_2"] = {group = "gold", tier = 2, branch = "symbiotic", share = 0.75, host_bonus = 0.25},
        ["wh3_dlc24_tze_the_changeling_income_symbiotic_3"] = {group = "gold", tier = 3, branch = "symbiotic", share = 1.00, host_bonus = 0.50},
        ["wh3_dlc24_tze_the_changeling_income_parasitic_1"] = {group = "gold", tier = 1, branch = "parasitic", flat_gold = 150, host_bonus = -0.10},
        ["wh3_dlc24_tze_the_changeling_income_parasitic_2"] = {group = "gold", tier = 2, branch = "parasitic", flat_gold = 300, host_bonus = -0.30},
        ["wh3_dlc24_tze_the_changeling_income_parasitic_3"] = {group = "gold", tier = 3, branch = "parasitic", flat_gold = 450, host_bonus = -0.50},

        ["wh3_dlc24_tze_the_changeling_growth_symbiotic_1"] = {group = "books", tier = 1, branch = "symbiotic", books = 8},
        ["wh3_dlc24_tze_the_changeling_growth_symbiotic_2"] = {group = "books", tier = 2, branch = "symbiotic", books = 12},
        ["wh3_dlc24_tze_the_changeling_growth_symbiotic_3"] = {group = "books", tier = 3, branch = "symbiotic", books = 16},
        ["wh3_dlc24_tze_the_changeling_growth_parasitic_1"] = {group = "books", tier = 1, branch = "parasitic", books = 4},
        ["wh3_dlc24_tze_the_changeling_growth_parasitic_2"] = {group = "books", tier = 2, branch = "parasitic", books = 8},
        ["wh3_dlc24_tze_the_changeling_growth_parasitic_3"] = {group = "books", tier = 3, branch = "parasitic", books = 12},

        ["wh3_dlc24_tze_the_changeling_expansion_symbiotic_1"] = {group = "spread", tier = 1, branch = "symbiotic", spread = 2},
        ["wh3_dlc24_tze_the_changeling_expansion_symbiotic_2"] = {group = "spread", tier = 2, branch = "symbiotic", spread = 4},
        ["wh3_dlc24_tze_the_changeling_expansion_symbiotic_3"] = {group = "spread", tier = 3, branch = "symbiotic", spread = 6},
        ["wh3_dlc24_tze_the_changeling_expansion_parasitic_1"] = {group = "spread", tier = 1, branch = "parasitic", spread = 4},
        ["wh3_dlc24_tze_the_changeling_expansion_parasitic_2"] = {group = "spread", tier = 2, branch = "parasitic", spread = 8},
        ["wh3_dlc24_tze_the_changeling_expansion_parasitic_3"] = {group = "spread", tier = 3, branch = "parasitic", spread = 12},
    },
}
