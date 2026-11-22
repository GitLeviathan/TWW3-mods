import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { crc32, deflateSync } from 'node:zlib';
import { modPack, readEntry } from '../mod-tools/pack.mjs';

const folder = new URL('./', import.meta.url);
const output = fileURLToPath(new URL('changeling_cult_management.pack', folder));
const prefix = 'ui/campaign ui/changeling_cult_management';
const entryPath = value => value.replaceAll('/', '\\');
const skin = 'ui/skins/default/';
const assets = new Map();

function pixel(name, hex) {
  const file = `${prefix}/${name}.png`;
  function chunk(type, contents) {
    const nameAndData = Buffer.concat([Buffer.from(type), contents]);
    const bytes = Buffer.alloc(8 + nameAndData.length);
    bytes.writeUInt32BE(contents.length);
    nameAndData.copy(bytes, 4);
    bytes.writeUInt32BE(crc32(nameAndData), 4 + nameAndData.length);
    return bytes;
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(1);
  header.writeUInt32BE(1, 4);
  header[8] = 8;
  header[9] = 6;
  assets.set(entryPath(file), Buffer.concat([
    Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header),
    chunk('IDAT', deflateSync(Buffer.from('00' + hex + 'ff', 'hex'))), chunk('IEND', Buffer.alloc(0)),
  ]));
  return file;
}

const palette = {
  window: pixel('window', '102532'), header: pixel('header', '0c3c44'), line: pixel('line', '5c8493'),
  row: pixel('row', '142c34'), alt: pixel('alt', '10252f'), queue: pixel('queue', '11252f'),
};
function guid(key) {
  const hex = createHash('sha256').update('changeling-cult-management:' + key).digest('hex').toUpperCase();
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 32)].join('-');
}
const links = [];
const components = [];
function component(id, x, y, width, height, options = {}) {
  const { color = '#F8E9CFFF', size = 14, text = true, action = false, art = [], position = '', layer = 5 } = options;
  const idGuid = guid(id);
  const defaultState = guid(id + 'active');
  const states = action ? ['active', 'selected', 'inactive'] : ['active'];
  const images = art.map(([path], index) => `<component_image this="${guid(id+'asset'+index)}"
      uniqueguid="${guid(id+'asset'+index)}" imagepath="${path}"/>`).join('');
  const stateXml = states.map(state => {
    const stateGuid = guid(id + state);
    const metrics = art.filter(([, , only]) => !only || only === state).map(asset => {
      const index = art.indexOf(asset);
      const image = guid(id + state + 'image' + index);
      const margin = asset[1] ? ` margin="${asset[1]}" tile="true"` : '';
      return `<image this="${image}" uniqueguid="${image}" componentimage="${guid(id+'asset'+index)}"
        width="${width}" height="${height}"${margin}/>`;
    }).join('');
    const selected = action && state === 'selected' ? '#AFF0FFFF' : color;
    const ink = state === 'inactive' ? '#8FA8B1FF' : selected;
    const content = text ? `<component_text textvalign="Center" texthalign="${action ? 'Center' : 'Left'}"
      texthbehaviour="Never split" textxoffset="${action ? '8.00,8.00' : '0.00,0.00'}" textyoffset="0.00,0.00"
      font_m_font_name="${size >= 16 ? 'brand_header' : 'body'}" font_m_size="${size}"
      font_m_colour="${ink}" font_m_leading="2" fontcat_name="${size >= 16 ? 'header_16' : 'body_12'}"/>` : '';
    return `<${state} this="${stateGuid}" uniqueguid="${stateGuid}" name="${state}" width="${width}"
      height="${height}" interactive="${action && state !== 'inactive'}">
      ${metrics ? `<imagemetrics>${metrics}</imagemetrics>` : ''}${content}</${state}>`;
  }).join('');
  components.push(`<${id} this="${idGuid}" id="${id}" uniqueguid="${idGuid}" currentstate="${defaultState}"
    defaultstate="${defaultState}" offset="${x}.00,${y}.00" priority="${layer}" tooltipslocalised="false"
    allowhorizontalresize="false" allowverticalresize="false" ${position}>
    ${images ? `<componentimages>${images}</componentimages>` : ''}<states>${stateXml}</states></${id}>`);
  links.push(`<${id} this="${idGuid}"/>`);
}

function button(id, x, y, width, height, position = '') {
  component(id, x, y, width, height, {
    action: true, position,
    art: [[skin + 'button_square_medium_text_active.png', '0.00,25.00,0.00,25.00']],
  });
}

function layout(owner) {
  const group = links.pop();
  const root = guid(owner + 'root');
  const state = guid(owner + 'rootstate');
  return `<?xml version="1.0"?><layout version="142"><hierarchy><root this="${root}">
    ${group.replace('/>', `>${links.join('')}</${owner}>`)}
    </root></hierarchy><components>
    <root this="${root}" id="root" uniqueguid="${root}" currentstate="${state}" defaultstate="${state}">
    <states><default this="${state}" name="default" uniqueguid="${state}" width="1600" height="900"/></states></root>
    ${components.join('\n')}</components></layout>`;
}

