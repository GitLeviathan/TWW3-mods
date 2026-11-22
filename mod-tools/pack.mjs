import fs from 'node:fs';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';
export function readEntry(file,wanted){
 const b=fs.readFileSync(file);assert.equal(b.toString('ascii',0,4),'PFH5');
 let p=28+b.readUInt32LE(12),o=p+b.readUInt32LE(20);
 for(let i=0;i<b.readUInt32LE(16);i++){
  const n=b.readUInt32LE(p),end=b.indexOf(0,p+5),name=b.toString('utf8',p+5,end);
  assert(end>=p+5&&o+n<=b.length);
  if(name===wanted)return b[p+4]?zlib.zstdDecompressSync(b.subarray(o+4,o+n)):b.subarray(o,o+n);
  p=end+1;o+=n;
 }throw Error('Missing entry: '+wanted);
}
function buildPack(entries,type){
 const h=Buffer.alloc(28);h.write('PFH5');h.writeUInt32LE(type,4);h.writeUInt32LE(entries.size,16);
 const index=Buffer.concat([...entries].map(([name,data])=>{const m=Buffer.alloc(5);m.writeUInt32LE(data.length);return Buffer.concat([m,Buffer.from(name+'\0')]);}));
 h.writeUInt32LE(index.length,20);return Buffer.concat([h,index,...entries.values()]);
}
export function moviePack(entries){return buildPack(entries,4);}
export function modPack(entries){return buildPack(entries,3);}
