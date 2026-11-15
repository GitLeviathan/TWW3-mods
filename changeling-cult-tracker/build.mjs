import { createHash } from 'node:crypto';
import { open, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { zstdDecompressSync } from 'node:zlib';

const gameData = process.argv[2] ?? 'D:/Steam/steamapps/common/Total War WARHAMMER III/data';
const layoutPath = 'ui\\campaign ui\\city_info_bar.twui.xml';
const provinceLayoutPath = 'ui\\campaign ui\\dropdown_regions.twui.xml';
const scriptPath = 'script\\campaign\\mod\\changeling_cult_tracker.lua';

async function readStockLayout(packPath, layoutPath) {
  const file = await open(packPath);
  try {
    const header = Buffer.alloc(28);
    await file.read(header, 0, header.length, 0);
    if (header.toString('ascii', 0, 4) !== 'PFH5' || (header.readUInt32LE(4) & ~0xf) !== 0) {
      throw new Error('Expected an unflagged PFH5 pack');
    }
    const index = Buffer.alloc(header.readUInt32LE(20));
    const indexOffset = header.length + header.readUInt32LE(12);
    await file.read(index, 0, index.length, indexOffset);
    let cursor = 0;
    let offset = indexOffset + index.length;
    for (let entry = 0; entry < header.readUInt32LE(16); entry++) {
      const length = index.readUInt32LE(cursor);
      const end = index.indexOf(0, cursor + 5);
      if (end < 0) throw new Error('Invalid pack entry');
      const name = index.toString('utf8', cursor + 5, end);
      if (name === layoutPath) {
        const contents = Buffer.alloc(length);
        await file.read(contents, 0, length, offset);
        if (index[cursor + 4] === 0) return contents.toString('utf8');
        const xml = zstdDecompressSync(contents.subarray(4));
        if (xml.length !== contents.readUInt32LE(0)) throw new Error(`Truncated layout: ${layoutPath}`);
        return xml.toString('utf8');
      }
      cursor = end + 1;
      offset += length;
    }
    throw new Error(`Could not find ${layoutPath} in ${packPath}`);
  } finally {
    await file.close();
  }
}

function appendDefinitions(layout, definitions, newline) {
  const definitionsEnd = /^[\t ]*<\/components>\r?$/m;
  if (!definitionsEnd.test(layout)) throw new Error('Missing component definitions');
  const text = definitions.map((definition) => definition.trimEnd().split(/\r?\n/)
    .map((line) => '\t\t' + line).join(newline)).join(newline);
  return layout.replace(definitionsEnd, (closing) => text + newline + closing);
}

function addBadge(layout, badge) {
  const cultIconLinkEnd = /^([\t ]*)<\/wh3_dae_trickster_cult_building>\r?$/m;
  const badgeRef = badge.match(/^<(\w+)\r?\n\s+this="([A-F0-9-]+)"/);
  const hierarchyEnd = layout.indexOf('</hierarchy>');
  const hierarchy = layout.slice(0, hierarchyEnd);
  const definitions = layout.slice(hierarchyEnd);
  if (!badgeRef || hierarchyEnd < 0 || !cultIconLinkEnd.test(hierarchy) || layout.includes(badgeRef[1])) {
    throw new Error('The city information bar no longer matches the expected cult icon layout');
  }
  const newline = layout.includes('\r\n') ? '\r\n' : '\n';
  const [, name, guid] = badgeRef;
  return hierarchy.replace(cultIconLinkEnd, (closing, indent) =>
    `${indent}\t<${name} this="${guid}"/>${newline}${closing}`)
    + appendDefinitions(definitions, [badge], newline);
}

function addProvinceBadges(layout, badge) {
  const cultIcons = /^([\t ]*)<wh3_main_dae_cult this="([A-F0-9-]+)"\/>\r?$/gm;
  const name = 'changeling_cult_province_count';
  const anchors = [...layout.matchAll(cultIcons)];
  if (anchors.length !== 2 || layout.includes(name)) {
    throw new Error('The province list no longer matches the expected cult icon layout');
  }
  const newline = layout.includes('\r\n') ? '\r\n' : '\n';
  const definitions = [];
  const withLinks = layout.replace(cultIcons, (_, indent, iconGuid) => {
    const definition = badge.replaceAll('changeling_cult_target_count', name)
      .replace('offset="22.00,1.00"', 'offset="13.00,0.00"')
      .replaceAll('="19"', '="16"')
      .replaceAll('CcoCampaignSettlement', 'CcoCampaignProvince')
      .replaceAll('RegionRecordKey', 'Key')
      .replaceAll('changeling_cult_tracker_', 'changeling_cult_tracker_province_')
      .replace(/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{16}/g, (guid) => {
        const hex = createHash('sha256').update(iconGuid + guid).digest('hex').slice(0, 32).toUpperCase();
        return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16)}`;
      });
    const guid = definition.match(/\bthis="([^"]+)"/)[1];
    definitions.push(definition);
    return [
      `${indent}<wh3_main_dae_cult this="${iconGuid}">`,
      `${indent}\t<${name} this="${guid}"/>`,
      `${indent}</wh3_main_dae_cult>`,
    ].join(newline) + (newline === '\r\n' ? '\r' : '');
  });
  return appendDefinitions(withLinks, definitions, newline);
}

function buildPack(entries) {
  const header = Buffer.alloc(28);
  header.write('PFH5');
  header.writeUInt32LE(3, 4); // Mod, selectable in the launcher.
  header.writeUInt32LE(entries.length, 16);
  const index = Buffer.concat(entries.map(([name, contents]) => {
    const metadata = Buffer.alloc(5);
    metadata.writeUInt32LE(contents.length);
    return Buffer.concat([metadata, Buffer.from(name + '\0')]);
  }));
  header.writeUInt32LE(index.length, 20);
  return Buffer.concat([header, index, ...entries.map(([, contents]) => contents)]);
}

const uiPack = join(gameData, 'ui3.pack');
const [layout, provinces, badge, script] = await Promise.all([
  readStockLayout(uiPack, layoutPath),
  readStockLayout(uiPack, provinceLayoutPath),
  readFile(new URL('./badge.xml', import.meta.url), 'utf8'),
  readFile(new URL('./changeling_cult_tracker.lua', import.meta.url), 'utf8'),
]);
const output = new URL('./changeling_cult_tracker.pack', import.meta.url);
await writeFile(output, buildPack([
  [scriptPath, Buffer.from(script.replaceAll('\r\n', '\n'))],
  [layoutPath, Buffer.from(addBadge(layout, badge))],
  [provinceLayoutPath, Buffer.from(addProvinceBadges(provinces, badge))],
]));
console.log(fileURLToPath(output));
