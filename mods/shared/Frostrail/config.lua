local json=require("Frostrail.json")
local M={}
function M.read(path)
    local f=assert(io.open(path,"rb"),"Cannot open "..path)
    local text=f:read("*a"); f:close()
    return json.decode(text:gsub("^\239\187\191",""))
end
function M.save(path,value)
    local text=json.encode(value)
    local temp,previous=path..".tmp",path..".replace-old"
    local function fail(message)
        os.remove(temp)
        error(message)
    end
    local f=assert(io.open(temp,"wb"))
    local written,write_error=f:write(text,"\n")
    local closed,close_error=f:close()
    if not written or not closed then fail(write_error or close_error) end
    local old=io.open(path,"rb")
    if old then
        local ok,err=old:close()
        if not ok then fail(err) end
        ok,err=os.rename(path,previous)
        if not ok then fail(err) end
    end
    local ok,err=os.rename(temp,path)
    if not ok then
        if old then
            local restored,restore_error=os.rename(previous,path)
            if not restored then fail(err.."; restore failed: "..restore_error.."; old file: "..previous) end
        end
        fail(err)
    end
    if old then assert(os.remove(previous)) end
end
function M.optional(path)
    local f=io.open(path,"rb")
    if not f then return nil end
    f:close()
    return M.read(path)
end
function M.load(dir)
    local defaults=M.optional(dir.."/defaults.json") or {}
    local f=io.open(dir.."/config.json","rb")
    if not f then
        if next(defaults) then M.save(dir.."/config.json",defaults) end
        return defaults
    end
    f:close()
    local value=M.read(dir.."/config.json")
    local changed=false
    -- New metadata/default fields are added without replacing user values.
    for k,v in pairs(defaults) do if value[k]==nil then value[k]=v; changed=true end end
    if changed then M.save(dir.."/config.json",value) end
    return value
end
return M
