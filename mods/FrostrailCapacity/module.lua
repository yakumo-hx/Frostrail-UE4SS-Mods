local here=debug.getinfo(1,"S").source:sub(2):gsub("\\","/"):match("^(.*)/module.lua$")
local M={title="容量",features={}}
for _,name in ipairs({"stacks","recycler"}) do
    M.features[name]=dofile(here.."/features/"..name.."/module.lua")
end
function M:setup()
    local defaults=self.core.config.read(self.dir.."/defaults.json")
    for name,feature in pairs(self.features) do
        feature.core,feature.dir,feature.id=self.core,self.dir,self.id.."."..name
        feature.cfg=self.cfg[name]
        for key,value in pairs(defaults[name]) do
            if feature.cfg[key]==nil then feature.cfg[key]=value end
        end
    end
end
-- A failing feature stops alone; the other one keeps working.
local function run(self,name,method,...)
    local feature=self.features[name]
    if feature.failed then return end
    local args=table.pack(...)
    local ok,err=xpcall(function() feature[method](feature,table.unpack(args,1,args.n)) end,debug.traceback)
    if not ok then feature.failed=true; self.core.log(self.core.id,"ERROR "..name..": "..tostring(err)) end
end
function M:init()
    run(self,"stacks","init")
    run(self,"recycler","init")
end
function M:actor_ready(actor) run(self,"recycler","actor_ready",actor) end
return M
