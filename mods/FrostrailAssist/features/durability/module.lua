local M={title="耐久"}
-- Every native item durability rule. The game keeps one wear rate per world:
-- whichever of these registers last overwrites it, and removing one deletes it.
local rules={
    {name="GPR_PreservativeAtmosphere_C",path="/Game/Frostrail/Blueprints/Rules/GPR_PreservativeAtmosphere.GPR_PreservativeAtmosphere_C"},
    {name="GPR_CorrosiveAtmosphere_C",path="/Game/Frostrail/Blueprints/Rules/GPR_CorrosiveAtmosphere.GPR_CorrosiveAtmosphere_C"},
}

local function world(C,actor)
    local level=actor:GetLevel()
    return C.valid(level) and level.OwningWorld or nil
end

function M:protect(actor)
    local C=self.core
    if not self.cfg.devices or not C.pawn_valid() or not C.valid(actor) or not actor:HasAuthority()
        or not C.same(world(C,actor),world(C,C.player)) then return end
    -- Actual recycler derives from CraftingStationBase. Salvage props, the
    -- Eden engine, carriages and containers are deliberately outside this set.
    if not actor:IsA("/Script/Frostrail.CraftingStationBase")
        and not actor:IsA("/Script/Frostrail.TrainHeaterActorBase") then return end
    local repair=actor.RepairComponent
    if not C.valid(repair) or not repair.bEnableColdDamage then return end
    local name=repair:GetFullName()
    self.protected[name]={object=repair,name=name}
    repair.bEnableColdDamage=false
end

function M:restore_devices()
    local C=self.core
    for _,entry in pairs(self.protected or {}) do
        if C.instance(entry.object,entry.name) then entry.object.bEnableColdDamage=true end
    end
    self.protected={}
end

function M:scan()
    local C=self.core
    if not self.cfg.devices or not C.pawn_valid() or not C.player:HasAuthority() then return end
    for name,entry in pairs(self.protected) do
        if not C.instance(entry.object,entry.name) then self.protected[name]=nil end
    end
    for _,class in ipairs({"CraftingStationBase","TrainHeaterActorBase"}) do
        for _,actor in ipairs(FindAllOf(class) or {}) do self:protect(actor) end
    end
end

function M:reset()
    self:restore_devices()
    self.world,self.world_name=nil,nil
end

-- The option is fixed at startup and class defaults are never saved, so zero
-- every durability rule's default for the rest of the process: any activation,
-- before or after ours, then registers 0. Rules active before that still hold
-- their old rate and are re-created; with none active the world rate falls
-- back to 1, so the preservative rule is activated.
function M:apply_items(pc)
    local C=self.core
    if not self.items or not pc:HasAuthority() then return end
    local current=world(C,pc)
    if C.instance(self.world,self.world_name) and C.same(self.world,current) then return end
    if not self.rules then
        local classes={}
        for _,rule in ipairs(rules) do
            local class=LoadAsset(rule.path)
            assert(C.valid(class),"Missing native item durability rule "..rule.name)
            class:GetCDO().DurabilityRate=0
            classes[#classes+1]=class
        end
        self.rules=classes
        C.retain(self.id,classes)
    end
    local subsystems=C.class("/Script/Engine.Default__SubsystemBlueprintLibrary")
    local register=subsystems:GetWorldSubsystem(pc,C.class("/Script/Frostrail.GameplayRuleSubsystem")).GameplayRuleRegister
    local cheat=C.new("/Script/Frostrail.FrostrailCheatManager",pc)
    C.retain(self.id,{cheat,table.unpack(self.rules)})
    local ok,err=xpcall(function()
        local active={}
        for i,class in ipairs(self.rules) do
            if register:Contains(class) then active[#active+1]=i;cheat:DeactivateGameplayRule(rules[i].name) end
        end
        if #active==0 then active[1]=1 end
        for _,i in ipairs(active) do
            cheat:ActivateGameplayRule(rules[i].name)
            assert(register:Contains(self.rules[i]),"Native item durability rule activation failed: "..rules[i].name)
        end
    end,debug.traceback)
    C.retain(self.id,self.rules)
    if not ok then error(err) end
    self.world,self.world_name=current,current:GetFullName()
    C.log(C.id,"Item durability rate=0 for "..self.world_name)
end

function M:setup()
    -- Like loot generation, the native world's rule is selected at startup.
    -- Reloading another F8 setting must not silently change this choice.
    self.items=self.cfg.items
    self.protected={}
end
function M:init()
    local C=self.core
    RegisterLoadMapPreHook(function() C.run(C.id,function() self:reset() end) end)
    -- Player binding catches existing devices; the scan catches streamed or
    -- recreated ones well inside the native 5 s cold-exposure threshold, so no
    -- per-actor BeginPlay hook. The world owns these objects; Lua keeps identities.
    LoopInGameThreadWithDelay(1000,function()
        if not self.failed then C.run(C.id,function() self:scan() end) end
    end)
end
function M:player_ready(pc) self:apply_items(pc);self:scan() end
function M:player_left() self:restore_devices() end
function M:changed()
    if not self.cfg.devices then self:restore_devices() else self:scan() end
end
return M
