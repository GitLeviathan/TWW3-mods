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

function initiallyHidden(component) {
  const header = component.slice(0, component.indexOf('>'));
  if (header.includes('visible="false"')) return component;
  return component.replace(/(offset="[^"]+")/, '$1 visible="false"');
}

export function verifyMaskLayout(layout) {
  if (!layout.includes('id="th_mask_toggle"')) return;
  const controls = [
    'th_mask_toggle', 'th_mask_withdraw', 'th_mask_insist', 'th_mask_explain', 'th_speak',
    'th_mask_preview_next', 'th_mask_preview_exit',
  ];
  if (layout.includes('id="th_gift_open"')) controls.push('th_gift_open');
  const labels = ['th_mask_regard', 'th_mask_status', 'th_mask_hint', 'th_mask_deal_heading', 'th_mask_ledger_heading'];
  const bounds = [];
  for (const id of [...controls, ...labels]) {
    const component = definition(layout, id);
    const gid = component.match(/this="([^"]+)"/)[1];
    assert.equal(layout.split('<' + id + ' this="' + gid + '"/>').length, 2, 'Invalid layout link: ' + id);
    const [x, y] = component.match(/offset="([^"]+)"/)[1].split(',').map(Number);
    const [w, h] = ['width', 'height'].map(name => Number(component.match(new RegExp('\\b' + name + '="(\\d+)"'))[1]));
    assert(x >= 0 && y >= 0 && x + w <= 1100 && y + h <= 500, 'Panel component outside frame: ' + id);
    const interactive = controls.includes(id);
    assert(component.includes('interactive="' + String(interactive) + '"'), 'Invalid input state: ' + id);
    if (interactive) bounds.push({ id, x, y, w, h });
  }
  for (const [index, a] of bounds.entries()) {
    for (const b of bounds.slice(index + 1)) {
      assert(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y,
        'Overlapping TalkHammer buttons: ' + a.id + ' and ' + b.id);
    }
  }
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
    added.push({ id, xml: initiallyHidden(style(dimensions(component, x, y, w, h))), guid: component.match(/this="([^"]+)"/)[1] });
  }

  remove('th_mask_speaker');
  for (const id of ['th_speak', 'th_accept', 'th_mask_toggle', 'th_mask_explain', 'th_mask_withdraw', 'th_mask_insist']) {
    edit(id, component => skin(component, buttonSkin, '0.00,50.00,0.00,50.00'));
  }
  for (const [id, x, w] of [
    ['th_mask_toggle', 20, 196], ['th_mask_withdraw', 270, 234],
    ['th_mask_insist', 513, 166], ['th_mask_explain', 688, 240],
  ]) edit(id, component => initiallyHidden(dimensions(component, x, 454, w, 34)));
  for (const id of ['th_crest', 'th_portrait', 'th_accept']) edit(id, initiallyHidden);

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
  const smallAction = component => skin(component, buttonSkin, '0.00,22.00,0.00,22.00')
    .replace('textyoffset="6.00,6.00"', 'textyoffset="2.00,2.00"')
    .replace('interactive="false"', 'interactive="true"');
  add('th_att', 'th_mask_preview_next', 924, 39, 76, 24, smallAction);
  add('th_att', 'th_mask_preview_exit', 1006, 39, 76, 24, smallAction);

  const links = added.map(({id, guid}) => '<' + id + ' this="' + guid + '"/>').join('\n');
  assert.equal(layout.split('</th_frame>').length, 3, 'Expected frame in hierarchy and components');
  const styled = layout.replace('</th_frame>', () => links + '\n</th_frame>')
    .replace('</components>', () => added.map(({xml}) => xml).join('\n') + '\n</components>');
  verifyMaskLayout(styled);
  return styled;
}
