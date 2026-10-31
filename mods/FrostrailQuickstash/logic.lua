-- Quickstash inventory layout rules, independent of Unreal wrappers.
local M={}
function M.locked(slots)
    local result={}
    for _,one_based in ipairs(slots) do result[one_based-1]=true end
    return result
end
function M.sort_layout(before,sorted,locks,quick_slots,capacity)
    local result,fixed={},{}
    for slot,item in pairs(before) do
        if slot<quick_slots or locks[slot] then result[slot]=item; fixed[slot]=true end
    end
    local next_slot=quick_slots
    for _,item in ipairs(sorted) do
        while fixed[next_slot] do next_slot=next_slot+1 end
        assert(next_slot<capacity,"Sorted items exceed inventory capacity")
        result[next_slot]=item
        next_slot=next_slot+1
    end
    return result
end
return M
