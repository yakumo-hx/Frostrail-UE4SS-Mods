local C = require("Frostrail.runtime").create({settings=false})
local M = {}
local runtime, firstPerson, ui
local api, byId = {}, {}
-- Lua opens narrow Windows paths in the C locale, while Unreal takes UTF-8.
-- For a non-ASCII filename, use the UTF-8 locale only while opening the handle.
function C.readSkinJson(path)
    local fullPath = C.dir.."/"..path
    if not fullPath:find("[\128-\255]") then return C.config.read(fullPath) end
    local previous = os.setlocale(nil,"ctype")
    assert(os.setlocale(".UTF8","ctype"))
    local file, err = io.open(fullPath,"rb")
    os.setlocale(previous,"ctype")
    assert(file,err)
    local body = file:read("*a")
    file:close()
    return require("Frostrail.json").decode(body:gsub("^\239\187\191",""))
end

local skins = C.readSkinJson("skins.json")
local folders = {}
-- Windows PowerShell can list Unicode names even when the game has no console.
-- All shell input is literal. The game sets its working directory to Win64.
local listing = assert(io.popen([[powershell.exe -NoProfile -NonInteractive -Command "]]..
    [[[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); ]]..
    [[Get-ChildItem -LiteralPath ue4ss/Mods/FrostrailSkins/addons -Directory -ErrorAction SilentlyContinue | ]]..
    [[Where-Object { [IO.File]::Exists([IO.Path]::Combine($_.FullName,'skins.json')) } | ForEach-Object { $_.Name }"]]))
for name in listing:lines() do folders[#folders+1] = name end
listing:close()
table.sort(folders)
for _,name in ipairs(folders) do
    local prefix = "addons/"..name.."/"
    for _,skin in ipairs(C.readSkinJson(prefix.."skins.json")) do
        for _,field in ipairs({"albedo","surface","reference","stockReference"}) do
            if skin[field] then skin[field] = prefix..skin[field] end
        end
        skins[#skins+1] = skin
    end
end
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
