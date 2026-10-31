local M={title="辅助",marked={},materials={}}
local identity={Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
local function color(hex)
    return {R=tonumber(hex:sub(1,2),16)/255,G=tonumber(hex:sub(3,4),16)/255,B=tonumber(hex:sub(5,6),16)/255,A=1}
end
function M:setup()
    self.core.action("TakeAll","打开容器：全部拿取","R",function() self:take_all() end)
    self.core.action("Headlamp","免费头灯","F",function()
        local C=self.core
        if C.pawn_valid() and C.instance(self.lamp,self.lamp_name) and not C.player.bShowMouseCursor then
            self.lamp_on=not self.lamp_on; self.lamp:SetVisibility(self.lamp_on,false)
        end
    end)
end
function M:init()
    local C=self.core
    -- UE4SS LoadAsset only searches the shipped asset registry. This new
    -- package is loaded through the native soft-reference loader instead.
    local library=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local reference=library:Conv_SoftObjPathToSoftObjRef({AssetPath={PackageName=FName("/Game/FrostrailMods/M_FrostrailHighlight"),AssetName=FName("M_FrostrailHighlight")}})
    self.parent=library:LoadAsset_Blocking(reference)
    assert(C.valid(self.parent),"Highlight resource missing: install the Assist resource patch and restart")
    assert(self.parent.bDisableDepthTest,"Highlight material must disable depth testing")
    local initializer=LoadAsset("/Game/Frostrail/GAS/AttributeInitializers/GE_SurvivalAttributeSetInitializer.GE_SurvivalAttributeSetInitializer_C"):GetCDO()
    local patched=false
    C.retain(self.id,{self.parent,initializer})
    local carry_reference=library:Conv_SoftObjPathToSoftObjRef({AssetPath={PackageName=FName("/Game/FrostrailMods/GE_FrostrailCarryBase"),AssetName=FName("GE_FrostrailCarryBase_C")}})
    self.carry_class=library:LoadAsset_Blocking(carry_reference)
    assert(C.valid(self.carry_class),"Carry resource missing: update the Assist resource patch and restart")
    self.carry_effect=self.carry_class:GetCDO()
    self.carry_effect.DurationPolicy=0 -- Instant: change the base, retain active GAS modifiers.
    initializer.Modifiers:ForEach(function(_,p)
        local modifier=p:get()
        if modifier.Attribute.AttributeName:ToString()=="MaxCarryWeight" then
            modifier.ModifierMagnitude.MagnitudeCalculationType=0
            modifier.ModifierMagnitude.ScalableFloatMagnitude.Value=self.cfg.base_carry_weight
            self.carry_effect.Modifiers={modifier}
            self.carry_effect.Modifiers:ForEach(function(_,m) m:get().ModifierOp=3 end) -- Override only MaxCarryWeight.
            patched=true
        end
    end)
    assert(patched,"Native MaxCarryWeight initializer not found")
    C.retain(self.id,{self.parent,initializer,self.carry_class,self.carry_effect})
    C.log(self.id,"Native carry base initializer="..self.cfg.base_carry_weight.."; other GAS modifiers retained")
    C.script_hook("/Script/Frostrail.BaseCharacter:OnBecomeDead",function() self:scan() end)
    C.hook("/Script/Frostrail.GatherableActor:TryGather",nil,function() self:scan() end)
    LoopAsync(math.max(500,self.cfg.refresh_ms),function()
        ExecuteInGameThread(function() if not self.failed then C.run(self.id,function() self:scan() end) end end)
        return self.failed==true
    end)
end
function M:restore_mark(entry)
    local C=self.core
    if C.instance(entry.mesh,entry.name) and C.same(entry.mesh.OverlayMaterial,self.materials[entry.category]) then
        entry.mesh:SetOverlayMaterial(C.instance(entry.original,entry.original_name) and entry.original or nil)
    end
end
function M:retain_overlays()
    local keep={}
    for _,entry in pairs(self.marked) do
        if self.core.instance(entry.original,entry.original_name) then keep[#keep+1]=entry.original end
    end
    -- Replacing OverlayMaterial removes the mesh's reference to its old material.
    -- Keep that original alive until restoration, then release it with the mark.
    self.core.retain(self.id.."_overlays",keep)
end
function M:player_left()
    local C=self.core
    for _,entry in pairs(self.marked) do self:restore_mark(entry) end
    self.marked={}
    self:retain_overlays()
    if C.instance(self.lamp,self.lamp_name) then self.lamp:K2_DestroyComponent(self.lamp:GetOwner()) end
    self.lamp,self.lamp_name,self.lamp_on=nil,nil,false
    self.materials={}
    C.retain(self.id.."_colors",{})
end
function M:player_ready(pc,pawn)
    self:apply_carry(pawn)
    self.materials={}
    for category in pairs(self.cfg.colors) do
        self.materials[category]=StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary"):CreateDynamicMaterialInstance(self.core.assets,self.parent,FName("Frostrail_"..category),0)
    end
    local keep={}; for _,mat in pairs(self.materials) do keep[#keep+1]=mat end
    self.core.retain(self.id.."_colors",keep)
    self.lamp=pawn:AddComponentByClass(self.core.class("/Script/Engine.SpotLightComponent"),true,identity,false)
    assert(self.core.valid(self.lamp),"Headlamp creation failed")
    self.lamp_name=self.lamp:GetFullName()
    self.lamp:K2_AttachToComponent(pawn:GetFirstPersonCamera(),FName("None"),2,2,2,false)
    self.lamp:SetVisibility(false,false); self.lamp_on=false
    self:changed()
    self.core.log(self.id,"Player bound; headlamp attached; four independent depth-disabled materials bound")
end
function M:apply_carry(pawn)
    local C=self.core
    if not C.valid(pawn) or not pawn:HasAuthority() then return end
    local library=StaticFindObject("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    local asc=library:GetAbilitySystemComponent(pawn)
    local attributes=asc:GetAttributeSet(C.class("/Script/Frostrail.SurvivalAttributeSet"))
    if not C.valid(attributes) then return end
    local before=attributes.MaxCarryWeight.BaseValue
    if before~=self.cfg.base_carry_weight then
        -- The pinned UE4SS build converts opaque spec handles to empty Lua
        -- tables. Native application by class keeps that handle inside GAS.
        asc:BP_ApplyGameplayEffectToSelf(self.carry_class,1,{})
    end
    C.log(self.id,"Carry base after player restore: "..before.." -> "..attributes.MaxCarryWeight.BaseValue.." current="..attributes.MaxCarryWeight.CurrentValue)
end
function M:changed()
    local C=self.core
    for category,mat in pairs(self.materials) do
        if C.valid(mat) then mat:SetVectorParameterValue(FName("Color"),color(self.cfg.colors[category])) end
    end
    if C.pawn_valid() and C.instance(self.lamp,self.lamp_name) then
        self.lamp:SetIntensity(self.cfg.lamp_intensity)
        self.lamp:SetAttenuationRadius(self.cfg.lamp_radius_m*100)
        self.lamp:SetOuterConeAngle(self.cfg.lamp_angle)
        self.lamp:SetInnerConeAngle(self.cfg.lamp_angle*0.6)
    end
    self:scan()
end
function M:take_all()
    local C=self.core
    if not C.pawn_valid() or not C.pawn:HasAuthority() then return end
    local system=C.pawn.ItemSystemComponent
    local container=system:GetSessionContainer()
    if not C.valid(container) or not container.bCanEverRemoveItems then return end
    local source=container:GetInventory()
    if not C.valid(source) then return end
    system:RequestTransferAllContainables(source,system:GetInventory(),false,false)
    C.log(self.id,"Take all requested through native open-container session")
    self:scan()
end
function M:scan()
    local C=self.core
    if not C.pawn_valid() then
        if self.lamp or next(self.marked) then self:player_left() end
        return
    end
    if not C.valid(self.materials.items) then return end
    local desired,counts={},{items=0,containers=0,cellars=0,enemies=0}
    local function mark(actor,category)
        if not C.valid(actor) or actor:GetDistanceTo(C.pawn)>self.cfg.range_m*100 then return end
        counts[category]=counts[category]+1
        for _,p in ipairs(actor:K2_GetComponentsByClass(C.class("/Script/Engine.MeshComponent"))) do
            local mesh=p:get()
            if C.valid(mesh) then desired[mesh:GetAddress()]={mesh=mesh,category=category} end
        end
    end
    if self.cfg.highlight then
        if self.cfg.items then
            for _,a in ipairs(FindAllOf("ItemPickable") or {}) do mark(a,"items") end
            for _,a in ipairs(FindAllOf("GatherableActor") or {}) do
                if not a.bHasGathered and a:CanGather() then mark(a,"items") end
            end
        end
        if self.cfg.containers then
            for _,container in ipairs(FindAllOf("ContainerComponent") or {}) do
                local owner,inv=container:GetOwner(),container:GetInventory()
                if C.valid(owner) and C.valid(inv) and not inv:IsEmpty()
                    and owner:IsA("/Script/Frostrail.LootContainer")
                    and not owner:IsA("/Game/Frostrail/Blueprints/Interactables/Containers/TrainContainers/BP_TrainContainer_Base.BP_TrainContainer_Base_C")
                    and not owner:GetClass():GetFName():ToString():find("DeadPlayer") then mark(owner,"containers") end
            end
        end
        if self.cfg.cellars then
            for _,a in ipairs(FindAllOf("DungeonEntrance") or {}) do if not a:HasCollapsed() then mark(a,"cellars") end end
        end
        if self.cfg.enemies and C.valid(C.pawn.MyCharacterTemplate) then
            local faction=C.pawn.MyCharacterTemplate:GetFaction()
            for _,a in ipairs(FindAllOf("AICharacter") or {}) do
                if a.bIsAlive and C.valid(a.MyCharacterTemplate) then
                    local enemy=a.MyCharacterTemplate:GetFaction()
                    if C.valid(enemy) and C.valid(faction) and enemy:GetAttitudeTowardsFaction(faction)==2 then mark(a,"enemies") end
                end
            end
        end
    end
    for id,entry in pairs(self.marked) do
        if not C.instance(entry.mesh,entry.name) then
            self.marked[id]=nil
        elseif not desired[id] then
            self:restore_mark(entry)
            self.marked[id]=nil
        end
    end
    for id,entry in pairs(desired) do
        if not self.marked[id] then
            local original=entry.mesh.OverlayMaterial
            self.marked[id]={mesh=entry.mesh,name=entry.mesh:GetFullName(),original=original,
                original_name=C.valid(original) and original:GetFullName() or nil,category=entry.category}
        end
        self.marked[id].category=entry.category
        if not C.same(entry.mesh.OverlayMaterial,self.materials[entry.category]) then
            entry.mesh:SetOverlayMaterial(self.materials[entry.category])
        end
    end
    self:retain_overlays()
    if not self.reported_scan then
        self.reported_scan=true
        C.log(self.id,"Initial scan items="..counts.items.." containers="..counts.containers.." cellars="..counts.cellars.." enemies="..counts.enemies)
    end
end
return M
