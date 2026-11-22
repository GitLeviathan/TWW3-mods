import fs from 'node:fs';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const here = new URL('./', import.meta.url);
const key = 'ui\\campaign ui\\dlc24_formless_horror.twui.xml';
const source = process.argv[2] ?? 'D:/Steam/steamapps/common/Total War WARHAMMER III/data/ui3.pack';
const bytes = fs.readFileSync(source);
assert.equal(bytes.toString('ascii', 0, 4), 'PFH5');
let p = 28 + bytes.readUInt32LE(12), offset = p + bytes.readUInt32LE(20);
const wanted = new Map([[key, ''], ['ui\\campaign ui\\character_details_panel_details.twui.xml', '']]);
for (let i = 0; i < bytes.readUInt32LE(16); i++) {
  const size = bytes.readUInt32LE(p), end = bytes.indexOf(0, p + 5);
  const name = bytes.toString('utf8', p + 5, end);
  if (wanted.has(name)) wanted.set(name, (bytes[p + 4]
    ? zlib.zstdDecompressSync(bytes.subarray(offset + 4, offset + size))
    : bytes.subarray(offset, offset + size)).toString('utf8'));
  p = end + 1; offset += size;
}
const native = wanted.get(key), equipment = [...wanted.values()][1];
assert(native && equipment, 'Native layouts not found');
fs.writeFileSync(new URL('native_dlc24_formless_horror.twui.xml', here), native);
fs.writeFileSync(new URL('native_character_details_panel_details.twui.xml', here), equipment);

const guid = label => {
  const h = crypto.createHash('sha256').update('changeling-formless-view-v1:' + label).digest('hex').toUpperCase();
  return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,32)}`;
};
const ids = Object.fromEntries(['page','renderer','character','name','unavailable','button','label'].map(x => [x, guid(x)]));
const esc = s => s.replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;').replaceAll('>','&gt;');
function component(xml, tag, id) {
  xml = xml.slice(xml.indexOf('<components>'));
  const found = [...xml.matchAll(new RegExp(`<${tag}\\s+this="${id}"[\\s\\S]*?<\\/${tag}>`, 'g'))];
  assert.equal(found.length, 1, `Expected one component ${id}`);
  return found[0][0];
}
function clone(xml, tag, oldId, newTag, newId) {
  let out = component(xml, tag, oldId);
  const refs = new Map([[oldId, newId]]);
  // Template GUIDs refer to the game's original template and must stay unchanged.
  for (const m of out.matchAll(/(?:this|uniqueguid)="([A-F0-9-]+)"/g)) {
    if (out.slice(Math.max(0,m.index-12),m.index).endsWith('_in_template')) continue;
    if (!refs.has(m[1])) refs.set(m[1],guid(newTag + ':' + m[1]));
  }
  out = out.replace(/(?<!_in_template)\b(this|uniqueguid|currentstate|defaultstate|componentimage)="([A-F0-9-]+)"/g,
    (all, attr, value) => `${attr}="${refs.get(value) ?? value}"`);
  return out.replace(new RegExp(`<(/?)${tag}(?=[\\s>])`, 'g'), `<$1${newTag}`)
    .replace(`id="${tag}"`, `id="${newTag}"`);
}
const info = 'B7B4E560-B970-41C3-AEE6720206563637';
const command = `Do(Component("${info}").SetVisible(Component("${ids.page}").IsVisible), Component("${ids.page}").SetVisible(Component("${ids.page}").IsVisible == false), self.UiMsg("MaskPreviewViewChanged"))`;
let button = clone(native, 'button_shapeshift', '5CF36C3D-36D4-437F-9E1901E5B34F2C53', 'button_mask_view', ids.button)
  .replace('dimensions="240.00,34.00"', 'dimensions="280.00,34.00" dock_point="Top Center" offset="0.00,0.00" priority="110"')
  .replace(/<callbacks_with_context>[\s\S]*?<\/callbacks_with_context>/,
    `<callbacks_with_context><callback_with_context callback_id="ContextCommandLeftClick" context_function_id="${esc(command)}"/></callbacks_with_context>`);
let label = clone(native, 'button_txt', '3AD45381-AABA-4F98-9C5D2BE8CC5A3204', 'button_txt', ids.label)
  .replace('dimensions="187.00,30.00"', 'dimensions="270.00,30.00"')
  .replaceAll('Assume for Battle', 'Показать 3D-модель')
  .replace(/\s+text_label="[^"]+"/g, '')
  .replace(/<localised_text\s+text="Показать 3D-модель"\/>/, '<localised_text text="Показать 3D-модель" is_text_localised="false"/>');

let renderer = clone(equipment, '_3d_character_window', '7B70D1A3-A1FB-4B07-B7F0D1F34C48652D', 'mask_model_renderer', ids.renderer)
  .replace('id="3D_character_window"','id="mask_model_renderer"')
  .replace('name="NewState"','name="mask_model_view"')
  .replace('offset="-478.00,0.00"','offset="0.00,0.00"')
  .replace('priority="45"','priority="80" updatewhennotvisible="true"')
  .replace('width="1960"','width="470"').replace('height="690"','height="510"')
  .replace(/\s*<callback_with_context\s+callback_id="ContextInteractiveSetter"[^>]*\/>/, '')
  .replace(/\s*<property\s+name="reset_button_(?:parent_)?id"[^>]*\/>/g, '');
const character = `<mask_asset_holder this="${ids.character}" id="mask_asset_holder" uniqueguid="${ids.character}" currentstate="${guid('character-state')}" defaultstate="${guid('character-state')}" updatewhennotvisible="true">
  <states><default this="${guid('character-state')}" name="default" uniqueguid="${guid('character-state')}" width="470" height="510"/></states>
