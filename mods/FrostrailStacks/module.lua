local here=debug.getinfo(1,"S").source:sub(2):gsub("\\","/"):match("^(.*)/module.lua$")
local logic=dofile(here.."/logic.lua")
local M={title="堆叠"}
function M:init()
    local C=self.core
    local catalog=C.config.read(self.dir.."/items.json")
    self.originals={}
    local count,keep=0,{}
    for _,entry in ipairs(catalog) do
        local item=LoadAsset(entry.path)
        assert(C.valid(item),"Missing schematic "..entry.path)
        local original=item.MaxStackSize
        local multiplier=self.cfg.categories[entry.category] or self.cfg.multiplier
        assert(type(multiplier)=="number" and multiplier>=1 and original*multiplier<2147483647,"Invalid stack multiplier")
        local limit=logic.stack_limit(original,item.bIsStackable,multiplier)
        if limit~=original then
            item.MaxStackSize=limit
            keep[#keep+1]=item
            self.originals[entry.path]=original
            count=count+1
        end
    end
    C.retain(self.id,keep)
    C.log(self.id,"Bound "..count.." stackable schematics; multiplier="..self.cfg.multiplier.."; weight fields unchanged")
end
return M
