import fs from 'node:fs';
const target=new URL('./schema_wh3.ron',import.meta.url);
if(!fs.existsSync(target)){
 const url='https://raw.githubusercontent.com/Frodo45127/rpfm-schemas/master/schema_wh3.ron';
 const response=await fetch(url);
 if(!response.ok)throw Error(`Schema download failed: ${response.status}`);
 fs.writeFileSync(target,await response.text());
}
console.log('DB schema ready. Run index-animations.mjs and build-assets.mjs to refresh the model manifest.');
