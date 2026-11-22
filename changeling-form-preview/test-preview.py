from pathlib import Path
import sys
import os
if os.environ.get('TWW3_LUPA_PATH'):
    sys.path.insert(0,os.environ['TWW3_LUPA_PATH'])
from lupa import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
selected='wh2_main_hef_cha_tyrion_0'; shown=true; calls=0; destroyed=0; logs={}
page={Visible=function() return shown end, Address=function() return 'page1' end}
holder={DestroyChildren=function() destroyed=destroyed+1; last_path=nil end,
 Position=function() return 1800,400 end,
 Dimensions=function() return 470,510 end,Id=function() return 'mask_asset_holder' end,
 Visible=function() return true end,ChildCount=function() return last_path and 1 or 0 end,
 CreateComponent=function(self,name,path) calls=calls+1; last_path=path; if fail_create then return nil end; model_x,model_y=0,0; return 'address' end}
viewport={Position=function() return model_x,model_y end,Dimensions=function() return 470,510 end,
 Visible=function() return true end,Id=function() return 'mask_model_renderer' end,
 ChildCount=function() return 0 end,CurrentState=function() return 'mask_model_view' end}
created_ui={Position=function() return model_x,model_y end,Dimensions=function() return 470,510 end,
 Visible=function() return true end,Id=function() return 'mask_current_model' end,
 ChildCount=function() return (missing_viewport or direct_viewport) and 0 or 1 end,
 CurrentState=function() return direct_viewport and 'mask_model_view' or 'default' end,
 MoveTo=function(self,x,y) model_x,model_y=x,y end}
function UIComponent(address) assert(address=='address');return created_ui end
label={SetText=function(self,text) caption=text end}
notice={SetText=function(self,text) message=text end,SetVisible=function(self,v) notice_visible=v end}
name={GetContextObjectId=function(self,t) assert(t=='CcoMainUnitRecord');return 'context' end}
common={get_context_value=function(t,id,fn) assert(t=='CcoMainUnitRecord' and fn=='Key');return selected end}
core={get_ui_root=function() return {} end,add_listener=function(...) end}
cm={add_first_tick_callback=function(self,fn) fn() end,repeat_real_callback=function(self,fn,ms) assert(ms==200);poll=fn end,real_callback=function(self,fn,ms) assert(ms==50);fn() end}
function out(s) table.insert(logs,s) end
function find_uicomponent(parent,id,child)
 if id=='mask_model_page' then return page elseif id=='button_mask_view' then return label
 elseif id=='mask_model_name' then return name elseif id=='mask_asset_holder' then return holder
 elseif id=='mask_model_renderer' then return not (missing_viewport or direct_viewport) and viewport or nil
 elseif id=='mask_model_unavailable' then return notice end
end
''')
lua.execute(Path(__file__).with_name('preview.generated.lua').read_text(encoding='utf8'))
lua.execute('''
poll(); assert(calls==1 and last_path:find('tyrion') and notice_visible==false)
assert(model_x==1800 and model_y==400, 'Created scene was not aligned to its visible holder')
poll(); assert(calls==1) -- No repeated allocation for unchanged selection.
selected='wh_dlc05_wef_cha_orion_0'; poll(); assert(calls==2 and last_path:find('orion'))
selected='wh2_main_lzd_cha_lord_mazdamundi_0'; poll(); assert(calls==3 and last_path:find('mazdamundi'))
selected='unknown_form'; poll(); assert(calls==3 and last_path==nil and notice_visible==true)
selected=nil; poll(); assert(last_path==nil and notice_visible==true)
selected='wh2_main_hef_cha_tyrion_0'; fail_create=true; poll(); assert(notice_visible==true)
shown=false; poll(); fail_create=false; shown=true; poll(); assert(notice_visible==false)
missing_viewport=true; selected='wh_dlc05_wef_cha_orion_0'; poll(); assert(notice_visible==true)
assert(logs[#logs]:find('Created layout has no model viewport',1,true))
missing_viewport=false; selected='wh2_main_hef_cha_tyrion_0'; poll(); assert(notice_visible==false)
direct_viewport=true; selected='wh3_dlc26_grn_cha_snagla_grobspit'; poll()
assert(last_path:find('snagla') and not notice_visible, 'The engine returned the renderer directly')
assert(caption=='Показать характеристики')
''')
print('PASS: real Lua execution: selection changes, unchanged selection, absent campaign characters, unsupported/missing keys, creation failure and reopening')
