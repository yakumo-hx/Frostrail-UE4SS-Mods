local M={title="尸变"}
local template_path="/Game/Frostrail/Data/Characters/Revenant/CT_Revenant_Basic_Tier1.CT_Revenant_Basic_Tier1"
local animation_path="/Game/Frostrail/SkeletalMeshes/BaseBody_Skeleton/Animations/NPCs/Revenant/MT_Revenant_Get_Up_"
local throw_class="/Game/Frostrail/GAS/Abilities/AI/Revenant/Ability_Revenant_Basic_ThrowJavelin.Ability_Revenant_Basic_ThrowJavelin_C"
local function vector(p) return {X=p.X,Y=p.Y,Z=p.Z} end
local function entries(inv)
    local slots,items={},{}
    inv:GetAllPopulatedSlots(slots,true)
    for _,ref in ipairs(slots) do items[#items+1]=inv:GetContainableInSlot({ID=ref:get().ID}) end
    return items
end
local looks={
    {id="revenant",apply=function() end},
    {id="self",apply=function(C,enemy,corpse)
        enemy.Mesh:SetSkeletalMeshAsset(corpse.Mesh:GetSkeletalMeshAsset())
        for i=0,corpse.Mesh:GetNumMaterials()-1 do enemy.Mesh:SetMaterial(i,corpse.Mesh:GetMaterial(i)) end
        for _,field in ipairs({"HeadComponent","TorsoComponent","LegsComponent"}) do
            local source=corpse[field]
            local mesh=enemy:AddComponentByClass(C.class("/Script/Engine.SkeletalMeshComponent"),true,
                {Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}},false)
            mesh:K2_AttachToComponent(enemy.Mesh,FName("None"),2,2,2,false)
            mesh:SetSkeletalMeshAsset(source:GetSkeletalMeshAsset())
            for i=0,source:GetNumMaterials()-1 do mesh:SetMaterial(i,source:GetMaterial(i)) end
            mesh:SetLeaderPoseComponent(enemy.Mesh,true,false)
        end
    end}
}
function M:fix_corpse(actor)
    local C=self.core
    if not C.valid(actor) or not actor:HasAuthority() or actor.bIsAlive
        or not actor:IsA("/Script/Frostrail.AICharacter") then return end
    local inv=actor.CorpseContainerComp:GetInventory()
    local count=inv:GetPopulatedSlotCount()
    if count>inv:GetInventorySize() then
        inv.InventoryRecord.InventorySize=count
        C.log(self.id,"Restored corpse capacity to "..count..": "..actor:GetFullName())
    end
end
function M:trace(context,start,finish,ignored)
    local hit={}
    local blocked=self.system:LineTraceSingle(context,start,finish,0,false,ignored,0,hit,true,{},{},0)
    return blocked,hit
end
function M:pose(corpse,player)
    local pelvis=corpse.Mesh:GetSocketTransform(FName("pelvis"),0)
    if corpse.bIsAlive then
        return vector(pelvis.Translation),"STANDING",self.math:FindLookAtRotation(pelvis.Translation,player:K2_GetActorLocation()).Yaw
    end
    local rotation=self.math:Quat_Rotator(pelvis.Rotation)
    -- Standing-player calibration: local -Y is chest-facing; local -X points
    -- toward the head. Chest projection alone cannot specify a flat body's yaw.
    local chest=self.math:GetRightVector(rotation)
    local side=chest.Z<0 and "BACK" or "FRONT"
    local head=corpse.Mesh:GetSocketLocation(FName("head"))
    local heading=self.math:FindLookAtRotation(pelvis.Translation,head).Yaw
    -- At yaw zero, FRONT begins head toward -X, BACK toward +X (about 16 deg
    -- lateral head bend in both poses). Align the measured head/pelvis vector.
    local yaw=heading-(side=="FRONT" and -163.24 or 15.47)
    return vector(pelvis.Translation),side,yaw
