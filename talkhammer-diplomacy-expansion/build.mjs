import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { moviePack, readEntry } from '../mod-tools/pack.mjs';
import { addGiftPanel } from './gift-layout.mjs';
import { verifyMaskLayout } from '../changeling-diplomacy/mask-layout.mjs';

const stock = 'D:/Steam/steamapps/workshop/content/1142710/3808547073/talkhammer.pack';
const defaultOutput = fileURLToPath(new URL('./00_talkhammer_diplomacy_expansion.pack', import.meta.url));
const [base = stock, output = defaultOutput, mainBase = stock] = process.argv.slice(2);
const rulerPath = 'script\\talkhammer\\lib\\ruler.lua';
const mainPath = 'script\\talkhammer\\main.lua';
const layoutPath = 'ui\\talkhammer\\th_panel.twui.xml';
const pickerPath = 'script\\talkhammer\\lib\\gift_panel.lua';
const jsonPath = 'script\\talkhammer\\lib\\json.lua';
const chroniclePath = 'script\\talkhammer\\lib\\chronicle.lua';
const russianPath = 'script\\talkhammer\\lib\\lang_ru.lua';
const source = readEntry(base, rulerPath).toString('utf8');
const module = (await readFile(new URL('./settlement-gifts.lua', import.meta.url), 'utf8')).trimEnd();
const influence = (await readFile(new URL('./vassal-influence.lua', import.meta.url), 'utf8')).trimEnd();
const natural = (await readFile(new URL('./natural-gifts.lua', import.meta.url), 'utf8')).trimEnd();
const services = await Promise.all([
  ['negotiation', 'negotiation.lua'],
  ['council', 'council-deadlines.lua'],
  ['military', 'military-tasks.lua'],
].map(async ([name, file]) =>
  'local ' + name + ' = (function()\n' + (await readFile(new URL('./' + file, import.meta.url), 'utf8')).trimEnd() + '\nend)()'));
const protectedOutput = (await readFile(new URL('./protected-output.lua', import.meta.url), 'utf8')).trimEnd();
const picker = await readFile(new URL('./gift-panel.lua', import.meta.url));
const giftChronicle = (await readFile(new URL('./gift-chronicle.lua', import.meta.url), 'utf8')).trimEnd();

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
log("DIPLOMACY|Expansion test.15")`);
main = activate(main, /^local env_ok, env_why = pcall\(setfenv, chunk, getfenv\(1\)\)$/m,
  'local env_ok, env_why = pcall(setfenv, chunk, talkhammer_environment)');
if (main.includes('mask.install')) {
  main = activate(main, /^        if not ok then log\("MASK\|install failed: " \.\. tostring\(error\)\) end$/m, `$&
        if ok then
            ruler.expansion_mask_active = function()
                return (ruler.mask_preview_active and ruler.mask_preview_active())
                    or (cm:get_local_faction_name(true) == "wh3_dlc24_tze_the_deceivers"
                        and state.setting("changeling_mask_enabled", true))
            end
        end`);
}
main = activate(main, /^voices\.load\(function\(ok\)$/m, `local gift_picker
if ui then
    local module = load_module("talkhammer/lib/gift_panel.lua")
    if module then
        local ok, result = pcall(module.install, { ui = ui, ruler = ruler, core = core,
            cm = cm, state = state, fold = u8.fold, index_of = u8.index_of, log = log,
            language = function() return lang and lang.code end })
        if ok then gift_picker = result else log("EXPANSION|picker failed: " .. tostring(result)) end
    end
