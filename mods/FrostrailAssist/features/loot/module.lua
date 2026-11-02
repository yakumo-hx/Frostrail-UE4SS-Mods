local M={title="物品生成"}
local rule_path="/Game/Frostrail/Blueprints/Rules/GPR_StacksOfStuff.GPR_StacksOfStuff_C"

local function asset_path(ref)
    return ref:GetObjectID():GetAssetPathName():ToString()
end

function M:reset()
    self.world,self.world_name=nil,nil
    -- Native level setup must see the original defaults before it rebuilds the
    -- selected rules. The retained class/CDO lives for this process only.
    if self.rule then
        local cdo=self.rule:GetCDO()
        cdo.StackSizeScale=self.original_quantity
        cdo.SpawnChanceScale=self.original_chance
    end
end

function M:apply(actor)
    local C=self.core
    local world=actor:GetLevel().OwningWorld
    if C.instance(self.world,self.world_name) and C.same(self.world,world) then return end
    local gs=self.game:GetGameState(actor)
    if not C.valid(gs) or not gs:IsA("/Script/Frostrail.FrostrailGameStateBase") then return end
    local descriptor=gs.GameplayLevelManager.CurrentGameplayLevelDescriptor
    assert(asset_path(descriptor.Level)~="None","Loot started before the level descriptor was ready")
    local selected=false
    descriptor.GameplayRules:ForEach(function(_,ref)
        if asset_path(ref:get())==rule_path then selected=true end
    end)
    if not self.rule then
        self.rule=LoadAsset(rule_path)
        assert(C.valid(self.rule),"Missing GPR_StacksOfStuff")
        C.retain(self.id,{self.rule})
        local cdo=self.rule:GetCDO()
        self.original_quantity,self.original_chance=cdo.StackSizeScale,cdo.SpawnChanceScale
    end
    local quantity=(selected and self.original_quantity or 1)*self.quantity
    local chance=(selected and self.original_chance or 1)*self.chance
    local cdo=self.rule:GetCDO()
    cdo.StackSizeScale,cdo.SpawnChanceScale=quantity,chance
    local pc=self.game:GetPlayerController(actor,0)
    assert(C.valid(pc) and pc:HasAuthority() and C.same(pc:GetLevel().OwningWorld,world),"No authority controller before loot generation")
    local subsystem=self.subsystems:GetWorldSubsystem(actor,C.class("/Script/Frostrail.GameplayRuleSubsystem"))
    -- This subsystem has no reflected activate/deactivate API. A temporary
    -- CheatManager uses the shipping native entry without enabling player cheats.
    local cheat=C.new("/Script/Frostrail.FrostrailCheatManager",pc)
    C.retain(self.id,{self.rule,cheat})
    if subsystem.GameplayRuleRegister:Contains(self.rule) then
        cheat:DeactivateGameplayRule("GPR_StacksOfStuff_C")
    end
    cheat:ActivateGameplayRule("GPR_StacksOfStuff_C")
    C.retain(self.id,{self.rule})
    assert(subsystem.GameplayRuleRegister:Contains(self.rule),"Native loot rule activation failed")
    self.world,self.world_name=world,world:GetFullName()
    C.log(C.id,"Loot scales before generation: quantity="..quantity.." chance="..chance
        .." selected="..tostring(selected).." world="..self.world_name)
end

function M:exact(component)
    local C=self.core
    local function multiply(entry)
        local item=entry.Item
        -- Exact bypasses the native StackSizeScale branch. Apply only the
        -- player's multiplier: vanilla StacksOfStuff never scales Exact counts.
        if entry.Type==1 and entry.ItemType==0 and C.valid(item) and item.bIsStackable and item.MaxStackSize>1 then
            -- A native pickup keeps only one stack (50 metal debris became 24
            -- without Capacity in LoadTest); cap the requested Exact count too.
            entry.Quantity=math.min(item.MaxStackSize,math.max(1,entry.Quantity)*self.quantity)
        end
    end
    if component.bMultipleLootEntries then
        component.Loots:ForEach(function(_,ref) multiply(ref:get()) end)
    else
        multiply(component.Loot)
    end
end

function M:before_spawn(actor)
    local C=self.core
    if not C.valid(actor) or not actor:HasAuthority() then return end
    local point=actor:IsA("/Script/Frostrail.ItemSpawnPoint") and actor.bSpawnOnBeginPlay
    local container=actor:IsA("/Script/Frostrail.LootContainer")
    if not point and not container and not actor:IsA("/Script/Frostrail.FrostrailGameStateBase") then return end
    self:apply(actor)
    if self.quantity==1 or (not point and not container) then return end
    if (point and actor.bInitialSpawnFinished) or (container and actor.bHasSpawnedLoot) then return end
    self:exact(actor.LootContextComponent)
end

function M:setup()
    local C=self.core
    -- These settings are fixed for the process, like farming recipes. Reloading
    -- another live Assist setting must not multiply existing Exact data again.
    self.quantity,self.chance=self.cfg.quantity_multiplier,self.cfg.chance_multiplier
    assert(type(self.quantity)=="number" and self.quantity>=1 and self.quantity<=10 and self.quantity%1==0,
        "Quantity multiplier must be an integer from 1 to 10")
    assert(type(self.chance)=="number" and self.chance>=1 and self.chance<=4,
        "Spawn chance multiplier must be between 1 and 4")
    if self.quantity==1 and self.chance==1 then return end
    self.game=C.class("/Script/Engine.Default__GameplayStatics")
    self.subsystems=C.class("/Script/Engine.Default__SubsystemBlueprintLibrary")
    local function run(fn,...)
        if self.failed then return end
        local ok,err=xpcall(fn,debug.traceback,self,...)
        if not ok then self.failed=true; C.log(C.id,"ERROR loot: "..err) end
    end
    RegisterLoadMapPreHook(function() run(self.reset) end)
    RegisterBeginPlayPreHook(function(ctx) run(self.before_spawn,ctx:get()) end)
end
return M
