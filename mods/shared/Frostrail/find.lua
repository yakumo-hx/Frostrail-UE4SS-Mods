-- Internal lookup helpers; not part of the public support API.
local M={}
function M.first(C,class,accept)
    for _,object in ipairs(FindAllOf(class) or {}) do
        if C.valid(object) and (not accept or accept(object)) then return object end
    end
end
function M.controller(C,menu,class)
    local world
    if menu then
        if not C.valid(menu) then return end
        world=menu:GetWorld()
    else
        local engine=M.first(C,"GameEngine")
        local viewport=engine and engine.GameViewport
        world=C.valid(viewport) and viewport.World or nil
    end
    if not C.valid(world) then return end
    local function matches(pc)
        if not C.valid(pc) or not pc:IsLocalController() then return false end
        local level=pc:GetLevel()
        return C.valid(level) and C.same(level.OwningWorld,world)
    end
    local owner=menu and menu:GetOwningPlayer()
    if matches(owner) then return owner end
    return M.first(C,class or "PlayerController",matches)
end
return M
