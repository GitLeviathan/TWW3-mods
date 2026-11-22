"""Structural checks; a live game render is still required."""
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

HERE = Path(__file__).parent
native = ET.parse(HERE / 'native_dlc24_formless_horror.twui.xml').getroot()
result = ET.parse(HERE / 'dlc24_formless_horror.twui.xml').getroot()
components = {c.attrib['this']: c for c in result.find('components')}
original = {c.attrib['this']: c for c in native.find('components')}

# No native component or action can be changed by this view-only extension.
for key, component in original.items():
    assert ET.tostring(components[key]) == ET.tostring(component), key
added = [c for key, c in components.items() if key not in original]
assert len(added) == 6
callbacks = [c for component in added for c in component.iter('callback_with_context')]
assert not any('Equip' in c.get('context_function_id', '') for c in callbacks)
assert not any(c.get('callback_id') in {'ClanLeaderModelView','ContextComponentModelSetter'} for c in callbacks)
assert not any('CharacterContext' in c.get('context_function_id','') or 'HasCharacter' in c.get('context_function_id','') for c in callbacks)
model = next(c for c in added if c.get('id') == 'mask_model_page')
assert model.get('visible') == 'false'
label = next(c for c in added if c.get('id') == 'button_txt')
assert not any('text_label' in e.attrib for e in label.iter())
assert 'ComponentText_60607fac' not in ET.tostring(label, encoding='unicode')
fallback = next(c for c in added if c.get('id') == 'mask_model_unavailable')
assert 'dy_name' not in ET.tostring(fallback, encoding='unicode')
assert 'Показать 3D-модель' in ET.tostring(label, encoding='unicode')
script = (HERE / 'preview.generated.lua').read_text(encoding='utf8')
assert 'Показать характеристики' in script
assert 'HasCharacter' not in script and 'CharacterContext' not in script
all_this = [e.get('this') for e in result.find('components').iter() if e.get('this')]
assert len(all_this) == len(set(all_this)), 'duplicate local GUID'
hierarchy = result.find('hierarchy')
refs = [e.get('this') for e in hierarchy.iter() if e.get('this')]
assert len(refs) == len(set(refs))
assert all(ref in components for ref in refs)
outer = next(e for e in hierarchy.iter() if e.get('this') == '0A958E9F-5526-4972-9FA182448EADC4F4')
assert len(outer) == 3  # Native info, model page, switch.
page = next(e for e in outer if e.tag == 'mask_model_page')
assert {e.tag for e in page} == {'mask_asset_holder', 'mask_model_name', 'mask_model_unavailable'}
switch = next(c for c in added if c.get('id') == 'button_mask_view')
command = switch.find('.//callback_with_context').get('context_function_id')
assert command.count('.SetVisible(') == 2
assert 'B7B4E560-B970-41C3-AEE6720206563637' in command
assert model.get('this') in command
# Removing our two branches must restore the entire native hierarchy.
for child in list(outer)[1:]:
    outer.remove(child)
def shape(node):
    return node.tag, node.attrib, [shape(child) for child in node]
assert shape(hierarchy) == shape(native.find('hierarchy'))

pack = (HERE / '00_changeling_formless_model_preview.pack').read_bytes()
assert pack[:4] == b'PFH5'
index_size = struct.unpack_from('<I', pack, 20)[0]
offset, cursor = 28+index_size, 28
entries = {}
for _ in range(struct.unpack_from('<I',pack,16)[0]):
    size = struct.unpack_from('<I',pack,cursor)[0]
    assert pack[cursor+4] == 0
    end = pack.index(0,cursor+5)
    key = pack[cursor+5:end].decode()
    entries[key] = pack[offset:offset+size]
    offset += size
    cursor = end+1
assert offset == len(pack) and cursor == 28+index_size
assert entries[r'ui\campaign ui\dlc24_formless_horror.twui.xml'] == (HERE/'dlc24_formless_horror.twui.xml').read_bytes()
import json
manifest = json.loads((HERE/'model-manifest.json').read_text())['models']
native_scenes = json.loads((HERE/'native-scenes.json').read_text())
assert native_scenes['wh3_dlc29_chs_cha_glottkin'] == 'composite_scene/porthole/wh3_dlc29_chs_cha_glottkin_porthole_fullbody.csc'
assert native_scenes['wh_dlc05_wef_cha_orion_0'].endswith('/orion.csc')
assert native_scenes.keys() <= manifest.keys()
assert len(entries) == len(manifest)+2
for unit, model in manifest.items():
    scene = ET.fromstring(entries[rf'ui\campaign ui\tww3_mask_models\{unit}.twui.xml'])
    comp = scene.find('components/mask_model_renderer')
    assert comp.find('.//ComponentModel').get('filepath') == model['asset'], unit
    assert comp.find('.//ComponentModel').get('skeleton_type') == model['skeleton'], unit
    state = comp.find('states/newstate')
    assert state.get('interactive') == 'true' and state.get('name') == 'mask_model_view'
    callbacks = list(comp.iter('callback_with_context'))
    assert len(callbacks) == 2 and callbacks[1].get('callback_id') == 'ComponentModelController', unit
    loader = callbacks[0]
    if unit in native_scenes:
        assert loader.get('callback_id') == 'ContextComponentModelSetter', unit
        assert loader.get('context_object_id') == 'CcoMainUnitRecord', unit
        assert loader.get('context_function_id') == f'Format("%s", "{native_scenes[unit]}")', unit
    else:
        assert loader.get('callback_id') == 'ClanLeaderModelView', unit
        assert loader.find('.//property[@name="fullbody_camera"]') is not None, unit
        assert loader.get('context_object_id') is None, unit
sample = [manifest[k]['asset'] for k in ['wh2_main_hef_cha_tyrion_0','wh_dlc05_wef_cha_orion_0','wh2_main_lzd_cha_lord_mazdamundi_0']]
assert len(set(sample)) == 3 and not any('emp_captains' in s.lower() for s in sample)
print(f'PASS: {len(manifest)} model layouts, {len(native_scenes)} native scenes; no campaign-character dependency; native controls unchanged; pack round-trip')