const panel = 'changeling_cult_management';
const child = name => 'cmgr_' + name;
const label = (name, x, y, w, h, options) => component(child(name), x, y, w, h, options);
const control = (name, x, y, w, h) => button(child(name), x, y, w, h);
const border = [skin + 'tooltip_frame.png', '16.00,20.00,16.00,20.00'];
label('top_line', 18, 60, 1084, 2, {text:false, art:[[palette.line]], layer:1});
label('header', 18, 125, 724, 28, {text:false, art:[[palette.header]], layer:1});
label('queue_bg', 756, 103, 345, 403, {text:false, art:[[palette.queue]], layer:1});
label('emblem', 20, 12, 43, 43, {text:false, art:[['ui/flags/wh3_dlc24_tze_the_deceivers/mon_64.png']]});
label('title', 75, 12, 530, 29, {size:20});
label('faction', 75, 38, 300, 20, {size:12, color:'#A6E4F4FF'});
label('balance', 619, 15, 426, 32, {color:'#E9CB7EFF'});
control('close', 1054, 14, 48, 34);
control('gold', 18, 67, 134, 31);
control('books', 159, 67, 146, 31);
control('spread', 312, 67, 182, 31);
control('remove', 501, 67, 112, 31);
control('preset', 910, 67, 192, 31);
label('sort', 19, 102, 720, 23, {size:12, color:'#B8DDE5FF'});
label('heading_place', 28, 126, 270, 26);
label('heading_effect', 343, 126, 192, 26);
label('heading_cost', 547, 126, 184, 26);
for (let index = 1; index <= 6; index++) {
  const y = 154 + (index-1) * 55;
  label('row_bg'+index, 18, y, 724, 54, {text:false, art:[[index%2 ? palette.row : palette.alt]], layer:1});
  label('row_mark'+index, 18, y, 4, 54, {text:false, art:[[palette.line]], layer:2});
  label('place'+index, 28, y+2, 300, 23, {size:16});
  label('building'+index, 28, y+24, 308, 26, {size:12, color:'#B8CBD2FF'});
  label('effect'+index, 343, y, 195, 52, {color:'#A6E4F4FF'});
  label('price'+index, 547, y, 97, 52, {size:12});
  control('pick'+index, 649, y+9, 88, 34);
}
control('previous', 19, 489, 94, 34);
control('next', 240, 489, 94, 34);
control('all', 363, 489, 173, 34);
label('page', 127, 489, 105, 34, {color:'#B8CBD2FF'});
label('queue_title', 767, 109, 320, 30, {size:16});
label('queue_items', 767, 141, 319, 187, {size:12});
control('queue_previous', 763, 329, 61, 29);
label('queue_page', 835, 329, 190, 29, {size:12, color:'#B8CBD2FF'});
control('queue_next', 1030, 329, 65, 29);
label('total', 767, 362, 319, 30, {color:'#E9CB7EFF'});
control('clear', 763, 398, 87, 34);
control('review', 855, 398, 240, 34);
label('feedback', 766, 435, 327, 72, {size:12, color:'#A6E4F4FF'});
label('preset_heading', 21, 107, 720, 33, {size:16});
for (let index = 1; index <= 3; index++) {
  const y = 160 + (index-1) * 56;
  label('preset_label'+index, 24, y, 158, 38);
  control('preset_slot'+index, 185, y, 524, 38);
}
label('mode_label', 24, 340, 158, 38);
control('mode', 185, 340, 323, 38);
control('preset_save', 520, 340, 189, 38);
label('preset_offer', 24, 392, 501, 29, {color:'#A6E4F4FF'});
control('preset_next', 525, 392, 184, 31);
control('preset_apply', 185, 429, 524, 38);
label('disclosure', 19, 537, 1080, 25, {size:12, color:'#B8CBD2FF'});
component(panel, 0, 0, 1120, 573, {text:false, layer:250,
  position:'docking="Center" component_anchor_point="0.50,0.50" clipchildren="true"',
  art:[[palette.window], border]});
assets.set(entryPath(prefix + '/panel.twui.xml'), Buffer.from(layout(panel)));

links.length = 0;
components.length = 0;
const open = 'cmgr_open';
button(open, 28, 75, 174, 33, 'docking="Top Left"');
assets.set(entryPath(prefix + '/open.twui.xml'), Buffer.from(layout(open)));

const parts = await Promise.all(['catalog', 'management', 'native'].map(async name =>
  `local ${name} = (function()\n${await readFile(new URL(`${name}.lua`, folder), 'utf8')}\nend)()\n`));
parts.push(await readFile(new URL('campaign.lua', folder), 'utf8'));
assets.set('script\\campaign\\mod\\changeling_cult_management.lua', Buffer.from(parts.join('\n')));
const pack = modPack(assets);
await writeFile(output, pack);
for (const [name, content] of assets) {
  if (!readEntry(output, name).equals(content)) throw new Error(`Pack verification failed for ${name}`);
}
console.log(output);
console.log('SHA256', createHash('sha256').update(pack).digest('hex'));
