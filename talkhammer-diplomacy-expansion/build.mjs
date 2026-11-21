import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { moviePack, readEntry } from '../mod-tools/pack.mjs';
import { addGiftPanel } from './gift-layout.mjs';

const stock = 'D:/Steam/steamapps/workshop/content/1142710/3808547073/talkhammer.pack';
const defaultOutput = fileURLToPath(new URL('./00_talkhammer_diplomacy_expansion.pack', import.meta.url));
const [base = stock, output = defaultOutput, mainBase = stock] = process.argv.slice(2);
const rulerPath = 'script\\talkhammer\\lib\\ruler.lua';
const mainPath = 'script\\talkhammer\\main.lua';
const layoutPath = 'ui\\talkhammer\\th_panel.twui.xml';
const pickerPath = 'script\\talkhammer\\lib\\gift_panel.lua';
const jsonPath = 'script\\talkhammer\\lib\\json.lua';
const source = readEntry(base, rulerPath).toString('utf8');
const module = (await readFile(new URL('./settlement-gifts.lua', import.meta.url), 'utf8')).trimEnd();
const influence = (await readFile(new URL('./vassal-influence.lua', import.meta.url), 'utf8')).trimEnd();
const protectedOutput = (await readFile(new URL('./protected-output.lua', import.meta.url), 'utf8')).trimEnd();
const picker = await readFile(new URL('./gift-panel.lua', import.meta.url));

function activate(text, pattern, replacement) {
  const matches = text.matchAll(new RegExp(pattern.source, pattern.flags.replace('g', '') + 'g'));
  assert.equal([...matches].length, 1, 'Expected one TalkHammer hook: ' + pattern.source);
  return text.replace(pattern, replacement);
}

let main = readEntry(mainBase, mainPath).toString('utf8');
main = activate(main, /^local function log\(msg\) if out then out\(TAG \.\. tostring\(msg\)\) end end$/m, `local safe_out, talkhammer_environment = (function()
${protectedOutput}
end)()(getfenv(1), function(why, message)
    local file = io.open("talkhammer_data/expansion.log", "a")
    if not file then return end
    file:write(os.date("%H:%M:%S"), " [", tostring(why), "] ", tostring(message), "\\n")
    file:close()
end)
local function log(msg) safe_out(TAG .. tostring(msg)) end
log("DIPLOMACY|Expansion test.4")`);
main = activate(main, /^local env_ok, env_why = pcall\(setfenv, chunk, getfenv\(1\)\)$/m,
  'local env_ok, env_why = pcall(setfenv, chunk, talkhammer_environment)');
if (main.includes('mask.install')) {
  main = activate(main, /^        if not ok then log\("MASK\|install failed: " \.\. tostring\(error\)\) end$/m, `$&
        if ok then
            ruler.expansion_mask_active = function()
                return cm:get_local_faction_name(true) == "wh3_dlc24_tze_the_deceivers"
                    and state.setting("changeling_mask_enabled", true)
            end
        end`);
}
main = activate(main, /^voices\.load\(function\(ok\)$/m, `local gift_picker
if ui then
    local module = load_module("talkhammer/lib/gift_panel.lua")
    if module then
        local ok, result = pcall(module.install, { ui = ui, ruler = ruler, core = core,
            cm = cm, state = state, fold = u8.fold, language = function() return lang and lang.code end })
        if ok then gift_picker = result else log("EXPANSION|picker failed: " .. tostring(result)) end
    end
end
voices.load(function(ok)`);
main = activate(main, /^on_speak = function\(\)$/m,
  '$&\nif gift_picker and gift_picker.consume_speak() then return end');

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
talk = activate(talk, /^function ruler\.talk_to\(faction_key, text\)$/m, 'function ruler.talk_to(faction_key, text, selection)');
talk = activate(talk, /^ruler\.awaiting\[faction_key\] = os\.clock\(\)$/m, `local prepared, expansion_proposal, expansion_error = pcall(diplomacy_expansion.prepare, faction_key, text, me.key, me.turn, selection)
if not prepared then
    log("EXPANSION|prepare failed: " .. tostring(expansion_proposal))
    expansion_error = TALKHAMMER_LANG and TALKHAMMER_LANG.code == "ru"
        and "Не удалось проверить условия сделки. Подробности в журнале TalkHammer."
        or "The proposal could not be checked. See the TalkHammer log."
end
if expansion_error then
    log("EXPANSION|" .. tostring(expansion_error))
    state.remember(faction_key, me.turn, expansion_error, "note", { short = expansion_error })
    ruler.show_conversation(faction_key)
    ruler.publish_status(nil, { activity = expansion_error })
    return
end
ruler.awaiting[faction_key] = os.clock()`);
talk = activate(talk, /^deliver\(faction_key, them, decision\)$/m, `if expansion_proposal then
    log("EXPANSION|reply for " .. faction_key .. " gift=" .. tostring(decision.gift_agreed)
        .. " confederation=" .. tostring(decision.influence_agreed))
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

const layout = addGiftPanel(readEntry(mainBase, layoutPath).toString('utf8'));
let json = readEntry(stock, jsonPath).toString('utf8');
json = activate(json, /^local SUB = string\.sub$/m, 'local SUB = byte_sub');
json = activate(json, /^SUB = has_high\(s\) and byte_sub or string\.sub\r?\n/m, '');
json = activate(json, /NUM_CHARS\[string\.sub\(chars, k, k\)\]/, 'NUM_CHARS[byte_sub(chars, k, k)]');
json = activate(json, /elseif c == "-" or \(c >= "0" and c <= "9"\) then return parse_number\(s, i\)/,
  'elseif c == "-" or c:match("^%d$") then return parse_number(s, i)');
const entries = new Map([
  [mainPath, Buffer.from(main, 'utf8')], [rulerPath, Buffer.from(ruler, 'utf8')],
  [layoutPath, Buffer.from(layout, 'utf8')], [pickerPath, picker], [jsonPath, Buffer.from(json, 'utf8')],
]);
const pack = moviePack(entries);
pack.writeUInt32LE(3, 4); // Selectable Mod pack.
await writeFile(output, pack);
for (const [path, content] of entries) assert.deepEqual(readEntry(output, path), content);
console.log(output);
console.log('SHA256', createHash('sha256').update(pack).digest('hex'));
