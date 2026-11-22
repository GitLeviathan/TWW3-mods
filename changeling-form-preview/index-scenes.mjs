import fs from 'node:fs';
import path from 'node:path';
import { decode, entryBytes, packIndex } from './game-data.mjs';

const data = process.argv[2] ?? 'D:/Steam/steamapps/common/Total War WARHAMMER III/data';
const destination = new URL('native-scenes.json', import.meta.url);
const { models } = JSON.parse(fs.readFileSync(new URL('model-manifest.json', import.meta.url), 'utf8'));
const normalise = value => value.toLowerCase().replaceAll('\\', '/');
const scenePaths = new Set();
const byAsset = new Map();
for (const entry of packIndex(path.join(data, 'data.pack'))) {
  const name = normalise(entry.name);
  if (!name.startsWith('composite_scene/') || !name.endsWith('.csc')) continue;
  scenePaths.add(name);
  if (!name.startsWith('composite_scene/lord_selection/')) continue;
  const scene = normalise(entryBytes(entry).toString('latin1'));
  const assets = new Set(scene.match(/variantmeshes\/variantmeshdefinitions\/[\w-]+\.variantmeshdefinition/g));
  if (assets.size !== 1) continue;
  const [asset] = assets;
  if (!byAsset.has(asset)) byAsset.set(asset, []);
  byAsset.get(asset).push(name);
}

const nativeUnits = packIndex(path.join(data, 'db.pack'))
  .filter(entry => entry.name.startsWith('db\\main_units_tables\\')).flatMap(decode);
const byUnit = new Map(nativeUnits.map(row => [row.unit, row]));
const scenes = {};
for (const [unit, model] of Object.entries(models).sort(([a], [b]) => a.localeCompare(b))) {
  const porthole = byUnit.get(unit)?.porthole_composite_scene;
  const wholeBody = porthole && normalise(porthole).replace(/(?:_01)?\.csc$/, '_fullbody.csc');
  const matching = byAsset.get(normalise(model.asset)) ?? [];
  const assetName = path.posix.basename(model.asset.toLowerCase(), '.variantmeshdefinition');
  const named = matching.filter(scene => {
    const name = path.posix.basename(scene, '.csc');
    return assetName === name || assetName.endsWith('_' + name);
  });
  if (wholeBody && scenePaths.has(wholeBody)) scenes[unit] = wholeBody;
  else if (matching.length === 1) scenes[unit] = matching[0];
  else if (named.length === 1) scenes[unit] = named[0];
}
fs.writeFileSync(destination, JSON.stringify(scenes, null, 2) + '\n');
console.log('Native previews indexed:', Object.keys(scenes).length);
