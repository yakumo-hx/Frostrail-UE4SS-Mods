local M={title="伐木"}
local ability_path="/Game/Frostrail/GAS/Abilities/Items/Ability_Weapon_Melee.Ability_Weapon_Melee_C"
local stump_package="/Game/Mods/FrostrailWoodcutting/BP_WoodcuttingStump"
local stump_name="BP_WoodcuttingStump_C"
local efficiency={}
local function weapon(folder,name,value)
    local path="/Game/Frostrail/Data/Items/"..folder.."/ISCH_"..name
    efficiency[path..".ISCH_"..name]=value
end
weapon("Weapons/Clubs","Club_Scrap",30)
weapon("Weapons/Clubs","Club_Primitive",20)
for _,name in ipairs({"Crowbar_Metal","Crowbar_Scrap"}) do
    weapon("Tools/SalvageDeconstruct",name,name=="Crowbar_Metal" and 15 or 12)
end
for _,name in ipairs({"Hammer_Metal","Hammer_Scrap","Hammer_Primitive","Wrench_Metal","Wrench_Scrap"}) do
    weapon("Tools/BuildingRepairing",name,name:find("Metal",1,true) and 15 or 12)
end
local function path(o) return o:GetFullName():match("^%S+ (.+)$") end
local function vector(p) return {X=p.X,Y=p.Y,Z=p.Z} end
local function distance(a,b) return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2 end
function M:world(actor)
    local C=self.core
    local world=actor:GetLevel().OwningWorld
    -- Engine owns the world; cache only its identity, never tree components.
    if not C.instance(self.current_world,self.world_name) or not C.same(self.current_world,world) then
        self.current_world,self.world_name=world,world:GetFullName()
        self.progress={}
    end
    return world
end
function M:remove_tree(node)
    local C=self.core
    local world=node:GetLevel().OwningWorld
    local position=node:K2_GetActorLocation()
    for _,component in ipairs(FindAllOf("HierarchicalInstancedStaticMeshComponent") or {}) do
        if C.valid(component) and C.valid(component.StaticMesh) and self.trees[path(component.StaticMesh)] then
            local owner=component:GetOwner()
            if C.valid(owner) and C.same(owner:GetLevel().OwningWorld,world) then
                for _,ref in ipairs(component:GetInstancesOverlappingSphere(position,1,true)) do
                    local index=ref:get()
                    local transform={}
                    if component:GetInstanceTransform(index,transform,true) and distance(transform.Translation,position)<=1 then
                        component:RemoveInstance(index)
                        return
                    end
                end
            end
        end
    end
