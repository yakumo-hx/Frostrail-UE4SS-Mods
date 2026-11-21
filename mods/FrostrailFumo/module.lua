local M={title="八云紫娃娃"}

function M:init()
    local C=self.core
    local catalog=C.config.read(self.dir.."/items.json")
    self.spec=catalog.items[1]
    local function load(name)
        local object=LoadAsset(catalog.root..name.."."..name)
        assert(C.valid(object),"Missing doll asset: "..name)
        return object
    end
    self.item=load(catalog.prefix..self.spec.id)
    self.decor=load("CSCH_FF_Yukari")
    C.retain("doll_schematics",{self.item,self.decor})
    -- Relocate resolves an actor class against the game's construction catalog.
    -- Cooked mod schematics loaded by the unlock table are absent from that list.
    C.hook("/Script/Frostrail.ConstructionSchematic:GetLoadedConstructionSchematicAssets",nil,function(_,out,category)
        if category:get().TagName:ToString()~="None" then return end
        local list=out:get()
        for i=1,#list do if C.same(list[i],self.decor) then return end end
        list[#list+1]=self.decor
    end)
    self:language_changed()
end

function M:language_changed()
    if not self.item then return end
    local text=self.core.text
    local name=FText(text(self.spec.name.zh,self.spec.name.en))
    self.item.DisplayName=name
    self.decor.DisplayName=name
    self.item.Description=FText(text(self.spec.description.zh,self.spec.description.en))
end

return M
