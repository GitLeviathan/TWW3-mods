import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { moviePack, readEntry } from '../mod-tools/pack.mjs';

const stock = 'D:/Steam/steamapps/workshop/content/1142710/3808547073/talkhammer.pack';
const defaultOutput = fileURLToPath(new URL('./00_talkhammer_diplomacy_expansion.pack', import.meta.url));
const [base = stock, output = defaultOutput] = process.argv.slice(2);
const rulerPath = 'script\\talkhammer\\lib\\ruler.lua';
const source = readEntry(base, rulerPath).toString('utf8');
const module = (await readFile(new URL('./settlement-gifts.lua', import.meta.url), 'utf8')).trimEnd();
const influence = (await readFile(new URL('./vassal-influence.lua', import.meta.url), 'utf8')).trimEnd();

function activate(text, pattern, replacement) {
  const matches = text.matchAll(new RegExp(pattern.source, pattern.flags.replace('g', '') + 'g'));
  assert.equal([...matches].length, 1, 'Expected one TalkHammer hook: ' + pattern.source);
  return text.replace(pattern, replacement);
}

let ruler = source;
const askStart = ruler.indexOf('local function ask(');
const askEnd = ruler.indexOf('response_format = response_schema(', askStart);
assert(askEnd > askStart);
let ask = ruler.slice(askStart, askEnd);
ask = activate(ask, /^local function ask\(([^\r\n]+)\)$/m,
  (_line, args) => 'local diplomacy_expansion\nlocal function ask(' + args + ', expansion_proposal)');
ask = activate(ask, /^(\.\. language_rule)$/m,
  '$1\n.. diplomacy_expansion.prompt(expansion_proposal)');
ruler = ruler.slice(0, askStart) + ask + ruler.slice(askEnd);
ruler = activate(ruler, /^response_format = (response_schema\([^)\r\n]*\)),$/m,
  (_line, schema) => 'response_format = diplomacy_expansion.schema(' + schema + ', expansion_proposal),');

const talkStart = ruler.indexOf('function ruler.talk_to(faction_key, text)');
const talkEnd = ruler.indexOf('function ruler.take_turn(trigger)', talkStart);
assert(talkStart >= 0 && talkEnd > talkStart);
let talk = ruler.slice(talkStart, talkEnd);
talk = activate(talk, /^ruler\.awaiting\[faction_key\] = os\.clock\(\)$/m, `local expansion_proposal, expansion_error = diplomacy_expansion.prepare(faction_key, text, me.key, me.turn)
if expansion_error then
    state.remember(faction_key, me.turn, expansion_error, "note", { short = expansion_error })
    ruler.show_conversation(faction_key)
    ruler.publish_status(nil, { activity = expansion_error })
    return
end
ruler.awaiting[faction_key] = os.clock()`);
talk = activate(talk, /^deliver\(faction_key, them, decision\)$/m, `if expansion_proposal then
    return diplomacy_expansion.finish(expansion_proposal, decision)
end
deliver(faction_key, them, decision)`);
talk = activate(talk, /^end, text([^\r\n]*)\)$/m,
  (_line, args) => 'end, text' + args + ', expansion_proposal)');
ruler = ruler.slice(0, talkStart) + talk + ruler.slice(talkEnd);

ruler = activate(ruler, /^ok, note, why_code = ruler\.settle\(key, true, me\)$/m,
  'ok, note, why_code = ruler.settle(key, true, me, spec.expansion and spec.print or nil)');

ruler = activate(ruler, /^return ruler\s*$/m, `do
local expansion = (function()
${module}
end)()
local influence = (function()
${influence}
end)()
local init = ruler.init
ruler.init = function(deps)
    init(deps)
    diplomacy_expansion = expansion.install({
        cm = cm, core = core, ruler = ruler, state = state, world = world, actions = actions, influence = influence,
        localise = function(key) return common.get_localised_string(key) end,
        fold = u8.fold,
        language = function() return TALKHAMMER_LANG and TALKHAMMER_LANG.code end,
        transcript = add_transcript,
        speak = function(key, line)
            if not (p2 and p2.speak) then return end
            local voice = ruler.voice_id
            if not voice and voices then
                local ok, assigned = pcall(voices.for_faction, key)
                if ok then voice = assigned end
            end
            pcall(p2.speak, line, voice)
        end,
    })
end
end

return ruler
`);

const entries = new Map([[rulerPath, Buffer.from(ruler, 'utf8')]]);
const pack = moviePack(entries);
pack.writeUInt32LE(3, 4); // Selectable Mod pack.
await writeFile(output, pack);
assert.deepEqual(readEntry(output, rulerPath), entries.get(rulerPath));
console.log(output);
console.log('SHA256', createHash('sha256').update(pack).digest('hex'));