end
voices.load(function(ok)`);
main = activate(main, /^on_speak = function\(\)$/m,
  '$&\nif gift_picker and gift_picker.consume_speak() then\n'
  + '    if ruler.mask_trace_input then ruler.mask_trace_input("gift_search") end\n'
  + '    return\nend');
main = activate(main, /^events\.init\(\{$/m, `if chronicle and chronicle.is_settlement_gift_event then
    local handle_event = events.handle
    events.handle = function(name, context)
        if name == "RegionFactionChangeEvent" and chronicle.is_settlement_gift_event(context) then return end
        return handle_event(name, context)
    end
end
events.init({`);

let ruler = source;
const askStart = ruler.indexOf('local function ask(');
const askEnd = ruler.indexOf('response_format = response_schema(', askStart);
assert(askEnd > askStart);
let ask = ruler.slice(askStart, askEnd);
ask = activate(ask, /^local function ask\(([^\r\n]+)\)$/m,
  (_line, args) => 'local diplomacy_expansion\nlocal function ask(' + args + ', expansion_proposal)');
ask = activate(ask, /^(\.\. language_rule)$/m,
  '$1\n.. diplomacy_expansion.prompt(expansion_proposal)\n.. (player_dialogue and diplomacy_expansion.context(speaker_key) or "")');
ruler = ruler.slice(0, askStart) + ask + ruler.slice(askEnd);
ruler = activate(ruler, /^response_format = (response_schema\([^)\r\n]*\)),$/m,
  (_line, schema) => 'response_format = diplomacy_expansion.schema(' + schema + ', expansion_proposal),');

const talkStart = ruler.indexOf('function ruler.talk_to(faction_key, text)');
const talkEnd = ruler.indexOf('function ruler.take_turn(trigger)', talkStart);
assert(talkStart >= 0 && talkEnd > talkStart);
let talk = ruler.slice(talkStart, talkEnd);
talk = activate(talk, /^function ruler\.talk_to\(faction_key, text\)$/m, 'function ruler.talk_to(faction_key, text, selection)');
talk = activate(talk, /^ruler\.awaiting\[faction_key\] = os\.clock\(\)$/m, `if not selection then
    local ok, handled = pcall(diplomacy_expansion.handle, faction_key, text, me.key, me.turn)
    if not ok then
        log("EXPANSION|order failed: " .. tostring(handled))
        ruler.last_error = T("note.no_answer", "No answer - say it again")
        return
    end
    if handled then ruler.publish_status(nil, { activity = "idle" }); return end
end
local prepared, expansion_proposal, expansion_error = pcall(diplomacy_expansion.prepare, faction_key, text, me.key, me.turn, selection)
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

ruler = activate(ruler, /^return ruler\s*$/m, () => `do
local expansion = (function()
${module}
end)()
local influence = (function()
${influence}
end)()
local natural = (function()
${natural}
end)()
${services.join('\n')}
local function ask_envoy(key, prompt, reply, correspondence)
    if not p2 or not p2.post or not p2.strict_format then return false end
    local language = TALKHAMMER_LANG and TALKHAMMER_LANG.code == "ru" and "Russian" or "the current interface language"
    local profile = state.character_of and state.character_of(key)
    local recent
    if correspondence and chronicle and chronicle.text then
        local ok, text = pcall(chronicle.text, key)
        if ok and type(text) == "string" and text ~= "" then recent = text end
    end
    local snapshot = ruler.snapshot(key)
    local player = cm:get_local_faction_name(true)
    local preferences = type(slaanesh_stage) == "function" and slaanesh_stage(cm, json, log, key) or nil
    local campaign, turn = state.data, cm:turn_number()
    local request = {
        messages = {
            { role = "system", content = "You are " .. ruler.identity(key) .. " in the Warhammer Fantasy Old World."
                .. " Answer in " .. language .. ", in character. Your reply represents only your own faction."
                .. " Express conditions or refusal honestly. No deal or war has happened just because you answer."
                .. (type(profile) == "string" and "\\n" .. profile or "")
                .. (snapshot and snapshot.ok and "\\n" .. ruler.describe(snapshot, player) or "")
                .. (recent and "\\nConfirmed campaign events:\\n" .. recent or "")
                .. (preferences and "\\n" .. preferences or "")
                .. "\\nReturn one short line, a verdict of accept/decline/counter, and an integer gold amount."
                .. " Only a permitted exact gold payment belongs in gold. Otherwise set gold to zero." },
            { role = "user", content = prompt },
        },
        response_format = p2.strict_format("court_reply", {
            type = "object", properties = {
                line = {type = "string"}, verdict = {type = "string", enum = {"accept", "decline", "counter"}},
                gold = {type = "integer"},
            },
            required = {"line", "verdict", "gold"}, additionalProperties = false,
        }),
    }
    local replied
    local function finish(line, decision)
        if replied then return end
        replied = true
        reply(line, decision)
    end
    local id = p2.post("/chat/completions", request, function(err, response)
        if campaign ~= state.data or turn ~= cm:turn_number() then return finish() end
        local choice = response and response.choices and response.choices[1]
        local content = choice and choice.message and choice.message.content
        if err or type(content) ~= "string" then return finish() end
        local decision = json.decode(content)
        if type(decision) ~= "table" or type(decision.line) ~= "string" or decision.line == ""
            or type(decision.gold) ~= "number" or decision.gold < 0 or decision.gold ~= math.floor(decision.gold)
            or (decision.verdict ~= "accept" and decision.verdict ~= "decline" and decision.verdict ~= "counter") then
            return finish()
        end
        finish(decision.line, decision)
    end)
    return id ~= nil or replied == true
end
local init = ruler.init
ruler.init = function(deps)
    init(deps)
    diplomacy_expansion = expansion.install({
        cm = cm, core = core, ruler = ruler, state = state, world = world, actions = actions, chronicle = chronicle,
        influence = influence, natural = natural, negotiation = negotiation, council = council, military = military,
        ask_envoy = ask_envoy,
        is_open = function()
            local frame = ui and (ui.frame or ui.panel)
            return frame and ui.mode == "talk" and frame:Visible()
        end,
        localise = function(key) return common.get_localised_string(key) end,
        fold = u8.fold, words = u8.words, stem = u8.ru_stem,
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
verifyMaskLayout(layout);
let chronicle = readEntry(stock, chroniclePath).toString('utf8');
chronicle = activate(chronicle, /^chronicle\.pretty_region = function\(key\) return pretty_region\(key\) end$/m, `$&

local gift_chronicle = (function()
${giftChronicle}
end)()
local function gift_place(key)
    local loc_key = "regions_onscreen_" .. key
    local name = common and common.get_localised_string(loc_key)
    if type(name) == "string" and name ~= "" and name ~= loc_key then return name end
    return pretty_region(key)
end`);
chronicle = activate(chronicle, /^local UNCAPPED = \{ death = true,/m,
  'local UNCAPPED = { settlement_gift = true, death = true,');
chronicle = activate(chronicle, /^if e\.k == "region" then\r?\nif b ~= "" and r then[^\n]*\nif r then[^\n]*\nreturn TS\("chron\.region_any"[^\n]*$/m,
  `if e.k == "settlement_gift" then
    x.r = gift_place(e.r)
    return TS("chron.settlement_gift", "{a} voluntarily gave the settlement of {r} to {b} as a diplomatic gift", x)
elseif e.k == "region" then
    if b ~= "" and r then return TS("chron.region_from", "Ownership of {r} passed from {b} to {a}", x) end
    if r then return TS("chron.region", "{a} became the owner of {r}", x) end
    return TS("chron.region_any", "{a} became the owner of a province", x)`);
chronicle = activate(chronicle, /^if lost > 0 and gained == 0 then[\s\S]*?\.\. window \.\. " - the war is even"\r?\nend$/m,
  `if gained == 0 then return "has lost " .. provinces(lost) .. " in the last " .. window end
if lost == 0 then return "has gained " .. provinces(gained) .. " in the last " .. window end
return "has gained " .. provinces(gained) .. " and lost " .. provinces(lost) .. " in the last " .. window
end`);
chronicle = activate(chronicle, /^reputation = deps\.reputation$/m, `$&
gift_chronicle.install(chronicle, state, world, cm, gift_place)
function chronicle.is_settlement_gift_event(context)
    local region, owner
    pcall(function()
        region = context:region():name()
        owner = context:region():owning_faction():name()
    end)
    if not region or not owner then return false end
    return chronicle.is_settlement_gift_change(region, faction_key_of(context, "previous_faction"), owner)
end`);
chronicle = activate(chronicle, /^if new_owner then\r?\nchronicle\.add\("region", new_owner, previous, region_key\)$/m,
  'if new_owner and not chronicle.is_settlement_gift_change(region_key, previous, new_owner) then\n'
  + 'chronicle.add("region", new_owner, previous, region_key)');
let russian = readEntry(stock, russianPath).toString('utf8');
for (const [key, translated] of [
  ['region', 'Фракция {a} стала владельцем поселения {r}'],
  ['region_any', 'Фракция {a} получила новое поселение'],
  ['region_from', 'Поселение {r} перешло от фракции {b} к фракции {a}'],
]) {
  russian = activate(russian, new RegExp('^\\["chron\\.' + key + '"\\] = .*,$', 'm'),
    `["chron.${key}"] = "${translated}",`);
}
russian = activate(russian, /^\["chron\.region_from"\] = .*,$/m,
  '$&\n["chron.settlement_gift"] = "Фракция {a} добровольно передала поселение {r} в дар фракции {b}",');
let json = readEntry(stock, jsonPath).toString('utf8');
json = activate(json, /^local SUB = string\.sub$/m, 'local SUB = byte_sub');
json = activate(json, /^SUB = has_high\(s\) and byte_sub or string\.sub\r?\n/m, '');
json = activate(json, /NUM_CHARS\[string\.sub\(chars, k, k\)\]/, 'NUM_CHARS[byte_sub(chars, k, k)]');
json = activate(json, /elseif c == "-" or \(c >= "0" and c <= "9"\) then return parse_number\(s, i\)/,
  'elseif c == "-" or c:match("^%d$") then return parse_number(s, i)');
const entries = new Map([
  [mainPath, Buffer.from(main, 'utf8')], [rulerPath, Buffer.from(ruler, 'utf8')],
  [layoutPath, Buffer.from(layout, 'utf8')], [pickerPath, picker], [jsonPath, Buffer.from(json, 'utf8')],
  [chroniclePath, Buffer.from(chronicle, 'utf8')], [russianPath, Buffer.from(russian, 'utf8')],
]);
const pack = moviePack(entries);
pack.writeUInt32LE(3, 4); // Selectable Mod pack.
await writeFile(output, pack);
for (const [path, content] of entries) assert.deepEqual(readEntry(output, path), content);
console.log(output);
console.log('SHA256', createHash('sha256').update(pack).digest('hex'));