</mask_asset_holder>`;

// Native text style, fed by the highlighted unit rather than the equipped mask.
let name = clone(native, 'dy_unit_name', 'C764AB5A-549D-41BB-9C3092D3EDE9625E', 'mask_model_name', ids.name);
name = name.replace(/offset="[^"]+"/, 'offset="0.00,510.00"');
let unavailable = name.replaceAll(ids.name, ids.unavailable).replaceAll('mask_model_name','mask_model_unavailable');
// Remap state/image GUIDs copied from name, keeping template references intact.
const remap = new Map();
for (const m of unavailable.matchAll(/\bthis="([A-F0-9-]+)"/g)) if(m[1]!==ids.unavailable) remap.set(m[1],guid('unavailable:'+m[1]));
for (const [old, next] of remap) unavailable = unavailable.replaceAll(old,next);
unavailable = unavailable.replace('offset="0.00,510.00"','offset="0.00,245.00"')
  .replace('text="dy_name"', 'text="Загрузка модели формы…"')
  .replace(/\s+textlabel="[^"]+"/g, '')
  .replace(/<callbackwithcontextlist>[\s\S]*?<\/callbackwithcontextlist>/, '');
const page = `<mask_model_page this="${ids.page}" id="mask_model_page" uniqueguid="${ids.page}" visible="false" offset="0.00,40.00" allowhorizontalresize="false" updatewhennotvisible="true" currentstate="${guid('page-state')}" defaultstate="${guid('page-state')}">
  <states><default this="${guid('page-state')}" name="default" uniqueguid="${guid('page-state')}" width="470" height="550"/></states>
