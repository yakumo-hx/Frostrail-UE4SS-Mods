local C = require("Frostrail.runtime").create({settings=false})
local M = {}
local runtime, firstPerson, ui
local api, byId = {}, {}
local skins = C.config.read(C.dir.."/skins.json")
for _,skin in ipairs(skins) do byId[skin.id] = skin end
local candidate

function api.list() return skins end
function api.selected() return byId[M.cfg.skin] and M.cfg.skin or "original" end
function api.showBack(id)
    local skin = byId[id]
    if not skin or not skin.mesh then return true end
    local value = M.cfg.backOverrides[id]
    if type(value) == "boolean" then return value end
    return not skin.hideBackByDefault
end
local function refresh()
    if not runtime or not C.pawn_valid() or not C.player:IsLocalController() then return end
    local world = byId[api.selected()]
    local preview = byId[candidate] or world
    runtime.set(world.mesh and world, preview.mesh and preview, api.showBack(world.id), api.showBack(preview.id))
    firstPerson.set(world.firstPersonMesh and world)
end
function api.preview(id)
    candidate = id and byId[id] and id or nil
    refresh()
end
local function saveChoice(values,key,value)
    local previous = values[key]
    values[key] = value
    local saved, err = pcall(C.config.save,C.dir.."/config.json",M.cfg)
    if not saved then
        values[key] = previous
        error(err)
    end
end
function api.apply(id)
    if not byId[id] then return false end
    saveChoice(M.cfg,"skin",id)
    candidate = nil
    refresh()
    return true
end
function api.setBack(id,value)
    if not byId[id] or not byId[id].mesh then return end
    saveChoice(M.cfg.backOverrides,id,value)
    refresh()
end

function M:init()
    runtime = assert(loadfile(C.dir.."/Scripts/runtime.lua"))(C)
    firstPerson = assert(loadfile(C.dir.."/Scripts/firstperson.lua"))(C,runtime)
    ui = assert(loadfile(C.dir.."/Scripts/ui.lua"))(C,api)
    -- Travel can remove the HUD without popping the open skin page first.
    -- Release this VM's binding while its widget tree and controller still exist.
    RegisterLoadMapPreHook(function() C.run(C.id,C.set_player,nil,nil) end)
end
function M:player_ready(pc,pawn)
    if not pc:IsLocalController() then return end
    runtime.bind(pawn)
    firstPerson.bind(pawn)
    ui.bind(pawn)
    refresh()
end
function M:player_left()
    -- Closing a try-on page also cancels its pending selection.
    runtime.clear()
    firstPerson.clear()
    ui.clear()
    candidate = nil
end
function M:changed() refresh() end
return C.start(M)
