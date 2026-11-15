import { open, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { zstdDecompressSync } from 'node:zlib';

const gameData = process.argv[2] ?? 'D:/Steam/steamapps/common/Total War WARHAMMER III/data';
const layoutPath = 'ui\\campaign ui\\city_info_bar.twui.xml';
const scriptPath = 'script\\campaign\\mod\\changeling_cult_tracker.lua';

async function readStockLayout(packPath) {
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
        if (xml.length !== contents.readUInt32LE(0)) throw new Error('Truncated city information bar layout');
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

function addBadge(layout, badge) {
  const cultIconLinkEnd = /^([\t ]*)<\/wh3_dae_trickster_cult_building>\r?$/m;
  const definitionsEnd = /^[\t ]*<\/components>\r?$/m;
  const badgeRef = badge.match(/^<(\w+)\r?\n\s+this="([A-F0-9-]+)"/);
  const hierarchyEnd = layout.indexOf('</hierarchy>');
  const hierarchy = layout.slice(0, hierarchyEnd);
  const definitions = layout.slice(hierarchyEnd);
  if (!badgeRef || hierarchyEnd < 0 || !cultIconLinkEnd.test(hierarchy) ||
      !definitionsEnd.test(definitions) || layout.includes(badgeRef[1])) {
    throw new Error('The city information bar no longer matches the expected cult icon layout');
  }
  const newline = layout.includes('\r\n') ? '\r\n' : '\n';
  const [, name, guid] = badgeRef;
  const definition = badge.trimEnd().split(/\r?\n/).map((line) => '\t\t' + line).join(newline);
  return hierarchy.replace(cultIconLinkEnd, (closing, indent) =>
    `${indent}\t<${name} this="${guid}"/>${newline}${closing}`)
    + definitions.replace(definitionsEnd, (closing) => definition + newline + closing);
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

const [layout, badge, script] = await Promise.all([
  readStockLayout(join(gameData, 'ui3.pack')),
  readFile(new URL('./badge.xml', import.meta.url), 'utf8'),
  readFile(new URL('./changeling_cult_tracker.lua', import.meta.url), 'utf8'),
]);
const output = new URL('./changeling_cult_tracker.pack', import.meta.url);
await writeFile(output, buildPack([
  [scriptPath, Buffer.from(script.replaceAll('\r\n', '\n'))],
  [layoutPath, Buffer.from(addBadge(layout, badge))],
]));
console.log(fileURLToPath(output));