end
function M:transfer(source,target)
    local items=entries(source)
    target.InventoryRecord.InventorySize=math.max(target:GetInventorySize(),#items)
    local moved={}
    for _,item in ipairs(items) do
        -- Ignore condensation until the transaction ends so rollback retains room.
        -- -1 transfers the same item; a positive count recreates durability state.
        if not target:TransferContainable(source:FindContainableSlot(item),source,target:GetFreeSlot(item),-1,true,true) then
            for i=#moved,1,-1 do
                local back=moved[i]
                assert(source:TransferContainable(target:FindContainableSlot(back),target,source:GetFreeSlot(back),-1,true,true),
                    "Could not return relic; preserving both actors")
            end
            return false
        end
        moved[#moved+1]=item
    end
    return true
end
function M:awaken(corpse,player)
    local C=self.core
    local pelvis,side,yaw=self:pose(corpse,player)
    local ground,hit=self:trace(corpse,pelvis,{X=pelvis.X,Y=pelvis.Y,Z=pelvis.Z-2000},{corpse})
    if not ground then return end
    local enemy=self.util:SpawnCharacterFromTemplate(corpse,self.template,
        {Rotation=self.math:Conv_RotatorToQuaternion({Pitch=0,Yaw=yaw,Roll=0}),
            Translation=vector(hit.Location),Scale3D={X=1,Y=1,Z=1}},true,nil)
    if not C.valid(enemy) then return end
    enemy:GetController().BrainComponent:StopLogic("Reanimation get-up")
    local bag=enemy.ItemSystemComponent:GetInventory()
    for _,item in ipairs(entries(bag)) do bag:RemoveContainableFromSlot(bag:FindContainableSlot(item)) end
    local remove={}
    enemy.AbilitySystemComponent.ActivatableAbilities.Items:ForEach(function(_,ref)
        local spec=ref:get()
        if C.valid(spec.Ability) and spec.Ability:IsA(throw_class) then remove[#remove+1]={Handle=spec.Handle.Handle} end
    end)
    for _,handle in ipairs(remove) do enemy.AbilitySystemComponent:ClearAbility(handle) end
    local look
    if self.cfg.look=="random" then look=looks[math.random(1,#looks)]
    else for _,option in ipairs(looks) do if option.id==self.cfg.look then look=option;break end end end
    look.apply(C,enemy,corpse)
    if not self:transfer(corpse.CorpseContainerComp:GetInventory(),bag) then enemy:K2_DestroyActor();return end
    corpse:K2_DestroyActor()
    if side~="STANDING" then enemy["Event PlaySpawnAnimServer"](enemy,self.montages[side]) end
    enemy:PlaySoundReplicated(self.scream)
    if side=="STANDING" then enemy:BP_StartNormalBehavior() end
    C.log(self.id,"Reanimated "..side.." look="..look.id..": "..enemy:GetFullName())
    return enemy
end
function M:scan()
    local C=self.core
    if not C.player_valid() or not C.player:HasAuthority() then return end
    local world=C.player:GetLevel().OwningWorld
    if not C.instance(self.world,self.world_name) or not C.same(self.world,world) then
        self.world,self.world_name=world,world:GetFullName()
        self.rolled={}
    end
    local actors,players,corpses={},{},{}
    self.game:GetAllActorsOfClass(C.player,C.class("/Script/Frostrail.PlayerCharacter"),actors)
    for _,ref in ipairs(actors) do
        local actor=ref:get()
        if C.valid(actor) then
            local controlled=C.valid(actor:GetController())
            if controlled and actor.bIsAlive then players[#players+1]=actor
            -- CorpsePlayerId is saved by the native death path; losing a
            -- controller alone does not turn a living player into a corpse.
            elseif not controlled and actor.CorpsePlayerId~=0 then corpses[#corpses+1]=actor end
        end
    end
    for _,corpse in ipairs(corpses) do
        local name=corpse:GetFullName()
        if not self.rolled[name] then
            local pelvis=corpse.Mesh:GetSocketLocation(FName("pelvis"))
            for _,player in ipairs(players) do
                local at=player:K2_GetActorLocation()
                local dx,dy,dz=at.X-pelvis.X,at.Y-pelvis.Y,at.Z-pelvis.Z
                if math.abs(dz)<=200 and dx*dx+dy*dy+dz*dz<=400*400 then
                    local eyes={X=at.X,Y=at.Y,Z=at.Z+player.BaseEyeHeight}
                    local blocked=self:trace(player,eyes,pelvis,{player,corpse})
                    if not blocked then
                        self.rolled[name]=true
                        if math.random(1,100)<=self.cfg.chance then self:awaken(corpse,player) end
                        break
                    end
                end
            end
        end
    end
end
function M:setup()
    local C=self.core
    self.rolled={}
    -- The native death-state delegate is broadcast after inventory allocation.
    C.hook("/Script/Frostrail.FrostrailAIController:OnPossessedAliveStateChanged",nil,function(ctx)
        C.run(self.id,function() self:fix_corpse(ctx:get():K2_GetPawn()) end)
    end)
end
function M:init()
    local C=self.core
    self.game=C.class("/Script/Engine.Default__GameplayStatics")
    self.system=C.class("/Script/Engine.Default__KismetSystemLibrary")
    self.math=C.class("/Script/Engine.Default__KismetMathLibrary")
    self.util=C.class("/Script/Frostrail.Default__GameplayUtils")
    self.template=LoadAsset(template_path)
    self.scream=LoadAsset("/Game/FMOD/Events/Character/Revenant/Character_Revenant_Scream.Character_Revenant_Scream")
    self.montages={}
    local assets={self.template,self.scream}
    for _,side in ipairs({"FRONT","BACK"}) do
        self.montages[side]=LoadAsset(animation_path..side..".MT_Revenant_Get_Up_"..side)
        assets[#assets+1]=self.montages[side]
    end
    C.retain("reanimation_assets",assets)
    -- World owns actors. Retain only assets; roll history is
    -- names in this world, never UObject wrappers, and survives local respawns.
    LoopInGameThreadWithDelay(250,function() C.run(self.id,function() self:scan() end) end)
end
return M
