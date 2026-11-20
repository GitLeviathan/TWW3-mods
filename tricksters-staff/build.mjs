import fs from 'node:fs';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const root='D:/Steam/steamapps/common/Total War WARHAMMER III/data/';
const staff='wh3_dlc24_anc_arcane_item_the_tricksters_staff';
const output=fileURLToPath(new URL('./tricksters_staff_transfer_settlement.pack',import.meta.url));
function unpack(b) {
  assert.equal(b.toString('ascii',0,4),'PFH5');
  let p=28+b.readUInt32LE(12),off=p+b.readUInt32LE(20);const entries=new Map();
  for(let i=0;i<b.readUInt32LE(16);i++){
    const len=b.readUInt32LE(p),end=b.indexOf(0,p+5),name=b.toString('utf8',p+5,end);
    let data=b.subarray(off,off+len);if(b[p+4])data=zlib.zstdDecompressSync(data.subarray(4));
    entries.set(name,data);p=end+1;off+=len;
  }
  assert.equal(off,b.length);return entries;
}
function decode(b,fields) {
  let p=0,version=0;
  if(b.readUInt32LE(p)===0xfffcfefd){p+=4;p+=2+b.readUInt16LE(p)*2;}
  if(b.readUInt32LE(p)===0xfffefdfc){p+=4;version=b.readUInt32LE(p);p+=4;}
  assert.equal(b[p++],1);const count=b.readUInt32LE(p);p+=4;
  const str=()=>{const n=b.readUInt16LE(p);p+=2;const s=b.toString('utf8',p,p+n);p+=n;return s;};
  const rows=[];
  for(let i=0;i<count;i++){
    const row={};for(const [name,type] of fields){
      if(type==='s')row[name]=str();
      else if(type==='o')row[name]=b[p++]?str():null;
      else if(type==='i'){row[name]=b.readInt32LE(p);p+=4;}
      else if(type==='f'){row[name]=b.readFloatLE(p);p+=4;}
      else throw Error(type);
    }rows.push(row);
  }
  assert.equal(p,b.length);return {rows,version};
}
const S=s=>{const b=Buffer.from(s);const h=Buffer.alloc(2);h.writeUInt16LE(b.length);return Buffer.concat([h,b]);};
const I=n=>{const b=Buffer.alloc(4);b.writeInt32LE(n);return b;};
const F=n=>{const b=Buffer.alloc(4);b.writeFloatLE(n);return b;};
const O=s=>s===null?Buffer.from([0]):Buffer.concat([Buffer.from([1]),S(s)]);
function table(rows){return Buffer.concat([Buffer.from([1]),I(rows.length),...rows]);}
function loc(rows){
  const str=s=>{const b=Buffer.from(s,'utf16le');const h=Buffer.alloc(2);h.writeUInt16LE(b.length/2);return Buffer.concat([h,b]);};
  return Buffer.concat([Buffer.from('fffe4c4f430001000000','hex'),I(rows.length),...rows.map(([k,v])=>Buffer.concat([str(k),str(v),Buffer.from([0])]))]);
}
function pack(entries){
  const h=Buffer.alloc(28);h.write('PFH5');h.writeUInt32LE(3,4);h.writeUInt32LE(entries.size,16);
  const index=Buffer.concat([...entries].map(([name,data])=>Buffer.concat([I(data.length),Buffer.from([0]),Buffer.from(name+'\0')])));
  h.writeUInt32LE(index.length,20);return Buffer.concat([h,index,...entries.values()]);
}
const db=unpack(fs.readFileSync(root+'db.pack'));
const ritualFields=[['key','s'],['cast','i'],['payload','s'],['cooldown','i'],['category','s'],['slave','i'],['global','i'],['start','o'],['icon','o'],['failure','i'],['required','o'],['expanded','o'],['target','o'],['target_expanded','o'],['target_required','o'],['target_cooldown','i'],['target_category_cooldown','i'],['effects','o'],['cost','o'],['vo','o'],['flags','s'],['self','o'],['increase','f'],['sort','i'],['influence','i'],['max','i']];
const rituals=decode(db.get('db\\rituals_tables\\data__'),ritualFields);assert.equal(rituals.version,4);
const categories=decode(db.get('db\\campaign_group_diplomatic_manipulation_category_junctions_tables\\data__'),[['group','s'],['category','s'],['cost','o'],['corruption','s'],['cooldown','i'],['excluded','o'],['factor','s'],['excluded_factions','o']]);
const ritualKeys=[
  'wh3_dlc24_ritual_tze_cotw_the_changeling_spread_corruption',
  'wh3_main_ritual_tze_cotw_track_army',
  'wh3_main_ritual_tze_cotw_force_rebellion',
  'wh3_main_ritual_tze_cotw_halt_faction',
  'wh3_main_ritual_tze_cotw_open_gates',
];
const diplomaticKeys=['break_alliance','force_peace','transfer_settlement','force_war'];
const effects=[],ancillaries=[],ritualLinks=[],diplomaticLinks=[],texts=[],report=[];
function add(kind,key,bonus,base){
  const effect='tww3_staff_one_turn_'+key.split('_').slice(-3).join('_')+'_'+bonus;
  assert(!effects.some(x=>x.key===effect));
  const visible=effects.length===0;
  effects.push({key:effect,visible});
  ancillaries.push(Buffer.concat([S(staff),S(effect),S('character_to_faction_unseen'),F(1-base)]));
  (kind==='ritual'?ritualLinks:diplomaticLinks).push(Buffer.concat(kind==='ritual'?[S(bonus),S(effect),S(key)]:[S(bonus),S(key),S(effect)]));
  texts.push(['effects_description_'+effect,visible?'Восстановление всех Великих перемен: 1 ход':'']);
  report.push({kind,key,bonus,base,modifier:1-base,result:base+(1-base)});
}
for(const key of ritualKeys){
  const r=rituals.rows.find(r=>r.key===key);assert(r,key);assert.equal(r.global,0);
  add('ritual',key,'cooldown_mod',r.cooldown);
  if(r.target_cooldown>0)add('ritual',key,'performer_target_cooldown_mod',r.target_cooldown);
  assert.equal(r.target_category_cooldown,0);
}
for(const key of diplomaticKeys){
  const matches=categories.rows.filter(r=>r.category===key);
  assert(matches.length>0,key);assert.equal(new Set(matches.map(r=>r.cooldown)).size,1,'Campaign cooldowns differ');
  add('diplomatic',key,'cooldown_mod',matches[0].cooldown);
}
assert.equal(new Set(report.map(r=>r.key)).size,9);assert(report.every(r=>r.result===1));
assert(!report.some(r=>r.key==='wh3_main_ritual_tze_cotw_reveal_shroud'));
const entries=new Map([
 ['db\\effects_tables\\tricksters_staff_transfer_settlement',table(effects.map(e=>Buffer.concat([S(e.key),O(e.visible?'turns.png':null),I(e.visible?106:0),O(e.visible?'turns.png':null),S('campaign'),Buffer.from([0])])) )],
 ['db\\ancillary_to_effects_tables\\tricksters_staff_transfer_settlement',table(ancillaries)],
 ['db\\effect_bonus_value_ritual_junctions_tables\\tricksters_staff_transfer_settlement',table(ritualLinks)],
 ['db\\effect_bonus_value_diplomacy_manipulation_category_junctions_tables\\tricksters_staff_transfer_settlement',table(diplomaticLinks)],
 // Preserve the installed description exactly, including hidden localization rows.
 ['text\\db\\tricksters_staff_transfer_settlement.loc',fs.readFileSync(new URL('./staff-description.loc',import.meta.url))],
]);
const result=pack(entries), reread=unpack(result);
for(const [key,value] of entries)assert.deepEqual(reread.get(key),value);
const written=decode(reread.get('db\\ancillary_to_effects_tables\\tricksters_staff_transfer_settlement'),[['ancillary','s'],['effect','s'],['scope','s'],['value','f']]);
assert.equal(written.rows.length,report.length);assert(written.rows.every(r=>r.ancillary===staff));
fs.writeFileSync(output,result);
const hash=crypto.createHash('sha256').update(result).digest('hex');
fs.writeFileSync(new URL('./build-report.json',import.meta.url),JSON.stringify({sha256:hash,actions:9,excluded:'wh3_main_ritual_tze_cotw_reveal_shroud',descriptionPreserved:true,rows:report},null,2)+'\n');
console.log(JSON.stringify({output,sha256:hash,actions:9,rows:report},null,2));