</mask_model_page>`;
const additions = [page,character,name,unavailable,button,label].join('\n');
const anchor = '<preview_holder this="0A958E9F-5526-4972-9FA182448EADC4F4">';
assert.equal(native.split(anchor).length,2);
// Add siblings after the native information holder, never inside its List layout.
const start = native.indexOf(anchor), innerEnd = native.indexOf('</preview_holder>',start);
const outerEnd = native.indexOf('</preview_holder>',innerEnd+1);
const hierarchy = `<mask_model_page this="${ids.page}"><mask_asset_holder this="${ids.character}"/><mask_model_name this="${ids.name}"/><mask_model_unavailable this="${ids.unavailable}"/></mask_model_page>
  <button_mask_view this="${ids.button}"><button_txt this="${ids.label}"/></button_mask_view>\n`;
const modified = (native.slice(0,outerEnd)+hierarchy+native.slice(outerEnd)).replace('</components>',additions+'\n</components>');
fs.writeFileSync(new URL('dlc24_formless_horror.twui.xml',here),modified);
const models=JSON.parse(fs.readFileSync(new URL('./model-manifest.json',here))).models;
const nativeScenes=JSON.parse(fs.readFileSync(new URL('./native-scenes.json',here)));
const entries=new Map([[key,Buffer.from(modified)]]),luaModels=[],luaScenes=[];
for(const [unit,model] of Object.entries(models)){
  assert(/^[a-zA-Z0-9_]+$/.test(unit));
  const layoutPath='ui/campaign ui/tww3_mask_models/'+unit;
  luaModels.push(`["${unit}"]="${layoutPath}"`);
  let scene=renderer.replace('VariantMeshes/VariantMeshDefinitions/emp_captains.VariantMeshDefinition',esc(model.asset))
    .replace('skeleton_type="humanoid01"',`skeleton_type="${esc(model.skeleton)}"`)
    .replace(/camera_target="[^"]+"/,`camera_target="0.00,${(model.height*.5).toFixed(3)},0.00"`)
    .replace(/camera_dist="[^"]+"/,`camera_dist="${(model.height*2.2).toFixed(3)}"`);
  if(model.animation)scene=scene.replace(/<animation_paths>[\s\S]*?<\/animation_paths>/,`<animation_paths><path value="${esc(model.animation)}"/></animation_paths>`);
  else scene=scene.replace('num_anims="1"','num_anims="0"').replace(/<animation_paths>[\s\S]*?<\/animation_paths>/,'');
  assert(scene.includes(`filepath="${esc(model.asset)}"`),'Model substitution failed: '+unit);
  const nativeScene = nativeScenes[unit];
  if (nativeScene) {
    assert(/^composite_scene\/[\w/-]+\.csc$/.test(nativeScene), `Invalid native scene for ${unit}`);
    const expression = esc(`Format("%s", "${nativeScene}")`);
    const setter = `<callback_with_context callback_id="ContextComponentModelSetter" context_object_id="CcoMainUnitRecord" context_function_id="${expression}"/>`;
    scene = scene.replace(/<callback_with_context callback_id="ClanLeaderModelView">[\s\S]*?<\/callback_with_context>/, setter);
    assert(scene.includes(setter), `Missing model initialization for ${unit}`);
    luaScenes.push(`["${unit}"]="${nativeScene}"`);
  }
  const rid=guid(unit+':root'), sid=guid(unit+':root-state');
  const xml=`<?xml version="1.0"?><layout version="142"><hierarchy><root this="${rid}"><mask_model_renderer this="${ids.renderer}"/></root></hierarchy><components>
  <root this="${rid}" id="root" uniqueguid="${rid}" currentstate="${sid}" defaultstate="${sid}" clipchildren="true"><states><default this="${sid}" name="default" uniqueguid="${sid}" width="470" height="510"/></states></root>${scene}</components></layout>`;
  entries.set(layoutPath.replaceAll('/','\\')+'.twui.xml',Buffer.from(xml));
}
const lua=fs.readFileSync(new URL('./preview.lua',here),'utf8').replace('__MODEL_MAP__','{'+luaModels.join(',\n')+'}')
  .replace('__NATIVE_SCENE_MAP__','{'+luaScenes.join(',\n')+'}');
entries.set('script\\campaign\\mod\\tww3_mask_direct_asset_preview.lua',Buffer.from(lua));
fs.writeFileSync(new URL('./preview.generated.lua',here),lua);
const header=Buffer.alloc(28);header.write('PFH5');header.writeUInt32LE(3,4);header.writeUInt32LE(entries.size,16);
const idx=Buffer.concat([...entries].map(([name,b])=>{const meta=Buffer.alloc(5);meta.writeUInt32LE(b.length);return Buffer.concat([meta,Buffer.from(name+'\0')]);}));
header.writeUInt32LE(idx.length,20);const pack=Buffer.concat([header,idx,...entries.values()]);
fs.writeFileSync(new URL('00_changeling_formless_model_preview.pack',here),pack);
const sha256 = b => crypto.createHash('sha256').update(b).digest('hex');
fs.writeFileSync(new URL('verification.json',here),JSON.stringify({source,sourceSha256:sha256(native),sha256:sha256(pack),ids,
  sceneSource:'Native full-body scenes and direct battle assets',models:Object.keys(models).length,nativeScenes:luaScenes.length,nativeControlsUnchanged:true,inGameVerified:false},null,2)+'\n');
console.log('Built 00_changeling_formless_model_preview.pack '+sha256(pack));
