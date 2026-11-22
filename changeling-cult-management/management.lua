local management = {}

local function before(a, b)
    if a.group == "spread" then
        if a.new_spread ~= b.new_spread then return a.new_spread end
        if a.site.provinces ~= b.site.provinces then return a.site.provinces > b.site.provinces end
        if a.site.targets ~= b.site.targets then return a.site.targets > b.site.targets end
        if a.gain ~= b.gain then return a.gain > b.gain end
    end
    if a.group == "gold" and a.payback ~= b.payback then return a.payback < b.payback end
    if a.gold ~= b.gold then return a.gold < b.gold end
    if a.supplies ~= b.supplies then return a.supplies < b.supplies end
    if a.site.name ~= b.site.name then return a.site.name < b.site.name end
    if a.slot ~= b.slot then return a.slot < b.slot end
    return a.level < b.level
end

function management.rank(jobs, sites, buildings)
    local result = {gold={}, books={}, spread={}, remove={}}
    local best = {gold={}, books={}, spread={}}
    local has_spread = {}
    for key, site in pairs(sites) do has_spread[key] = site.has_spread end
    for _, job in ipairs(jobs) do
        local current = buildings[job.current]
        if current and current.group == "spread" then has_spread[job.region] = true end
    end
    for _, job in ipairs(jobs) do
        local level, site = buildings[job.level], sites[job.region]
        if level and site then
            local entry = {}
            for field, value in pairs(job) do entry[field] = value end
            local current = buildings[job.current] or {}
            entry.group, entry.site = level.group, site
            if job.kind == "remove" then
                if level.group == "spread" and site.targets == 0 then
                    entry.group = "remove"
                    result.remove[#result.remove + 1] = entry
                end
            else
                if level.group == "gold" and level.share then
                    local gdp = site.gdp
                    local new_gdp = gdp * (1 + level.host_bonus) / (1 + (current.host_bonus or 0))
                    local old_income = gdp * (current.share or 0) + (current.flat_gold or 0)
                    entry.gain = math.floor(new_gdp * level.share - old_income + .5)
                    if entry.gain > 0 then entry.payback = entry.gold / entry.gain end
                    entry.old_share, entry.share = current.share or 0, level.share
                elseif level.group == "books" then
                    entry.gain = level.books - (current.books or 0)
                elseif level.group == "spread" and site.targets > 0
                    and (not has_spread[job.region] or current.group == "spread") then
                    entry.new_spread = not has_spread[job.region]
                    entry.gain = level.spread - (current.spread or 0)
                end
                if entry.gain and entry.gain > 0 then
                    local group = best[entry.group]
                    local other = group[job.region]
                    if not other or before(entry, other) then group[job.region] = entry end
                end
            end
        end
    end
    for group, entries in pairs(best) do
        for _, entry in pairs(entries) do result[group][#result[group] + 1] = entry end
    end
    for _, entries in pairs(result) do table.sort(entries, before) end
    return result
end

function management.preset(jobs, buildings, region, levels)
    local groups, choices = {}, {}
    for i, level in ipairs(levels) do
        local building = buildings[level]
        if not building or groups[building.group] then return nil end
        groups[building.group], choices[i] = true, {}
        for _, job in ipairs(jobs) do
            if job.region == region and job.kind == "build" and job.level == level then
                choices[i][#choices[i] + 1] = job
            end
        end
    end
    local used, plan = {}, {}
    local function assign(i)
        if i > #choices then return true end
        for _, job in ipairs(choices[i]) do
            if not used[job.slot] then
                used[job.slot], plan[i] = true, job
                if assign(i + 1) then return true end
                used[job.slot], plan[i] = nil, nil
            end
        end
        return false
    end
    if #choices > 0 and assign(1) then return plan end
end

function management.same(a, b)
    return a.region == b.region and a.slot == b.slot and a.level == b.level and a.current == b.current
        and a.kind == b.kind and a.gold == b.gold and a.supplies == b.supplies
end

function management.total(jobs)
    local gold, supplies = 0, 0
    for _, job in ipairs(jobs) do
        gold, supplies = gold + job.gold, supplies + job.supplies
    end
    return gold, supplies
end

return management
