import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { moviePack, readEntry } from '../mod-tools/pack.mjs';

const dataDirectory = process.argv[2] ?? 'D:/Steam/steamapps/common/Total War WARHAMMER III/data';
const table = 'db\\settlement_type_to_building_chains_junctions_tables\\';
const vanilla = readEntry(path.join(dataDirectory, 'db.pack'), `${table}data__`);
const referenceType = 'wh3_dlc23_chd_factory';
const targetTypes = ['wh3_dlc29_chs_altar', 'wh3_dlc29_chs_dark_fortress'];

function readRows(bytes) {
  let offset = 0;
  if (bytes.readUInt32LE(offset) === 0xfffcfefd) {
    offset = 6 + bytes.readUInt16LE(4) * 2;
  }
  assert.equal(bytes.readUInt32LE(offset), 0xfffefdfc);
  assert.equal(bytes.readUInt32LE(offset + 4), 1, 'Unsupported building junction table version');
  assert.equal(bytes[offset + 8], 1);
  const count = bytes.readUInt32LE(offset + 9);
  offset += 13;
  function readString() {
    const length = bytes.readUInt16LE(offset);
    offset += 2;
    const value = bytes.toString('utf8', offset, offset + length);
    offset += length;
    return value;
  }
  const rows = [];
  for (let index = 0; index < count; index++) {
    const buildingChain = readString();
    const settlementType = readString();
    const exclude = bytes[offset++];
    assert(exclude === 0 || exclude === 1);
    rows.push({ buildingChain, settlementType, exclude });
  }
  assert.equal(offset, bytes.length);
  return rows;
}

function encodeString(text) {
  const value = Buffer.from(text);
  const size = Buffer.alloc(2);
  size.writeUInt16LE(value.length);
  return Buffer.concat([size, value]);
}

const stockRows = readRows(vanilla);
// The game already permits every Changeling cult chain in this special settlement type.
const chains = [...new Set(stockRows
  .filter(row => row.settlementType === referenceType && row.exclude === 0 &&
    row.buildingChain.startsWith('wh3_dlc24_tze_the_changeling_'))
  .map(row => row.buildingChain))].sort();
assert.equal(chains.length, 16, 'The installed game has a different set of cult chains');
const rows = [];
for (const settlementType of targetTypes) {
  assert(stockRows.some(row => row.settlementType === settlementType), `Unknown settlement type ${settlementType}`);
  for (const buildingChain of chains) {
    const existing = stockRows.find(row => row.settlementType === settlementType && row.buildingChain === buildingChain);
    assert(existing?.exclude !== 1, `The installed game explicitly excludes ${buildingChain} in ${settlementType}`);
    if (!existing) rows.push({ buildingChain, settlementType, exclude: 0 });
  }
}
assert(rows.length > 0, 'The installed game already includes all cult permissions');

const header = Buffer.alloc(13);
header.writeUInt32LE(0xfffefdfc);
header.writeUInt32LE(1, 4);
header[8] = 1;
header.writeUInt32LE(rows.length, 9);
const payload = Buffer.concat([header, ...rows.map(row => Buffer.concat([
  encodeString(row.buildingChain), encodeString(row.settlementType), Buffer.from([row.exclude]),
]))]);
const entry = `${table}tww3_changeling_chaos_cult_construction`;
const pack = moviePack(new Map([[entry, payload]]));
const output = new URL('changeling_chaos_cult_construction.pack', import.meta.url);
fs.writeFileSync(output, pack);
assert.deepEqual(readRows(readEntry(output, entry)), rows);
console.log(JSON.stringify({ rows: rows.length, types: targetTypes,
  sha256: createHash('sha256').update(pack).digest('hex') }, null, 2));
