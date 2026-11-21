import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

export function addGiftPanel(layout) {
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
      })
      .replace(/offset="[^"]+"/, `offset="${x}.00,${y}.00"`)
      .replace(/(?<![\w_])width="\d+"/g, `width="${width}"`)
      .replace(/(?<![\w_])height="\d+"/g, `height="${height}"`);
    if (interactive !== undefined) {
      definition = definition.replace(/interactive="(?:true|false)"/, `interactive="${interactive}"`);
    }
    if (sourceId === 'th_frame') {
      definition = definition.replace(/(offset="[^"]+")/, '$1 priority="260"');
    }
    const firstGuid = definition.match(/this="([^"]+)"/)[1];
    definitions.push(definition);
    return { id, guid: firstGuid };
  }
  const open = clone('th_accept', 'th_gift_open', 220, 454, 142, 34);
  const picker = clone('th_frame', 'th_gift_picker', 20, 70, 1060, 300, true);
  const children = [
    clone('th_title', 'th_gift_header', 16, 6, 1028, 40),
  ];
  for (let index = 0; index < 8; index++) {
    children.push(clone('th_accept', `th_gift_choice_${index + 1}`,
      16 + index % 2 * 520, 58 + Math.floor(index / 2) * 45, 508, 40));
  }
  children.push(
    clone('th_accept', 'th_gift_back', 16, 255, 154, 34),
    clone('th_accept', 'th_gift_previous', 369, 255, 147, 34),
    clone('th_accept', 'th_gift_next', 530, 255, 147, 34),
    clone('th_accept', 'th_gift_send', 840, 255, 204, 34),
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
