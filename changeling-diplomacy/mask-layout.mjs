import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

const skins = 'ui/skins/default/';
const buttonSkin = 'button_square_medium_text_active.png';
const ornament = 'parchment_divider_title.png';
const guidPattern = /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{16}/g;

function definition(layout, id) {
  const match = layout.match(new RegExp('<' + id + '\\r?\\n[\\s\\S]*?</' + id + '>'));
  assert(match, 'Missing TalkHammer UI component ' + id);
  return match[0];
}

function dimensions(component, x, y, w, h) {
  return component.replace(/offset="[^"]+"/, 'offset="' + x + '.00,' + y + '.00"')
    .replace(/\bwidth="\d+"/g, 'width="' + w + '"')
    .replace(/\bheight="\d+"/g, 'height="' + h + '"');
}

function skin(component, texture, margin) {
  const withTexture = component.replace(/imagepath="[^"]+"/, 'imagepath="' + skins + texture + '"');
  assert(withTexture.includes(skins + texture), 'Expected a component image');
  return margin ? withTexture.replace(/margin="[^"]+"/, 'margin="' + margin + '"') : withTexture;
}

export function styleMaskLayout(source) {
  let layout = source;
  function remove(id) {
    const existing = new RegExp('<' + id + '\\r?\\n[\\s\\S]*?</' + id + '>');
    const link = new RegExp('<' + id + ' this="[^"]+"\\s*/>');
    layout = layout.replace(existing, '').replace(link, '');
  }
  function edit(id, change) {
    const before = definition(layout, id);
    layout = layout.replace(before, () => change(before));
  }
  const added = [];
  function add(template, id, x, y, w, h, style = component => component) {
    remove(id);
    const uuid = guid => {
      const hex = createHash('sha256').update(id + guid).digest('hex').slice(0, 32).toUpperCase();
      return hex.slice(0, 8) + '-' + hex.slice(8, 12) + '-' + hex.slice(12, 16) + '-' + hex.slice(16);
    };
    const component = definition(layout, template).replaceAll(template, id).replace(guidPattern, uuid);
    added.push({ id, xml: style(dimensions(component, x, y, w, h)), guid: component.match(/this="([^"]+)"/)[1] });
  }

  remove('th_mask_speaker');
  for (const id of ['th_speak', 'th_accept', 'th_mask_toggle', 'th_mask_explain', 'th_mask_withdraw', 'th_mask_insist']) {
    edit(id, component => skin(component, buttonSkin, '0.00,50.00,0.00,50.00'));
  }
  for (const [id, x, w] of [
    ['th_mask_toggle', 20, 196], ['th_mask_withdraw', 270, 234],
    ['th_mask_insist', 513, 166], ['th_mask_explain', 688, 240],
  ]) edit(id, component => dimensions(component, x, 454, w, 34));

  // The native parchment trim and button art follow the game's faction skin.
  for (const id of ['th_deal', 'th_ledger']) {
    edit(id, component => skin(component, 'panel_back_border.png', '4.00,4.00,4.00,4.00')
      .replace('textyoffset="6.00,6.00"', 'textyoffset="17.00,6.00"'));
  }
  const plaque = component => skin(component, ornament, '10.00,40.00,10.00,40.00')
    .replace('textyoffset="6.00,6.00"', 'textyoffset="2.00,2.00"')
    .replace('#F5F5DCFF', '#FFE9B0FF');
  add('th_att', 'th_mask_deal_heading', 822, 62, 196, 24, plaque);
  add('th_att', 'th_mask_ledger_heading', 822, 220, 196, 24, plaque);
  add('th_sub', 'th_mask_regard', 604, 8, 304, 24);
  add('th_sub', 'th_mask_status', 604, 34, 304, 24,
    component => component.replace('#A99F89FF', '#FFE9B0FF'));
  add('th_sub', 'th_mask_hint', 20, 427, 835, 23);

  const links = added.map(({id, guid}) => '<' + id + ' this="' + guid + '"/>').join('\n');
  assert.equal(layout.split('</th_frame>').length, 3, 'Expected frame in hierarchy and components');
  return layout.replace('</th_frame>', () => links + '\n</th_frame>')
    .replace('</components>', () => added.map(({xml}) => xml).join('\n') + '\n</components>');
}