end
function M:give(pawn,schematic,quantity)
    if quantity<=0 then return end
    local C=self.core
    local system=pawn.ItemSystemComponent
    local bag=system:GetInventory()
    local created=C.class("/Script/Frostrail.Default__GameplayUtils"):CreateItems(bag,schematic,quantity)
    local items={}
    for _,ref in ipairs(created) do items[#items+1]=ref:get() end
    C.retain("woodcutting_rewards",items)
    local ok,err=xpcall(function()
        for _,item in ipairs(items) do system:StoreContainable(item,true) end
    end,debug.traceback)
    C.retain("woodcutting_rewards",{})
    if not ok then error(err) end
end
function M:hit(ability,hit)
    local C=self.core
    if not C.valid(ability) then return end
    local swing=ability:GetFullName()
    if self.swings[swing]~=false then return end
    local pawn=ability:GetAvatarActorFromActorInfo()
    if not C.valid(pawn) or not pawn:HasAuthority() then return end
    local source=ability:GetSourceItemSchematic()
    if not C.valid(source) then return end
    local component=hit.Component:Get()
    if not C.valid(component) or not component:IsA("/Script/Engine.HierarchicalInstancedStaticMeshComponent")
        or not C.valid(component.StaticMesh) then return end
    local mesh=path(component.StaticMesh)
    if not self.trees[mesh] then return end
    local owner=component:GetOwner()
    if not C.valid(owner) or not C.same(owner:GetLevel().OwningWorld,self:world(pawn)) then return end
    local t={}
    if hit.Item<0 or not component:GetInstanceTransform(hit.Item,t,true) then return end
    self.swings[swing]=true
    -- Pure values survive HISM reindexing, weapon changes and actor virtualization.
    local entries=self.progress[mesh] or {}
    self.progress[mesh]=entries
    local entry
    for _,candidate in ipairs(entries) do
        if distance(candidate.position,t.Translation)<=1 then entry=candidate;break end
    end
    if not entry then entry={position=vector(t.Translation),value=0};entries[#entries+1]=entry end
    if entry.value>=120 then return end
    entry.value=entry.value+(efficiency[path(source)] or 8)
    if entry.value<120 then return end
    local transform={Translation=vector(t.Translation),
        Rotation={X=t.Rotation.X,Y=t.Rotation.Y,Z=t.Rotation.Z,W=t.Rotation.W},
        Scale3D={X=1,Y=1,Z=1}}
    local pawn_name=pawn:GetFullName()
    local world,world_name=self.current_world,self.world_name
    local logs,branches=self.cfg.logs,self.cfg.branches
    -- Leave the melee sweep before spawning: the stump's BeginPlay changes HISM
    -- collision. No timer or forest-readiness retry is involved.
    ExecuteInGameThread(function()
        C.run(self.id,function()
            if not C.instance(pawn,pawn_name) or not C.instance(world,world_name)
                or not C.same(pawn:GetLevel().OwningWorld,world) then return end
            local game=C.class("/Script/Engine.Default__GameplayStatics")
            local node=game:BeginDeferredActorSpawnFromClass(pawn,self.stump,transform,1,nil,0)
            assert(C.valid(node),"Could not spawn woodcutting stump")
            game:FinishSpawningActor(node,transform,0)
            self:give(pawn,self.log_item,logs)
            self:give(pawn,self.branch_item,branches)
            C.log(self.id,"Felled "..mesh.." at "..entry.position.X..","..entry.position.Y..","..entry.position.Z)
        end)
    end)
end
function M:setup()
    local C=self.core
    self.trees=dofile(self.dir.."/trees.lua")
    self.swings={}
    self.progress={}
    -- Register before player binding: saved nodes can begin play before the pawn.
    -- This is the only removal path, on host and client alike. No delayed retry.
    RegisterBeginPlayPostHook(function(ctx)
        local actor=ctx:get()
        if C.valid(actor) and path(actor:GetClass())==stump_package.."."..stump_name then
            C.run(self.id,function() self:remove_tree(actor) end)
        end
    end)
end
function M:init()
    local C=self.core
    local library=C.class("/Script/Engine.Default__KismetSystemLibrary")
    local ref=library:Conv_SoftObjPathToSoftObjRef({AssetPath={PackageName=FName(stump_package),AssetName=FName(stump_name)}})
    self.stump=library:LoadAsset_Blocking(ref)
    assert(C.valid(self.stump),"Woodcutting stump asset missing")
    self.log_item=LoadAsset("/Game/Frostrail/Data/Items/Resources/Nature/ISCH_Log_01.ISCH_Log_01")
    self.branch_item=LoadAsset("/Game/Frostrail/Data/Items/Resources/Nature/ISCH_Branch_01.ISCH_Branch_01")
    local ability=LoadAsset(ability_path)
    C.retain("woodcutting_assets",{self.stump,self.log_item,self.branch_item,ability})
    C.script_hook(ability_path..":K2_ActivateAbility",function(ctx) self.swings[ctx:get():GetFullName()]=false end)
    C.script_hook(ability_path..":K2_OnEndAbility",function(ctx) self.swings[ctx:get():GetFullName()]=nil end)
    C.script_hook(ability_path..":HandleGenericHitNotify",function(ctx,hit)
        C.run(self.id,function() self:hit(ctx:get(),hit:get()) end)
    end)
end
return M
