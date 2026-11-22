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

function centerActionArt(component, width, height) {
  // The 46 px source texture is painted between y=2 and y=33.
  const inset = Math.round(height * (23 - 17.5) / 46);
  const cap = Math.min(50, Math.floor(width / 3));
  return skin(component, buttonSkin, `0.00,${cap}.00,0.00,${cap}.00`)
    .replace(/<image\s[^>]*\/>/, image =>
      image.replace(/\s+offset="[^"]+"/, '').replace('/>', ` offset="0.00,${inset}.00"/>`))
    .replace(/textyoffset="[^"]+"/, 'textyoffset="0.00,0.00"');
}

export const actionRow = { y: 442, height: 48 };

export function placeActionButton(component, x, y, width, height) {
  return centerActionArt(dimensions(component, x, y, width, height), width, height);
}

export function styleConversationLayout(layout) {
  for (const [id, x, width] of [['th_accept', 20, 476], ['th_speak', 918, 162]]) {
    const component = definition(layout, id);
    layout = layout.replace(component, () => placeActionButton(component, x, actionRow.y, width, actionRow.height));
  }
  const frame = definition(layout, 'th_frame');
  const tiled = skin(frame, 'tooltip_frame.png', '16.00,20.00,16.00,20.00')
    .replace(/<image\s[^>]*\/>/, image =>
      image.replace(/\btile="[^"]+"\s*/, '').replace('margin=', 'tile="true" margin='));
  return layout.replace(frame, () => tiled);
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
  if (layout.includes('id="th_mask_confirm"')) controls.push('th_mask_confirm');
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
  const confirm = bounds.find(({id}) => id === 'th_mask_confirm');
  if (confirm) {
    const withdraw = bounds.find(({id}) => id === 'th_mask_withdraw');
    assert(confirm.w === withdraw.w && confirm.h === withdraw.h && confirm.y === withdraw.y,
      'Confirm and decline must be the same size and on the same row');
  }
  for (const [index, a] of bounds.entries()) {
    for (const b of bounds.slice(index + 1)) {
      // Confirm appears only after the check, when Insist and Explain are hidden.
      if (b === confirm && (a.id === 'th_mask_insist' || a.id === 'th_mask_explain')) continue;
      assert(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y,
        'Overlapping TalkHammer buttons: ' + a.id + ' and ' + b.id);
    }
  }
}

export function styleMaskLayout(source) {
  let layout = styleConversationLayout(source);
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
  const decisionWidth = 186;
  for (const [id, x, w] of [
    ['th_mask_toggle', 710, 200], ['th_mask_withdraw', 20, decisionWidth],
    ['th_mask_insist', 214, 96], ['th_mask_explain', 318, 178],
  ]) edit(id, component => initiallyHidden(placeActionButton(component, x, actionRow.y, w, actionRow.height)));
  add('th_mask_withdraw', 'th_mask_confirm', 214, actionRow.y, decisionWidth, actionRow.height);
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
  const smallAction = component => centerActionArt(component, 82, 32)
    .replace('interactive="false"', 'interactive="true"');
  add('th_att', 'th_mask_preview_next', 910, 30, 82, 32, smallAction);
  add('th_att', 'th_mask_preview_exit', 998, 30, 82, 32, smallAction);

  const links = added.map(({id, guid}) => '<' + id + ' this="' + guid + '"/>').join('\n');
  assert.equal(layout.split('</th_frame>').length, 3, 'Expected frame in hierarchy and components');
  const styled = layout.replace('</th_frame>', () => links + '\n</th_frame>')
    .replace('</components>', () => added.map(({xml}) => xml).join('\n') + '\n</components>');
  verifyMaskLayout(styled);
  return styled;
}
