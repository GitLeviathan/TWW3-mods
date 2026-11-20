"""Execute the packaged Lua score and submission policy against campaign-interface doubles."""
import importlib.util
import json
import sys
import os
from pathlib import Path
ROOT = Path(__file__).resolve().parent
if os.environ.get('TWW3_LUPA_PATH'):
    sys.path.insert(0, os.environ['TWW3_LUPA_PATH'])
from lupa import LuaRuntime
spec = importlib.util.spec_from_file_location('boundaries', ROOT / 'regard-boundaries.test.py')
boundaries = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boundaries)


def run(pack_path, config_path=None):
    entries = boundaries.unpack(pack_path)
    stock = boundaries.unpack('D:/Steam/steamapps/workshop/content/1142710/3808547073/talkhammer.pack')
    config_file = Path(config_path) if config_path else Path(__file__).with_name('talkhammer-slaanesh-rulers.json')
    config = json.loads(config_file.read_text(encoding='utf-8'))
    assert config['version'] == 2 and config['regard']['perStage'] == 50
    assert config['vassalDialogue']['requiredStage'] == 3
    assert config['vassalDialogue']['requirePlayerAsOverlord'] is True
    assert len(config['rulers']) == 10
    assert all('voice' not in row for row in config['stages'])
    assert all('voice' not in row for row in config['rulers'].values())
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('TALKHAMMER_U8 = {sub=string.sub, blen=string.len, clean=function(s) return s end, fold_typography=function(s) return s end}')
    lua.globals().config_text = json.dumps(config, ensure_ascii=False)
    json_module = lua.execute(stock[r'script\talkhammer\lib\json.lua'][0].decode())
    lua.globals().json_module = json_module
    lua.execute('''
        level=0; subtype=""; overlord="player"; human=true; attitude=0
        config_missing=false; trait_error=false; vassal_error=false
        -- main.lua's loader is lexical; disposition has no global loader in game.
        load_module=nil
        local original_open=io.open
        io.open=function(path, mode)
            if path=="talkhammer/talkhammer-slaanesh-rulers.json" then
                if config_missing then return nil end
                return {read=function() return config_text end,close=function() end}
            end
            return original_open(path,mode)
        end
        local leader={is_null_interface=function() return false end,
            character_subtype_key=function() return subtype end,
            trait_level=function() if trait_error then error("missing trait") end return level end}
        cm={get_local_faction_name=function() return "player" end,
            get_faction=function(_,key)
                return {key=key, is_null_interface=function() return false end,
                    is_human=function() return key=="player" and human end,
                    faction_leader=function() return leader end,
                    is_vassal_of=function(_,other)
                        if vassal_error then error("relationship unavailable") end
                        return other.key==overlord
                    end}
            end}
    ''')
    disp = lua.execute(entries[r'script\talkhammer\lib\disposition.lua'][0].decode())
    lua.globals().disposition = disp
    evaluate = lua.eval('''function(them, extra)
        disposition.init({world={get=function() return {} end,
            attitude=function() return attitude end}})
        local snap={treasury=1000,regions=1,wars={}}
        return disposition.score(them,"player",snap,snap,{v1=true,earned=extra or 0})
    end''')
    cases = 0
    for faction, ruler in config['rulers'].items():
        lua.globals().subtype = ruler['leaderSubtype']
        for stage in range(4):
            lua.globals().level = stage
            result, reasons, parts = evaluate(faction, 0)
            assert result == 50*stage, f'{faction} stage {stage}: expected {50*stage}, got {result}'
            cases += 1
    faction = 'wh2_main_hef_avelorn'
    lua.globals().subtype = config['rulers'][faction]['leaderSubtype']
    lua.globals().level = 3
    # Real post-modifier addition: culture-independent, with final total bounds retained.
    lua.globals().attitude = -600
    assert evaluate(faction, -76)[0] == 34  # original -116 + 150
    lua.globals().attitude = 1000
    assert evaluate(faction, 0)[0] == 250
    lua.globals().attitude = 0
    for name, value in [('human',False),('subtype','new_leader'),('trait_error',True),('config_missing',True)]:
        before = lua.globals()[name]
        lua.globals()[name] = value
        assert evaluate(faction, 0)[0] == 0, name
        lua.globals()[name] = before
        cases += 1
    assert evaluate('unlisted',0)[0] == 0
    # A hostile culture attenuates ordinary standing before the corruption bonus.
    lua.globals().attitude = 200
    culture_case = lua.eval('''function(stage_level)
        level=stage_level
        disposition.init({world={get=function() return {subculture="test"} end,
            attitude=function() return attitude end},
            lore={lord_rel=function() return nil end,
                culture_rel=function() return -50,"test ancient hatred" end,
                values_terms=function() return {} end,
                company_terms=function() return {} end}})
        local snap={treasury=1000,regions=1,wars={}}
        return disposition.score("wh2_main_hef_avelorn","player",snap,snap,{v1=true})
    end''')
    ordinary = culture_case(0)[0]
    corrupted = culture_case(3)[0]
    assert corrupted == ordinary + 150, (ordinary, corrupted)
    lua.globals().attitude = 0
    policy = lua.execute(entries[r'script\talkhammer\lib\slaanesh_policy.lua'][0].decode())
    for stage in range(4):
        for master in ['player','another_faction',None]:
            lua.globals().level = stage
            lua.globals().overlord = master
            context = policy.resolve(lua.globals().cm, json_module, faction, 'player')
            assert context.bonus == 50*stage
            assert context.requireAgreement == (stage==3 and master=='player')
            prompt = policy.instruction(context)
            assert (config['vassalDialogue']['instruction'] in prompt) == context.requireAgreement
            cases += 1
    lua.globals().level = 3
    lua.globals().vassal_error = True
    context = policy.resolve(lua.globals().cm, json_module, faction, 'player')
    assert context.bonus == 150 and not context.requireAgreement
    lua.globals().vassal_error = False
    for bad_level in [-1, 4, 1.5, '3']:
        lua.globals().level = bad_level
        assert evaluate(faction,0)[0] == 0
        cases += 1
    original_config = lua.globals().config_text
    lua.globals().config_text = '{broken json'
    lua.globals().level = 3
    assert evaluate(faction,0)[0] == 0
    lua.globals().config_text = original_config
    lua.globals().level = 0
    assert evaluate(faction, -116)[0] == -116  # no minimum of zero
    # Compile both modified modules, including ruler request integration.
    compile_lua = lua.eval('function(s) return assert(load(s)) end')
    for name, (source, compressed) in entries.items():
        if name.endswith('.lua'):
            assert not compressed
            compile_lua(source.decode())
    ruler_source=entries[r'script\talkhammer\lib\ruler.lua'][0].decode()
    assert 'policy.instruction(context)' in ruler_source
    assert 'cm:get_local_faction_name(true)' in ruler_source
    assert 'end, text, true)' in ruler_source
    # Execute the exact packaged request hook, not a parallel reconstruction.
    start=ruler_source.index('local slaanesh_stage = (function()')
    end=ruler_source.index('local function ask(',start)
    request_policy=lua.execute(ruler_source[start:end]+'\nreturn slaanesh_stage')
    lua.globals().level=3
    lua.globals().overlord='player'
    logs=[]
    prompt=request_policy(lua.globals().cm,json_module,logs.append,faction)
    assert config['vassalDialogue']['instruction'] in prompt
    assert 'require_agreement=true' in prompt
    assert any('bonus=150' in line and 'require_agreement=true' in line for line in logs)
    lua.globals().overlord='another_faction'
    prompt=request_policy(lua.globals().cm,json_module,logs.append,faction)
    assert config['vassalDialogue']['instruction'] not in prompt
    assert 'require_agreement=false' in prompt
    assert disp.attitude_scale == .4 and disp.regard_cap == 250
    print(f'Passed: {cases} stage/identity/vassal cases, actual score integration, caps, errors, Lua syntax and prompt hook')


if __name__ == '__main__':
    run(sys.argv[1], sys.argv[2] if len(sys.argv)>2 else None)
