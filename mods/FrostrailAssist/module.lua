local here=debug.getinfo(1,"S").source:sub(2):gsub("\\","/"):match("^(.*)/module.lua$")
local M={title="辅助",features={}}
local order={"basic","quickstash","pause","supply","farming","loot","return_train","durability"}
for _,name in ipairs(order) do
    M.features[name]=dofile(here.."/features/"..name.."/module.lua")
end

function M:configure()
    for name,feature in pairs(self.features) do
        feature.core,feature.dir,feature.id=self.core,self.dir,self.id.."."..name
        feature.cfg=name=="basic" and self.cfg or self.cfg[name]
        if name~="basic" then
            for key,value in pairs(self.defaults[name]) do
                if feature.cfg[key]==nil then feature.cfg[key]=value end
            end
        end
        feature.config=self.cfg
    end
end
-- A failing feature stops alone, as it did when each was its own package:
-- the others keep running, and its own loops see feature.failed.
function M:each(method,...)
    local args=table.pack(...)
    for _,name in ipairs(order) do
        local feature=self.features[name]
        if not feature.failed and (name~="farming" or self.farming_enabled) and feature[method] then
            local ok,err=xpcall(function() feature[method](feature,table.unpack(args,1,args.n)) end,debug.traceback)
            if not ok then feature.failed=true; self.core.log(self.core.id,"ERROR "..name..": "..tostring(err)) end
        end
    end
end
function M:setup()
    self.defaults=self.core.config.read(self.dir.."/defaults.json")
    self:configure()
    -- Farming changes native recipes for this process, so its switch needs a restart.
    self.farming_enabled=self.cfg.farming.enabled
    self:each("setup")
end
function M:init() self:each("init") end
function M:changed() self:configure(); self:each("changed") end
function M:language_changed() self:each("language_changed") end
function M:player_ready(pc,pawn) self:each("player_ready",pc,pawn) end
function M:player_left() self:each("player_left") end
return M
