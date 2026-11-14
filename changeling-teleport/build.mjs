import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const paths = [
  'db/campaign_stance_effects_junctions_tables/tww3_changeling_teleport_range',
  'db/effect_bundles_tables/tww3_changeling_teleport_range',
  'db/effect_bundles_to_effects_junctions_tables/tww3_changeling_teleport_range',
  'text/db/tww3_changeling_teleport_range.loc',
  'script/campaign/mod/changeling_long_jump.lua',
  'ui/templates/changeling_long_jump_button.twui.xml',
  'ui/skins/default/changeling_long_jump_symbol.png',
];

const entries = await Promise.all(paths.map(async (path) => {
  const content = await readFile(new URL(`./pack/${path}`, import.meta.url));
  const metadata = Buffer.alloc(5); // The last byte marks an uncompressed entry.
  metadata.writeUInt32LE(content.length);
  const name = Buffer.from(path.replaceAll('/', '\\') + '\0');
  return { content, index: Buffer.concat([metadata, name]) };
}));

const index = Buffer.concat(entries.map((entry) => entry.index));
const header = Buffer.alloc(28);
header.write('PFH5');
header.writeUInt32LE(3, 4); // Mod, selectable in the launcher.
header.writeUInt32LE(entries.length, 16);
header.writeUInt32LE(index.length, 20);
// Keep the original timestamp so the same assets reproduce the installed pack.
header.writeUInt32LE(Date.parse('2026-11-14T22:02:42Z') / 1000, 24);

const output = new URL('./changeling_teleport_range.pack', import.meta.url);
await writeFile(output, Buffer.concat([header, index, ...entries.map((entry) => entry.content)]));
console.log(fileURLToPath(output));
