-- This Mod's multiplier policy; not a platform inventory rule.
local M={}
function M.stack_limit(original,stackable,multiplier)
    if not stackable or original<2 then return original end
    return math.max(original,math.floor(original*multiplier))
end
return M
