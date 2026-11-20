"""Execute the original mod's complete turn-start pipeline with the one-shot patch."""
from pathlib import Path
import os,sys
if os.environ.get('TWW3_LUPA_PATH'):sys.path.insert(0,os.environ['TWW3_LUPA_PATH'])
from lupa.lua51 import LuaRuntime
source=(Path(__file__).parent/'.build-cache/candidate.lua').read_text(encoding='utf8')
TOKEN='950569697f27b68f5548134997988f140b848baa695d1a5a4f22baadd38df628'
PENDING='codex_turn75_rep_miao_pending'
DONE='codex_turn75_rep_miao_done'
prelude='''
listeners={};events={};turn=75;local_player='wh3_dlc24_tze_the_deceivers'
io={open=function()return {write=function()end,close=function()end}end}
local empty={num_items=function()return 0 end}
local function faction(name) return {name=function()return name end,is_human=function()return true end,
 is_vassal_of=function()return false end,character_list=function()return empty end}end
cm={get_saved_value=function(_,key)return saved[key]end,set_saved_value=function(_,key,v)saved[key]=v end,
 get_local_faction_name=function()return local_player end,get_faction=function(_,name)return faction(name)end,
 model=function()return {turn_number=function()return turn end}end,
 add_first_tick_callback=function(_,fn)fn()end,
 trigger_dilemma=function(_,player,key)table.insert(events,{player=player,key=key})end}
core={add_listener=function(_,name,event,condition,callback)listeners[name]={condition=condition,callback=callback}end}
function emit(name)
 local listener=assert(listeners.PlayerTurnStartListener)
 local ctx={faction=function()return faction(name)end}
 if listener.condition(ctx)then listener.callback(ctx)end
end
'''
def runtime(values=None):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().saved=lua.table_from(values if values is not None else {PENDING:TOKEN,'rep_defeat_count':2,'miao_defeat_count':2})
    lua.execute(prelude);lua.execute(source)
    return lua

lua=runtime()
lua.execute("assert(#events==0);emit(local_player);assert(#events==0 and saved.rep_defeat_count==2)")
lua.execute("turn=76;emit('another_human');assert(#events==0)")
lua.execute("emit(local_player);assert(#events==2 and saved.rep_defeat_count==3 and saved.miao_defeat_count==3)")
events={row['key'] for _,row in lua.globals().events.items()}
assert events=={'rep_defeat_3','miao_defeat_3'}
assert lua.globals().saved[PENDING] is False and lua.globals().saved[DONE] is True
lua.execute("emit(local_player);assert(#events==2);turn=77;emit(local_player);assert(#events==2)")
saved=dict(lua.globals().saved.items())
reloaded=runtime(saved)
reloaded.execute("turn=76;emit(local_player);assert(#events==0)")
for label,values in [
    ('unmarked',{'rep_defeat_count':2,'miao_defeat_count':2}),
    ('wrong token',{PENDING:'another_campaign','rep_defeat_count':2,'miao_defeat_count':2}),
    ('already consumed',{PENDING:TOKEN,DONE:True,'rep_defeat_count':2,'miao_defeat_count':2}),
    ('counter advanced',{PENDING:TOKEN,'rep_defeat_count':3,'miao_defeat_count':2}),
]:
    trial=runtime(values);trial.execute("turn=76;emit(local_player);assert(#events==0)")
    print('PASS',label)
for turn in [75,77]:
    trial=runtime();trial.globals().turn=turn;trial.execute('emit(local_player);assert(#events==0)')
trial=runtime();trial.execute("turn=76;local_player='wh_main_emp_empire';emit(local_player);assert(#events==0)")
print('PASS: native rep/miao defeat_3 only on marked Deceivers turn76; counters2->3; no load trigger, foreign-faction trigger, replay or reload repeat')
