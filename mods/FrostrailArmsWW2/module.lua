local M={title="二战枪械"}
local root="/Game/FrostrailMods/FrostrailArmsWW2/"
local selection="/Game/Frostrail/UI/Widgets/Crafting/Basic/WBP_Sub_SchematicSelection.WBP_Sub_SchematicSelection_C"

function M:asset(path)
    local system=self.core.class("/Script/Engine.Default__KismetSystemLibrary")
    local key=path:match("[^/]+$")
    local ref=system:Conv_SoftObjPathToSoftObjRef({AssetPath={PackageName=FName(path),AssetName=FName(key)}})
    local object=system:LoadAsset_Blocking(ref)
    assert(self.core.valid(object),"Missing asset "..path)
    return object
end

function M:language_changed()
    local C=self.core
    for i,spec in ipairs(self.catalog) do
        local gun=self.guns[i]
        gun.DisplayName=FText(C.text(spec.name.zh,spec.name.en))
        gun.Description=FText(C.text(spec.description.zh,spec.description.en))
    end
    -- The stock SMG round is named "SMG Magazine" in every language.
    if self.smg_ammo then self.smg_ammo.DisplayName=FText(C.text("冲锋枪弹药","SMG Ammunition")) end
end

-- Loading a save builds a default hierarchy for each firearm state, then a
-- second one from the save. The state ends up on the second with all parts,
-- but its parameters stay at the receiver's values; stock guns do this too.
-- When a state that already has a hierarchy gets a replacement, let native
-- code rebuild the whole firearm on the next tick. Clients get the native
-- replication notify, so only the authority acts.
function M:watch_restored_firearms()
    local C=self.core
    NotifyOnNewObject("/Script/Frostrail.ModularItemHierarchy",function(hierarchy)
        C.run(C.id,function()
            local state=hierarchy:GetOuter()
            if not state:IsA("/Script/Frostrail.FirearmItemState") or not state.ModularHierarchy:IsValid() then return end
            ExecuteInGameThread(function()
                C.run(C.id,function()
                    if not C.valid(hierarchy) then return end
                    local owner=hierarchy:GetOuter()
                    if owner:HasAuthority() and C.same(owner.ModularHierarchy,hierarchy) then owner:OnRep_ModularHierarchy() end
                end)
            end,EGameThreadMethod.EngineTick)
        end)
    end)
end

function M:init()
    local C=self.core
    self.catalog=C.config.read(C.dir.."/items.json")
    self.guns,self.by_name={},{}
    for i,spec in ipairs(self.catalog) do
        local id="MISCH_FRWW2_"..spec.id
        local gun=self:asset(root..id)
        self.guns[i]=gun
        self.by_name[id]=spec
    end
    self.recipes={table.unpack(self.guns)}
    for _,spec in ipairs(self.catalog) do
        if spec.stats.automatic and spec.shell then
            local ammo=self:asset("/Game/Frostrail/Data/Items/Ammo/"..spec.ammo)
            local tags={}
            local station="Crafting.Station.Ammo"
            local present=false
            ammo.ItemTags.GameplayTags:ForEach(function(_,ref)
                local name=ref:get().TagName
                tags[#tags+1]={TagName=name}
                if name:ToString()==station then present=true end
            end)
            if not present then
                tags[#tags+1]={TagName=FName(station)}
                ammo.ItemTags.GameplayTags=tags
            end
            self.recipes[#self.recipes+1]=ammo
            self.smg_ammo=ammo
        end
    end
    -- Stock progression unlocks these two with a workbench augment the Demo may
    -- not offer, so the player can opt in from settings.
    self.stock_ammo={}
    local held={table.unpack(self.recipes)}
    for _,name in ipairs({"ISCH_Ammo_Rifle_Regular","ISCH_Ammo_Shotgun_Regular"}) do
        local ammo=self:asset("/Game/Frostrail/Data/Items/Ammo/"..name)
        self.stock_ammo[#self.stock_ammo+1]=ammo
        held[#held+1]=ammo
    end
    C.retain("recipes",held)
    self:language_changed()
    self:watch_restored_firearms()
    self.shells=dofile(C.dir.."/shells.lua")(self)
    self.shells:watch()
    LoadAsset(selection)
    C.script_hook(selection..":CreateSchematicWidgets",function(ctx)
        local panel=ctx:get()
        if not C.player_valid() or not C.same(panel:GetOwningPlayer(),C.player) then return end
        for _,ref in ipairs(panel.SchematicView:GetListItems()) do
            local row=ref:get()
            if C.valid(row.Schematic) and self.by_name[row.Schematic:GetFName():ToString()] then
                row.ModularItemConfiguration=row.Schematic.BasicConfig
            end
        end
    end)
    C.hook("/Script/Frostrail.CraftingComponent:GetSessionSchematicSelectionList",function(ctx)
        if not self.recipes_ready and C.pawn_valid() and C.player:HasAuthority()
            and C.same(ctx:get(),C.pawn.CraftingComponent) then
            local list={table.unpack(self.recipes)}
            if self.cfg.unlock_stock_ammo then
                for _,ammo in ipairs(self.stock_ammo) do list[#list+1]=ammo end
            end
            C.player:TryUnlockSchematicViaQuesting(list,{},false)
            self.recipes_ready=true
        end
    end)
end

function M:player_ready(pc)
    self.shells:load_icons(pc)
end

function M:player_left() self.recipes_ready=false end
function M:changed() self.recipes_ready=false end
return M
