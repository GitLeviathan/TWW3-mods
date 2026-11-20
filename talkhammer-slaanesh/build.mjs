import { readFile, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

function unpack(data) {
  assert.equal(data.toString('ascii',0,4),'PFH5');
  let index=28+data.readUInt32LE(12), offset=index+data.readUInt32LE(20);
  const entries=new Map();
  for(let i=0;i<data.readUInt32LE(16);i++) {
    const size=data.readUInt32LE(index), compressed=data[index+4];
    const end=data.indexOf(0,index+5);
    assert(end>=index+5 && offset+size<=data.length);
    entries.set(data.toString('utf8',index+5,end),{content:data.subarray(offset,offset+size),compressed});
    index=end+1;offset+=size;
  }
  assert.equal(offset,data.length);
  return entries;
}
function pack(entries) {
  const header=Buffer.alloc(28);header.write('PFH5');header.writeUInt32LE(3,4);
  header.writeUInt32LE(entries.size,16);
  const index=Buffer.concat([...entries].map(([name,entry])=>{
    const meta=Buffer.alloc(5);meta.writeUInt32LE(entry.content.length);meta[4]=entry.compressed;
    return Buffer.concat([meta,Buffer.from(name+'\0')]);
  }));
  header.writeUInt32LE(index.length,20);
  return Buffer.concat([header,index,...[...entries.values()].map(e=>e.content)]);
}
const stockPath=process.argv[2]??'D:/Steam/steamapps/workshop/content/1142710/3808547073/talkhammer.pack';
const stock=unpack(await readFile(stockPath)), entries=new Map();
const policy=await readFile(new URL('./slaanesh-policy.lua',import.meta.url),'utf8');
const policyPath='script\\talkhammer\\lib\\slaanesh_policy.lua';
const dispositionPath='script\\talkhammer\\lib\\disposition.lua';
const rulerPath='script\\talkhammer\\lib\\ruler.lua';
const embed='(function()\n'+policy+'\nend)()';
const source=stock.get(dispositionPath);
assert(source && !source.compressed);
const jsonSource=stock.get('script\\talkhammer\\lib\\json.lua');
assert(jsonSource && !jsonSource.compressed, 'Expected the stock JSON decoder');
let disposition=source.content.toString('utf8');
const upper='if points >  40 then points =  40 end';
assert.equal(disposition.split(upper).length,2);
disposition=disposition.replace(upper,'if points > 200 then points = 200 end');
assert.equal(disposition.split('local disposition = {}').length,2);
disposition=disposition.replace('local disposition = {}',`local disposition = {}
local slaanesh_policy = ${embed}
-- main.lua's loader is private. Embed its exact decoder instead of relying on a global.
local policy_json = (function()
${jsonSource.content.toString('utf8')}
end)()`);
const scoreHook='parts.raw = score';
assert.equal(disposition.split(scoreHook).length,2);
disposition=disposition.replace(scoreHook,`-- Apply the exact stage bonus after cultural attenuation and all other terms.
local stage_ok, stage = pcall(slaanesh_policy.resolve, cm, policy_json, them_key, you_key)
if stage_ok and stage and stage.bonus ~= 0 then
    add(stage.bonus, "Slaanesh Expanded corruption stage " .. tostring(stage.level))
    parts.corruption = stage.bonus
end
${scoreHook}`);
const oldRuler=stock.get(rulerPath);
assert(oldRuler && !oldRuler.compressed);
let ruler=oldRuler.content.toString('utf8');
const ask='local function ask(speaker_key, personality, user_text, on_decision, player_dialogue)';
const requestStart=ruler.indexOf('local request = {',ruler.indexOf(ask));
assert(requestStart>=0 && ruler.split(ask).length===2);
const stage=['','local stage_instruction = ""','if apply_slaanesh_stage then',
    '    local ok, block = pcall(slaanesh_stage, cm, json, log, speaker_key)',
    '    if ok and block then stage_instruction = "\\n\\n" .. block end',
    '    if not ok then log("SLAANESH|stage lookup failed: " .. tostring(block)) end','end',''].join('\n');
const wrapper=`local slaanesh_stage = (function()
    local policy = ${embed}
    return function(cm, json, log, speaker_key, config_path)
        local player_key = cm:get_local_faction_name(true)
        local context = policy.resolve(cm, json, speaker_key, player_key, config_path)
        if not context then return end
        log("SLAANESH|" .. speaker_key .. " level=" .. context.level
            .. " bonus=" .. context.bonus .. " player_vassal=" .. tostring(context.isPlayerVassal)
            .. " require_agreement=" .. tostring(context.requireAgreement))
        return policy.instruction(context)
    end
end)()
`;
ruler=(ruler.slice(0,requestStart)+stage+ruler.slice(requestStart))
    .replace(ask,wrapper+ask.slice(0,-1)+', apply_slaanesh_stage)')
    .replace(/\.\. reply_style(\r?\n)/g,'.. reply_style$1.. stage_instruction$1')
    .replace(/\r?\nend, text\)(?=\r?\nend\)\r?\nend)/,'\nend, text, true)');
assert(ruler.includes('end, text, true)'));
// Preserve the currently installed adapter against the newer Workshop ruler API.
// This small, hash-guarded delta contains only the version differences, not a copy
// of the upstream TalkHammer module or a private backup pack.
const adjustments=JSON.parse(await readFile(new URL('./installed-version-adjustments.json',import.meta.url),'utf8'));
assert.equal(createHash('sha256').update(ruler).digest('hex'),adjustments.sourceSha256,'TalkHammer ruler version changed');
for(const change of adjustments.changes.toReversed()){
    ruler=ruler.slice(0,change.start)+change.new+ruler.slice(change.end);
}
assert.equal(createHash('sha256').update(ruler).digest('hex'),adjustments.resultSha256);
entries.set(rulerPath,{content:Buffer.from(ruler),compressed:0});
entries.set(dispositionPath,{content:Buffer.from(disposition),compressed:0});
entries.set(policyPath,{content:Buffer.from(policy),compressed:0});
const result=pack(entries), decoded=unpack(result);
for(const [key,value] of entries)assert.deepEqual(decoded.get(key),value);
const output=fileURLToPath(new URL('./00_talkhammer_slaanesh_diplomacy.pack',import.meta.url));
await writeFile(output,result);
console.log(output);
console.log('SHA256',createHash('sha256').update(result).digest('hex'));
