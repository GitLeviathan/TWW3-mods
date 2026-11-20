import fs from 'node:fs';import assert from 'node:assert/strict';
import {packIndex,entryBytes} from './game-data.mjs';
const root='D:/Steam/steamapps/common/Total War WARHAMMER III/data/';
const paths=new Set();
for(const file of ['anim.pack','anim_3.pack']){
 for(const entry of packIndex(root+file).filter(e=>e.name.endsWith('.animpack'))){
  const b=entryBytes(entry);let p=4;
  for(let i=0;i<b.readUInt32LE(0);i++){
   const len=b.readUInt16LE(p);p+=2;paths.add(b.toString('utf8',p,p+len).replaceAll('\\','/').toLowerCase());p+=len;
   const size=b.readUInt32LE(p);p+=4+size;
  }assert.equal(p,b.length,'Animation archive boundary');
 }
}
fs.writeFileSync(new URL('./native-animation-paths.json',import.meta.url),JSON.stringify([...paths]));
console.log('Indexed animation assets:',paths.size);
