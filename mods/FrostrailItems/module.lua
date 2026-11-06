local M={title="新物品"}
function M:item(spec)
    local name="ISCH_FRI_"..spec.id
    local path="/Game/FrostrailMods/FrostrailItems/"..name
    -- UE4SS LoadAsset searches the shipped registry. Like Assist's derived
    -- assets, this independent cooked asset uses the native path loader.
    local library=self.core.class("/Script/Engine.Default__KismetSystemLibrary")
    local reference=library:Conv_SoftObjPathToSoftObjRef({AssetPath={PackageName=FName(path),AssetName=FName(name)}})
    local item=library:LoadAsset_Blocking(reference)
    assert(self.core.valid(item),"Missing item schematic: "..path)
    return item
end

function M:language_changed()
    local C=self.core
    -- The rooted ObjectLibrary owns the asset for this process. The schematic
    -- references its copied parameter and use-action subobjects.
    for _,spec in ipairs(self.catalog.items) do
        local item=self:item(spec)
        item.DisplayName=FText(C.text(spec.name.zh,spec.name.en))
        -- The last line tells players which mod an item comes from; it vanishes
        -- from saves when the mod is removed. The cooked text keeps no such line.
        local source=self.catalog.source
        local zh,en=spec.description.zh,spec.description.en
        if source then zh,en=zh.."\n"..source.zh,en.."\n"..source.en end
        item.Description=FText(C.text(zh,en))
    end
end

function M:init()
    local C=self.core
    self.catalog=C.config.read(self.dir.."/items.json")
    local items={}
    for _,spec in ipairs(self.catalog.items) do items[#items+1]=self:item(spec) end
    C.retain("items",items)
    self.visuals=dofile(self.dir.."/visuals.lua")(C,self.dir,self.catalog)
    self.icons=dofile(self.dir.."/icons.lua")(C,self.catalog)
    self:language_changed()
    -- Native host spawning and save restoration do not share a proven Lua
    -- notification. A bounded 500 ms scan covers both after ItemInstance exists.
    LoopInGameThreadWithDelay(500,function()
        if C.pawn_valid() then C.call("refresh_visuals")
        elseif not self.failed then self.visuals:clear() end
    end)
    C.log(self.id,"Loaded "..#items.." independent item schematics")
end

function M:refresh_visuals()
    self.visuals:scan(self.core.player)
    self.icons:refresh()
end
function M:player_ready() self:refresh_visuals() end
function M:player_left() if self.visuals then self.visuals:clear() end end

return M
