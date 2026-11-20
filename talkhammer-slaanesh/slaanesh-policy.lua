-- Shared numerical and dialogue policy for the ten Slaanesh Expanded rulers.
local policy = {}
local default_path = "talkhammer/talkhammer-slaanesh-rulers.json"

function policy.resolve(cm, json, them_key, player_key, config_path)
    if not cm or not json or type(json.decode) ~= "function"
        or type(them_key) ~= "string" or type(player_key) ~= "string"
        or them_key == player_key then return end
    local opened, file = pcall(io.open, config_path or default_path, "rb")
    if not opened or not file then return end
    local read, raw = pcall(function() return file:read("*a") end)
    pcall(function() file:close() end)
    if not read then return end
    local decoded, config = pcall(json.decode, raw)
    if not decoded or type(config) ~= "table" or config.version ~= 2
        or type(config.rulers) ~= "table" or type(config.stages) ~= "table"
        or type(config.regard) ~= "table" then return end
    local per_stage = config.regard.perStage
    if type(per_stage) ~= "number" or per_stage ~= per_stage
        or per_stage < 0 or per_stage == math.huge or per_stage % 1 ~= 0 then return end
    local entry = config.rulers[them_key]
    if type(entry) ~= "table" or type(entry.leaderSubtype) ~= "string"
        or type(entry.traitKey) ~= "string" then return end
    local found, target, player, leader = pcall(function()
        local you, them = cm:get_faction(player_key), cm:get_faction(them_key)
        if not you or you:is_null_interface() or you:is_human() ~= true
            or not them or them:is_null_interface() then return end
        local character = them:faction_leader()
        if not character or character:is_null_interface()
            or character:character_subtype_key() ~= entry.leaderSubtype then return end
        return them, you, character
    end)
    if not found or not leader then return end
    local valid, level = pcall(function() return leader:trait_level(entry.traitKey) end)
    if not valid or type(level) ~= "number" or level ~= level
        or level < 0 or level > 3 or level % 1 ~= 0 then level = 0 end
    local stage
    for _, value in ipairs(config.stages) do
        if type(value) == "table" and value.level == level then stage = value break end
    end
    if not stage then return end
    -- The engine expects a faction interface here, not a faction key.
    local relation_ok, is_vassal = pcall(function() return target:is_vassal_of(player) end)
    is_vassal = relation_ok and is_vassal == true
    local dialogue = config.vassalDialogue or {}
    local required = dialogue.requiredStage
    local agreement = type(required) == "number" and required == 3
        and level == required and is_vassal
    return {
        level = level,
        bonus = per_stage * level,
        isPlayerVassal = is_vassal,
        requireAgreement = agreement,
        name = entry.name or them_key,
        stageName = stage.name or tostring(level),
        decisionRule = config.decisionRule,
        stageDecision = stage.decision,
        agreementRule = dialogue.instruction,
        normalRule = dialogue.otherwise,
    }
end

function policy.instruction(context)
    if not context then return "" end
    local function text(value) return type(value) == "string" and value or "" end
    return table.concat({
        "Verified campaign policy: stage=" .. context.level
            .. "; player_vassal=" .. tostring(context.isPlayerVassal)
            .. "; require_agreement=" .. tostring(context.requireAgreement) .. ".",
        "The numerical corruption bonus +" .. context.bonus
            .. " has already been included in Regard by Lua; do not add it again or replace the score.",
        text(context.decisionRule),
        text(context.stageDecision),
        context.requireAgreement and text(context.agreementRule) or text(context.normalRule),
    }, "\n")
end

return policy
