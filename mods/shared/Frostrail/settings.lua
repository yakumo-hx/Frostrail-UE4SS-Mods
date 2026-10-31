-- Optional, data-only settings discovery. Runtime callbacks stay in their mod.
local config=require("Frostrail.config")
local json=require("Frostrail.json")
local M={registry_key="FrostrailCore.settings.ids",busy_key="FrostrailCore.ui.blocked"}
local prefix="FrostrailCore.settings."
function M.get(value,key)
    for part in key:gmatch("[^.]+") do
        if type(value)~="table" then return nil end
        value=value[part]
    end
    return value
end
function M.set(value,key,new_value)
    local parts={}; for part in key:gmatch("[^.]+") do parts[#parts+1]=part end
    for i=1,#parts-1 do
        local part=parts[i]
        if type(value[part])~="table" then value[part]={} end
        value=value[part]
    end
    value[parts[#parts]]=new_value
end
function M.label(value,language)
    if type(value)~="table" then return tostring(value or "") end
    return value[language or "zh"] or value.zh or value.en or ""
end
function M.command(id) return "frostrail.apply."..id end
function M.set_busy(value) ModRef:SetSharedVariable(M.busy_key,value==true) end
function M.busy() return ModRef:GetSharedVariable(M.busy_key)==true end
function M.kind(field,value)
    if field.type=="color" then return "color" end
    if field.options and #field.options>0 then return "choice" end
    if type(value)=="boolean" then return "bool" end
    if type(value)=="number" then return "number" end
    if type(value)=="table" then
        if #value>0 or (getmetatable(value) or {}).__json_array or field.columns then return "list" end
        return "map"
    end
    return "string"
end
function M.register(C)
    local fields=config.optional(C.dir.."/settings.json")
    if not fields then return false end
    local defaults=config.optional(C.dir.."/defaults.json") or {}
    for _,field in ipairs(fields) do field.type=M.kind(field,M.get(defaults,field.key)) end
    local manifest=config.optional(C.dir.."/mod.json") or {}
    local id=C.context_id or C.id
    local record={id=id,title=manifest.name or C.title or C.id,
        config={path=C.dir.."/config.json",defaults=defaults,fields=fields}}
    local raw=ModRef:GetSharedVariable(M.registry_key)
    local ids=type(raw)=="string" and json.decode(raw) or {}
    local found=false
    for _,existing in ipairs(ids) do if existing==id then found=true; break end end
    if not found then ids[#ids+1]=id end
    ModRef:SetSharedVariable(prefix..id,json.encode(record))
    ModRef:SetSharedVariable(M.registry_key,json.encode(ids))
    return true
end
function M.list()
    local raw=ModRef:GetSharedVariable(M.registry_key)
    local ids=type(raw)=="string" and json.decode(raw) or {}
    local result={}
    for _,id in ipairs(ids) do
        local value=ModRef:GetSharedVariable(prefix..id)
        if type(value)=="string" then result[#result+1]=json.decode(value) end
    end
    return result
end
function M.read_config(C,description)
    return config.optional(description.path) or {}
end
function M.notify(C,id)
    if not C.player_valid() then return false end
    C.class("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(C.player,M.command(id),C.player)
    return true
end
return M
