local natural = {}
local verbs = { ["передай"] = true, ["передайте"] = true, ["подари"] = true, ["подарите"] = true,
    ["отдай"] = true, ["отдайте"] = true, ["уступи"] = true, ["уступите"] = true,
    give = true, transfer = true, gift = true }
local towns = { ["поселение"] = true, ["город"] = true, ["крепость"] = true, ["форт"] = true,
    settlement = true, city = true }
local fillers = { ["пожалуйста"] = true, ["свое"] = true, ["своё"] = true, ["свой"] = true,
    ["свою"] = true, ["в"] = true, ["дар"] = true, ["фракции"] = true, ["ведьме"] = true,
    ["леди"] = true, ["лорду"] = true, ["королю"] = true, ["королеве"] = true,
    your = true, the = true, to = true, please = true, as = true, a = true, gift = true }
local alternatives = { ["если"] = true, ["или"] = true, ["либо"] = true, ["взамен"] = true,
    ["за"] = true, ["после"] = true, ["потом"] = true, ["не"] = true, ["и"] = true,
    ["но"] = true, ["когда"] = true, ["вместо"] = true, ["без"] = true, ["ли"] = true,
    ["if"] = true, ["or"] = true, ["and"] = true, ["but"] = true, ["not"] = true,
    ["unless"] = true, ["after"] = true, ["when"] = true, ["for"] = true }

function natural.command(text, words)
    if text:match("[?;\r\n]") or text:match("？") then return end
    local tokens = words(text)
    local first = (tokens[1] == "пожалуйста" or tokens[1] == "please") and 2 or 1
    if not verbs[tokens[first]] then return end
    local body, has_town = {}, false
    for index = first + 1, #tokens do
        local token = tokens[index]
        if alternatives[token] then return end
        if towns[token] then has_town = true end
        body[#body + 1] = token
    end
    return body, has_town
end

local function matches(tokens, choices, words, stem)
    local found = {}
    local function same(a, b) return a == b or (stem and stem(a) == stem(b)) end
    for _, choice in ipairs(choices) do
        for _, label in ipairs(choice.labels) do
            local name = words(label)
            if #name > 0 then
                for first = 1, #tokens - #name + 1 do
                    local matched = true
                    for index, token in ipairs(name) do
                        if not same(tokens[first + index - 1], token) then matched = false; break end
                    end
                    if matched then found[#found + 1] = { key = choice.key, first = first, last = first + #name - 1 } end
                end
            end
        end
    end
    return found
end

function natural.resolve(tokens, cities, recipients, words, stem)
    local location = matches(tokens, cities, words, stem)
    if #location == 0 then return nil, nil, "city" end
    local people = matches(tokens, recipients(), words, stem)
    local city, recipient
    for _, place in ipairs(location) do
        for _, person in ipairs(people) do
            if place.last < person.first or person.last < place.first then
                local complete = true
                for index, token in ipairs(tokens) do
                    if not (index >= place.first and index <= place.last)
                        and not (index >= person.first and index <= person.last)
                        and not fillers[token] and not towns[token] then
                        complete = false
                        break
                    end
                end
                if complete then
                    if city and city ~= place.key then return nil, nil, "city" end
                    if recipient and recipient ~= person.key then return nil, nil, "recipient" end
                    city, recipient = place.key, person.key
                end
            end
        end
    end
    if city then return city, recipient end
    return nil, nil, "recipient"
end

return natural
