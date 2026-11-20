import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';
import {packIndex,entryBytes,decode} from './game-data.mjs';
const root='D:/Steam/steamapps/common/Total War WARHAMMER III/data';
const active=[...fs.readFileSync('C:/Users/moroz/AppData/Roaming/The Creative Assembly/Warhammer3/logs/modified.log','utf8').matchAll(/^Mod: (.+)$/gm)].map(m=>m[1].trim());
const paths=[];function walk(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())walk(p);else if(e.name.endsWith('.pack'))paths.push(p);}}
walk('D:/Steam/steamapps/workshop/content/1142710');
const local=fs.readdirSync(root).filter(n=>n.endsWith('.pack')).map(n=>path.join(root,n));
const native=local.filter(p=>!active.includes(path.basename(p))&&!path.basename(p).startsWith('@')&&!path.basename(p).startsWith('00_'));
const mods=active.toReversed().map(n=>local.find(p=>path.basename(p)===n)??paths.find(p=>path.basename(p)===n)).filter(Boolean);
const tables=['main_units','land_units','unit_variants','variants','battle_animations_table','battle_entities'];
const data=Object.fromEntries(tables.map(t=>[t,new Map()])), assets=new Map(), diagnostics=[];
const animationPaths=new Set(JSON.parse(fs.readFileSync(new URL('./native-animation-paths.json',import.meta.url))));
for(const file of [...native,...mods])for(const e of packIndex(file)){
 const n=e.name.toLowerCase().replaceAll('\\','/');
 if(n.endsWith('.variantmeshdefinition'))assets.set(path.posix.basename(n),e.name.replaceAll('\\','/'));
 if(n.endsWith('.anim'))animationPaths.add(n);
 const t=tables.find(t=>e.name.startsWith(`db\\${t}_tables\\`));if(t){
  const rows=decode(e);for(const r of rows){const k=t==='main_units'?r.unit:t==='variants'?r.variant_name:t==='unit_variants'?`${r.unit}:${r.faction??''}`:r.key;data[t].set(k,r);}
 }
 // Custom skeleton animation paths may live inside small mod animation archives.
 if(mods.includes(file)&&n.endsWith('.animpack')){const b=entryBytes(e);let p=4;for(let i=0;i<b.readUInt32LE(0);i++){const len=b.readUInt16LE(p);p+=2;const s=b.toString('utf8',p,p+len);p+=len;const size=b.readUInt32LE(p);p+=4;animationPaths.add(s.replaceAll('\\','/').toLowerCase());p+=size;}}
}
const clips=[...animationPaths].filter(n=>n.endsWith('.anim')&&n.includes('/stand/')&&!/porthole|affirmative/.test(n));
const models={};
for(const main of data.main_units.values()){
 if(!['lord','hero'].includes(main.caste))continue;
 const land=data.land_units.get(main.land_unit);if(!land)continue;
 const uv=data.unit_variants.get(`${main.unit}:`)??[...data.unit_variants.values()].find(r=>r.unit===main.unit);
 const variant=uv&&data.variants.get(uv.variant);const skeleton=data.battle_animations_table.get(land.man_animation)?.skeleton;
 const file=variant?.variant_filename?.replaceAll('\\','/');const asset=file&&assets.get(path.posix.basename(file.endsWith('.variantmeshdefinition')?file:file+'.variantmeshdefinition').toLowerCase());
 if(!asset||!skeleton){diagnostics.push({key:main.unit,reason:!asset?'model missing':'skeleton missing'});continue;}
 const words=(land.man_animation??'').split('_').filter(s=>s.length>2);
 const compatible=clips.filter(n=>n.includes('/'+skeleton.toLowerCase()+'/'));
 function score(n){return words.reduce((s,w)=>s+(n.includes(w)?4:0),0)+(n.endsWith('_stand_01.anim')?10:0)-(n.includes('idle')?2:0)-(n.includes('/rider/')&&!land.mount?100:0);}
 compatible.sort((a,b)=>score(b)-score(a)||a.localeCompare(b));
 const entity=data.battle_entities.get(land.man_entity);const height=Math.max(1.5,Number(entity?.height??2));
 models[main.unit]={asset,skeleton,animation:compatible[0]??null,height,variant:uv.variant};
}
fs.writeFileSync(new URL('./model-manifest.json',import.meta.url),JSON.stringify({models,unsupported:diagnostics,activeMods:active},null,2));
console.log('Models resolved:',Object.keys(models).length,'unsupported:',diagnostics.length);
for(const key of ['wh2_main_hef_cha_tyrion_0','wh_dlc05_wef_cha_orion_0','wh2_main_lzd_cha_lord_mazdamundi_0'])console.log(key,models[key]);
