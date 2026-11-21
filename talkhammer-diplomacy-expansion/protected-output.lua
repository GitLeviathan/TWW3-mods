return function(environment, fallback)
    local function safe_out(message)
        local output = environment.out
        if not output then return end
        local ok, why = pcall(output, message)
        if not ok then pcall(fallback, why, message) end
    end

    local module_environment = setmetatable({ out = safe_out }, {
        __index = environment,
        __newindex = environment,
    })
    return safe_out, module_environment
end
