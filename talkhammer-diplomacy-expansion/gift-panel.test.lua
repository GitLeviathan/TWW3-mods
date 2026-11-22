local dir = (... or ".") .. "/"
local panel = assert(loadfile(dir .. "gift-panel.lua"))()
local components, turn, submitted = {}, 81, nil
local function component(id)
    if not components[id] then
        components[id] = {
            visible = false, text = "",
            SetVisible = function(self, value) self.visible = value end,
            SetStateText = function(self, value) self.text = value end,
            GetStateText = function(self) return self.text end,
            Visible = function(self) return self.visible end,
        }
    end
    return components[id]
end
local listener
local ui = { panel = {}, frame = component("frame"), mode = "talk", deep_find = function(_, id) return component(id) end,
    field = component("field"), speak_btn = component("speak"),
    init = function() return true end, hide = function() component("frame").visible = false end }
ui.frame.visible = true
ui.field.text, ui.speak_btn.text = "Черновик реплики", "Сказать"
local ruler = { counterpart = "sisters", tick = function() end,
    gift_choices = function(_key, region)
        if region then return {{key = "kislev", label = "Ледяной двор"}, {key = "player", label = "Обманщики"}} end
        local cities = {{key = "fort", label = "Форт Оберштир"}}
        for i = 2, 10 do cities[i] = {key = "city_" .. i, label = "City " .. i} end
        return cities
    end,
    offer_settlement_gift = function(key, region, recipient) submitted = {key, region, recipient} end,
}
local masked = false
local native_find = string.find
ruler.expansion_mask_active = function() return masked end
local picker = panel.install({ ui = ui, ruler = ruler, cm = { turn_number = function() return turn end },
    state = { data = {} }, language = function() return "ru" end, fold = string.lower,
    index_of = function(text, query) return native_find(text, query, 1, true) end,
    core = { add_listener = function(_, _, _, predicate, callback)
        listener = function(id)
            local context = { string = id }
            if predicate(context) then callback(context) end
        end
    end } })
assert(ui.init())
local prefix = "th_gift_"
local function click(id) listener(prefix .. id); ruler.tick() end
local function part(id) return component(prefix .. id) end
assert(part("open").visible and not part("picker").visible)
click("open")
assert(part("picker").visible and part("choice_1").text == "Форт Оберштир")
assert(part("next").text == "Следующая")
click("next")
assert(part("choice_1").text == "City 9")
assert(ui.field.text == "" and ui.speak_btn.text == "Найти")
ui.field.text = "City 3"
assert(picker.consume_speak(), "Enter/Speak must stay in the picker")
assert(part("choice_1").text == "City 3" and not part("choice_2").visible)
click("back")
assert(not part("picker").visible and not submitted)
assert(ui.field.text == "Черновик реплики" and ui.speak_btn.text == "Сказать")
assert(not picker.consume_speak(), "ordinary chat must retain its submit path")
click("open")
click("choice_1")
assert(part("choice_1").text == "Ледяной двор")
ui.field.text = "двор"
string.find = function() error("The campaign's native find must stay out of settlement filtering") end
ruler.tick()
string.find = native_find
assert(part("choice_1").text == "Ледяной двор" and not part("choice_2").visible)
click("choice_1")
assert(part("send").visible and not submitted)
assert(part("header").text:find("Получатель: Ледяной двор", 1, true))
click("send")
assert(submitted[1] == "sisters" and submitted[2] == "fort" and submitted[3] == "kislev")
assert(not part("picker").visible)
submitted = nil
click("open")
click("choice_1")
click("choice_1")
turn = turn + 1
click("send")
assert(not submitted and not part("picker").visible)
click("open")
ui.field.text = "Гронд"
listener("th_mask_toggle")
assert(not part("picker").visible and not picker.consume_speak(), "Switching masks must release the search field before redrawing chat")
assert(ui.field.text == "Черновик реплики" and ui.speak_btn.text == "Сказать")
masked = true
ruler.tick()
assert(not part("open").visible)
print("Gift picker: paging, search, review, submit, stale turn, and mask switching passed")
