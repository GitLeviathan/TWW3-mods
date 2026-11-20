import fs from 'node:fs';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';
const schema=fs.readFileSync(new URL('./schema_wh3.ron',import.meta.url),'utf8');
export function packIndex(file){
 const fd=fs.openSync(file,'r'), h=Buffer.alloc(28);fs.readSync(fd,h,0,28,0);
 if(h.toString('ascii',0,4)!=='PFH5'){fs.closeSync(fd);return [];}
 const idx=Buffer.alloc(h.readUInt32LE(20));fs.readSync(fd,idx,0,idx.length,28+h.readUInt32LE(12));
 let p=0,o=28+h.readUInt32LE(12)+idx.length;const list=[];
 for(let i=0;i<h.readUInt32LE(16);i++){const size=idx.readUInt32LE(p),end=idx.indexOf(0,p+5),name=idx.toString('utf8',p+5,end);list.push({file,name,size,offset:o,compressed:!!idx[p+4]});o+=size;p=end+1;}
 fs.closeSync(fd);return list;
}
export function entryBytes(e){const fd=fs.openSync(e.file,'r'),b=Buffer.alloc(e.size);try{fs.readSync(fd,b,0,b.length,e.offset);}finally{fs.closeSync(fd);}if(!e.compressed)return b;
 if(b.readUInt32LE(4)!==0x184d2204)return zlib.zstdDecompressSync(b.subarray(4));
 const out=Buffer.alloc(b.readUInt32LE(0));let p=10,q=0;const flg=b[8]; // Frame starts at offset 4, FLG at 8.
 if(flg&8)p+=8;if(flg&1)p+=4;p++; // magic, FLG, BD, optional fields, HC
 while(true){const n=b.readUInt32LE(p);p+=4;if(!n)break;const end=p+(n&0x7fffffff);
  if(n&0x80000000){b.copy(out,q,p,end);q+=end-p;p=end;}
  else while(p<end){const token=b[p++];let literals=token>>>4;if(literals===15){let v;do{v=b[p++];literals+=v;}while(v===255);}b.copy(out,q,p,p+literals);p+=literals;q+=literals;if(p>=end)break;const distance=b.readUInt16LE(p);p+=2;assert(distance>0&&distance<=q);let length=(token&15)+4;if((token&15)===15){let v;do{v=b[p++];length+=v;}while(v===255);}for(let i=0;i<length;i++)out[q+i]=out[q+i-distance];q+=length;}
  assert.equal(p,end);if(flg&16)p+=4;
 }assert.equal(q,out.length);return out;
}
export function decode(e){
 const b=entryBytes(e);let p=0,version=0;
 if(b.readUInt32LE(p)===0xfffcfefd){p+=4;p+=2+b.readUInt16LE(p)*2;}
 if(b.readUInt32LE(p)===0xfffefdfc){p+=4;version=b.readUInt32LE(p);p+=4;}
 assert.equal(b[p++],1);const count=b.readUInt32LE(p);p+=4;
 const table=e.name.split('\\')[1];let s=schema.slice(schema.indexOf(`"${table}": [`));
 assert(s.includes(`version: ${version},`),`${table} v${version}`);s=s.slice(s.indexOf(`version: ${version},`));s=s.slice(0,s.indexOf('localised_fields:'));
 const fields=[...s.matchAll(/name: "([^"]+)",\s+field_type: (\w+)/g)].map(m=>[m[1],m[2]]);
 function read(t){if(t.startsWith('Optional'))return b[p++]?read(t.slice(8)):null;
  if(t==='StringU8'){const n=b.readUInt16LE(p);p+=2;const s=b.toString('utf8',p,p+n);p+=n;return s;}
  if(t==='Boolean')return !!b[p++];
  if(t==='I32'){const v=b.readInt32LE(p);p+=4;return v;}if(t==='I64'){const v=Number(b.readBigInt64LE(p));p+=8;return v;}
  if(t==='F32'){const v=b.readFloatLE(p);p+=4;return v;}throw Error(`${table}: ${t}`);
 }
 const rows=Array.from({length:count},()=>Object.fromEntries(fields.map(([name,type])=>[name,read(type)])));
 assert.equal(p,b.length,`${table} decode boundary`);return rows;
}
