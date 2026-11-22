import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { actionRow, placeActionButton, styleConversationLayout } from '../changeling-diplomacy/mask-layout.mjs';

export function addGiftPanel(layout) {
  layout = styleConversationLayout(layout);
  const definitions = [];
  function clone(sourceId, id, x, y, width, height, interactive) {
    const source = layout.match(new RegExp('<' + sourceId + '\\r?\\n[\\s\\S]*?</' + sourceId + '>'));
    assert(source, 'Missing TalkHammer component ' + sourceId);
    const guid = new Map();
    let definition = source[0].replaceAll(sourceId, id)
      .replace(/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{16}/g, (old) => {
        if (!guid.has(old)) {
          const hex = createHash('sha256').update(id + old).digest('hex').slice(0, 32).toUpperCase();
          guid.set(old, `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16)}`);
        }
        return guid.get(old);
      });
    definition = sourceId === 'th_accept' ? placeActionButton(definition, x, y, width, height)
      : definition.replace(/offset="[^"]+"/, `offset="${x}.00,${y}.00"`)
      .replace(/(?<![\w_])width="\d+"/g, `width="${width}"`)
      .replace(/(?<![\w_])height="\d+"/g, `height="${height}"`);
    if (interactive !== undefined) {
      definition = definition.replace(/interactive="(?:true|false)"/, `interactive="${interactive}"`);
    }
    if (sourceId === 'th_frame') {
      definition = definition.replace(/(offset="[^"]+")/, '$1 priority="260"');
    }
    if ((id === 'th_gift_open' || id === 'th_gift_picker') && !definition.slice(0, definition.indexOf('>')).includes('visible="false"')) {
      definition = definition.replace(/(offset="[^"]+")/, '$1 visible="false"');
    }
    const firstGuid = definition.match(/this="([^"]+)"/)[1];
    definitions.push(definition);
    return { id, guid: firstGuid };
  }
  const hasMask = layout.includes('id="th_mask_toggle"');
  const open = clone('th_accept', 'th_gift_open', hasMask ? 504 : 710, actionRow.y, hasMask ? 198 : 200, actionRow.height);
  const picker = clone('th_frame', 'th_gift_picker', 20, 66, 1060, 314, true);
  const children = [
    clone('th_title', 'th_gift_header', 16, 4, 1028, 40),
  ];
  for (let index = 0; index < 8; index++) {
    children.push(clone('th_accept', `th_gift_choice_${index + 1}`,
      16 + index % 2 * 520, 46 + Math.floor(index / 2) * 54, 508, 48));
  }
  children.push(
    clone('th_accept', 'th_gift_previous', 218, 262, 200, 48),
    clone('th_accept', 'th_gift_back', 430, 262, 200, 48),
    // Only the confirmation screen shows Send in place of Next.
    clone('th_accept', 'th_gift_next', 642, 262, 200, 48),
    clone('th_accept', 'th_gift_send', 642, 262, 200, 48),
  );
  const link = ({id, guid}) => `<${id} this="${guid}"/>`;
  const additions = `    ${link(open)}
    <${picker.id} this="${picker.guid}">
      ${children.map(link).join('\n      ')}
    </${picker.id}>
`;
  assert.equal(layout.split('</th_frame>').length, 3, 'Expected frame in hierarchy and components');
  return layout.replace('</th_frame>', additions + '</th_frame>')
    .replace('</components>', definitions.join('\n') + '\n</components>');
}
