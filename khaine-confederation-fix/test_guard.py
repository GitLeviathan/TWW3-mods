from pathlib import Path
import sys
import os
if os.environ.get('TWW3_LUPA_PATH'):sys.path.insert(0,os.environ['TWW3_LUPA_PATH'])
from lupa.lua51 import LuaRuntime
native=(Path(__file__).parent/'.build-cache/native.lua').read_text(encoding='utf-8-sig')
guard=Path(__file__).with_name('guard.lua').read_text(encoding='utf8')
prelude=r'''
listeners, first_ticks, changes = {}, {}, {}
local function list(items) return {num_items=function()return #items end,item_at=function(_,i)return items[i+1]end} end
factions={}
function faction(key)
    if not factions[key] then factions[key]={name=function()return key end,is_human=function()return true end,command_queue_index=function()return 13 end} end
    return factions[key]
end
character_faction='deceivers'; shrine_faction='high_elves'; stage=2; actual_cqi=21
character={command_queue_index=function()return actual_cqi end,faction=function()return faction(character_faction)end,is_null_interface=function()return false end,
has_ancillary=function(_,key)return key=='wh2_dlc10_anc_weapon_the_widowmaker_'..stage end}
local world={characters_owning_ancillary=function(_,key)return list(character:has_ancillary(key) and {character} or {})end}
local region={is_abandoned=function()return false end,owning_faction=function()return faction(shrine_faction)end,
slot_list=function()return list({{has_building=function()return true end,building=function()return {name=function()return 'wh2_main_special_shrine_of_khaine_hef_1'end}end}})end}
cm={add_saving_game_callback=function()end,add_loading_game_callback=function()end,
add_first_tick_callback=function(_,cb)first_ticks[#first_ticks+1]=cb end,
get_character_by_cqi=function(_,cqi)assert(cqi==actual_cqi);return character end,
model=function()return {world=function()return world end,character_for_command_queue_index=function(_,cqi)assert(cqi==actual_cqi);return character end}end,
get_region=function()return region end,get_faction=function(_,key)return faction(key)end,
force_remove_ancillary_from_faction=function(_,_,key)changes[#changes+1]='remove:'..key end,
force_add_ancillary=function(_,_,key)changes[#changes+1]='add:'..key end,
trigger_dilemma_with_targets=function(_,_,key)changes[#changes+1]='dilemma:'..key end}
core={add_listener=function(_,name,event,condition,callback)listeners[name]={condition=condition,callback=callback,event=event}end}
out=function()end
function emit(name,ctx)
    local l=assert(listeners[name]);if l.condition==true or l.condition(ctx) then l.callback(ctx)end
end
'''
def runtime(patched):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(prelude);lua.execute(native)
    lua.execute('sword_of_khaine.set_sword_button_state=function()end; sword_of_khaine:add_listeners()')
    if patched:
        lua.execute(guard);lua.execute('for _,cb in ipairs(first_ticks)do cb()end')
    return lua
def case(label,body,patched=True):
    lua=runtime(patched);lua.execute(body);print('PASS',label)
base="sword_of_khaine.owner={character_cqi=21,faction='deceivers',lv=2,cd=7,ready=true};"
case('native listener reproduces downgrade on unrelated confederation',base+r'''
emit('sword_of_khaine_FactionJoinsConfederation')
assert(sword_of_khaine.owner.lv==1 and sword_of_khaine.owner.cd==15)
emit('sword_of_khaine_CharacterAncillaryGained',{character=function()return character end})
assert(changes[2]=='add:wh2_dlc10_anc_weapon_the_widowmaker_1')
''',False)
case('same native listener preserves real stage and timer; no ancillary replacement',base+r'''
emit('sword_of_khaine_FactionJoinsConfederation')
assert(sword_of_khaine.owner.faction=='deceivers' and sword_of_khaine.owner.lv==2 and sword_of_khaine.owner.cd==7)
emit('sword_of_khaine_CharacterAncillaryGained',{character=function()return character end})
assert(#changes==0)
''')
case('real wielder faction transfer preserves stage and timer',base+r'''
character_faction='new_faction'
emit('sword_of_khaine_FactionJoinsConfederation')
assert(sword_of_khaine.owner.faction=='new_faction' and sword_of_khaine.owner.lv==2 and sword_of_khaine.owner.cd==7)
''')
case('unwielded shrine faction transfer retains native behavior',r'''
stage=0;sword_of_khaine.owner={faction='old_shrine',lv=0,cd=0,ready=false}
emit('sword_of_khaine_FactionJoinsConfederation')
assert(sword_of_khaine.owner.faction==shrine_faction and sword_of_khaine.owner.ready and sword_of_khaine.owner.lv==0)
''')
case('new wielder retains native acquisition path',base+r'''
actual_cqi=99
local acquired
sword_of_khaine.set_sword_owner=function(_,cqi)acquired=cqi end
emit('sword_of_khaine_FactionJoinsConfederation')
assert(acquired==99)
''')
case('lost wielder retains native return-to-shrine path',base+r'''
stage=0
local returned=false
sword_of_khaine.return_sword_to_shrine=function()returned=true end
emit('sword_of_khaine_FactionJoinsConfederation')
assert(returned)
''')
case('already completed stage 3 and zero timer remain unchanged',r'''
stage=3;sword_of_khaine.owner={character_cqi=21,faction='deceivers',lv=3,cd=0,ready=true}
emit('sword_of_khaine_FactionJoinsConfederation')
assert(sword_of_khaine.owner.lv==3 and sword_of_khaine.owner.cd==0)
''')
case('mismatched cache derives actual stage without free upgrade',r'''
sword_of_khaine.owner={character_cqi=21,faction='deceivers',lv=1,cd=14,ready=true}
emit('sword_of_khaine_FactionJoinsConfederation')
assert(sword_of_khaine.owner.lv==2 and sword_of_khaine.owner.cd==10)
''')
case('stage 2 countdown reaches normal dilemma, never free stage 3',base+r'''
for i=1,7 do emit('sword_of_khaine_WorldStartRound')end
assert(sword_of_khaine.owner.lv==2 and sword_of_khaine.owner.cd==0 and #changes==0)
emit('sword_of_khaine_WorldStartRound')
assert(changes[1]=='dilemma:wh2_dlc10_sword_of_khaine_lv2' and sword_of_khaine.owner.lv==2)
''')
