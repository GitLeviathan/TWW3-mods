local catalog = dofile("catalog.lua")
local management = dofile("management.lua")
local key = catalog.faction
local income = "wh3_dlc24_tze_the_changeling_income_symbiotic_1"
local entries, callbacks, listeners, save, issued, enqueued = {}, {}, {}, {}, {}, {}
local gold, supplies = 4200, 50

local function list(values)
    return {num_items=function() return #values end, item_at=function(_,i) return values[i+1] end}
end

local function region(name, gdp)
    return {
        name=function() return name end, gdp=function() return gdp end, is_null_interface=function() return false end,
        province_name=function() return "province_" .. name end,
        adjacent_region_list=function() return list({}) end,
        foreign_slot_manager_for_faction=function() return {is_null_interface=function() return false end} end,
    }
end

local locations = {wei=region("wei", 2400), hai=region("hai", 1000), new=region("new", 1000)}
local faction = {
    treasury=function() return gold end,
    foreign_slot_managers=function() return list(entries) end,
    pooled_resource_manager=function() return {resource=function() return {
        is_null_interface=function() return false end, value=function() return supplies end,
    } end} end,
}
local function add_site(name, slot)
    entries[#entries+1] = {
        region=function() return locations[name] end,
        slots=function() return list({{has_building=function() return false end}}) end,
        job={region=name, slot=slot, kind="build", level=income, gold=1000, supplies=10, turns=2},
    }
end
add_site("wei", 5)
add_site("hai", 9)

local function button()
    return {
        SetState=function(self,state) self.state=state end,
        SetStateText=function(self,text) self.text=text end,
        SetVisible=function(self,value) self.visible=value end,
        Visible=function(self) return self.visible end,
        SetInteractive=function(self,value) self.enabled=value end,
    }
end
local buttons = setmetatable({}, {__index=function(self,id) local v=button(); rawset(self,id,v); return v end})
local open, panel = button(), button()
local env = setmetatable({catalog=catalog, management=management}, {__index=_G})
env.out = function() end
env.common = {get_localised_string=function(name) return name end}
env.find_uicomponent = function(_,id) return buttons[id] end
env.native = {
    scan_manager=function(manager,_,jobs)
        if not enqueued[manager.job.slot] then jobs[#jobs+1] = manager.job end
    end,
    scan=function(_,_,region_key)
        local rows = {}
        for _, obj in ipairs(entries) do
            if obj.job.region==region_key then env.native.scan_manager(obj,nil,rows) end
        end
        return rows
    end,
    validate=function(job) return not enqueued[job.slot], "slot_changed" end,
    issue=function(job) issued[#issued+1]=job; return true end,
    queued=function(job) return enqueued[job.slot] == true end,
}
env.core = {
    get_ui_root=function() return {} end,
    get_or_create_component=function(_,id) if id=="cmgr_open" then return open end; return panel end,
    add_listener=function(_,_,event,filter,invoke) listeners[event]={filter,invoke} end,
}
env.cm = {
    add_first_tick_callback=function(_,fn) fn() end,
    get_local_faction_name=function() return key end,
    is_multiplayer=function() return false end,
    is_local_players_turn=function() return true end,
    get_faction=function() return faction end,
    get_region=function(_,name) return locations[name] end,
    real_callback=function(_,fn) callbacks[#callbacks+1]=fn end,
    set_saved_value=function(_,name,value) save[name]=value end,
    get_saved_value=function(_,name) return save[name] end,
}
save.changeling_cult_management_preset = { mode="offer", levels={income,"",""} }
setfenv(assert(loadfile("campaign.lua")),env)()
local function event(name,ctx)
    local listener = listeners[name]
    if listener[1](ctx) then listener[2](ctx) end
end
local function click(id) event("ComponentLClickUp", {string="cmgr_"..id}) end
local function step() assert(table.remove(callbacks,1))() end
local function flush() while #callbacks>0 do step() end end

click("open")
assert(panel:Visible())
flush()
assert(buttons.cmgr_place1.text=="wei" and buttons.cmgr_place2.text=="hai")
click("all")
click("review")
assert(#issued==0 and buttons.cmgr_review.text=="Поставить в очередь")
click("review")
assert(#issued==1 and issued[1].region=="wei")
step()
assert(#issued==1, "Second job was sent before the first had entered the native queue")
enqueued[5]=true
step()
assert(#issued==2 and issued[2].region=="hai")
enqueued[9]=true
flush()
assert(buttons.cmgr_feedback.text:find("2 из 2",1,true))

add_site("new",12)
event("ForeignSlotManagerCreatedEvent", {
    requesting_faction=function() return {name=function() return key end} end,
    is_allied=function() return false end, region=function() return locations.new end,
})
assert(open.text:find("1",1,true) and #issued==2)
click("preset")
click("preset_apply")
assert(#issued==2 and buttons.cmgr_review.text=="Поставить в очередь")
supplies=0
click("review")
assert(#issued==2 and buttons.cmgr_feedback.text:find("Не хватает",1,true))
supplies=50
click("review")
assert(#issued==3 and issued[3].region=="new")
enqueued[12]=true
flush()
assert(open.text=="Управление культами")
print("Cult management campaign: opening, ranked rows, native queue sequencing, offer, insufficient resources and completion passed")
