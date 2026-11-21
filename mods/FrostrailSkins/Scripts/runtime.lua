local C=...
local pose=dofile(C.dir.."/Scripts/pose.lua")
local R={}
local system=C.class("/Script/Engine.Default__KismetSystemLibrary")
local renderer=C.class("/Script/Engine.Default__KismetRenderingLibrary")
local skeletal=C.class("/Script/Engine.SkeletalMeshComponent")
local poseable=C.class("/Script/Engine.PoseableMeshComponent")
local none=FName("None")
local handSockets={S_Weapon_R=FName("S_Weapon_R"),S_Weapon_L=FName("S_Weapon_L")}
local identity={Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
local materialPath="/Game/Frostrail/SkeletalMeshes/BaseBody_Skeleton/Materials/Clothes/Player/Tier2/LeatherSet/MI_Player_Leather_Set_01"
local backSlotPath="/Game/Frostrail/Data/Types/EquipmentSlots/EquipmentSlot_Back.EquipmentSlot_Back_C"
local inventoryPath="/Game/Frostrail/UI/Widgets/Composites/WBP_Composite_Inventory+Status.WBP_Composite_Inventory+Status_C"
local hudPath="/Game/Frostrail/UI/BP_FrostrailHUD.BP_FrostrailHUD_C"
local assets,retained,rigs={},{},{}
local firstPersonAssets={}
local pawn,worldSkin,previewSkin,showWorldBack,showPreviewBack
local views,displays={},{}
local driver,refreshTimer,refreshQueued,hooks,inventorySwitcher
local syncDriver

local function remember(object)
    return {object=object,name=object:GetFullName()}
end
local function alive(entry)
    return entry and C.instance(entry.object,entry.name)
end

-- These are package resources, never actors, components or widgets. The
-- rooted ObjectLibrary is shared with the first-person path for this VM.
local function keep(path,object)
    assert(C.valid(object),"Missing skin resource "..path)
    retained[#retained+1]=object
    C.retain("skin_resources",retained)
    assets[path]=object
    return object
end
function R.loadMesh(path)
    if assets[path] then return assets[path] end
    local key=path:match("[^/]+$")
    local ref=system:Conv_SoftObjPathToSoftObjRef({AssetPath={PackageName=FName(path),AssetName=FName(key)}})
    return keep(path,system:LoadAsset_Blocking(ref))
end
function R.loadFirstPersonMesh(path)
    local mesh=R.loadMesh(path)
    -- The asset library owns this mesh for the lifetime of the Lua VM.
    firstPersonAssets[mesh:GetAddress()]=true
    return mesh
end
local function texture(path)
    return assets[path] or keep(path,renderer:ImportFileAsTexture2D(C.player,C.dir.."/"..path))
end
function R.shade(component,skin)
    local mat=component:CreateDynamicMaterialInstance(0,R.loadMesh(materialPath),none)
    assert(C.valid(mat),"Could not create skin material")
    mat:SetTextureParameterValue(FName("BaseColor"),texture(skin.albedo))
    mat:SetTextureParameterValue(FName("CRMS"),texture(skin.surface))
    -- The leather parent's normal map still imprints its grain on the face
    -- and hands with Normal Strength at zero in the shipping material.
    mat:SetTextureParameterValue(FName("Normal"),R.loadMesh("/Engine/EngineMaterials/FlatNormal"))
    for _,parameter in ipairs({"Normal Strength","TintIntensity","SnowAmount","Cloth Tears"}) do
        mat:SetScalarParameterValue(FName(parameter),0)
    end
    return mat
end

local function backMesh(owner)
    local items=owner.ItemSystemComponent
    if not C.valid(items) then return end
    local class=assets[backSlotPath] or keep(backSlotPath,LoadAsset(backSlotPath))
    local slot=items:GetEquipmentSlotOfClass(class)
    if not C.valid(slot) then return end
    local state=slot:GetEquippedItemState()
    if not C.valid(state) or not C.valid(state.OwnerItem) then return end
    local actor=state.OwnerItem.LinkedItemActor
    if C.valid(actor) and C.same(actor:GetOwner(),owner) then return actor:GetMesh() end
end

-- The native display builder skips source components whose bVisible is
-- false. Keep it and the mesh asset intact while suppressing the world draw.
local drawFlags={
    {"bRenderInMainPass","SetRenderInMainPass"},{"bRenderInDepthPass","SetRenderInDepthPass"},
    {"CastShadow","SetCastShadow"},{"bVisibleInRayTracing","SetVisibleInRayTracing"},
    {"bRenderCustomDepth","SetRenderCustomDepth"},
}
local function restoreDraw(entry)
    if not alive(entry) then return end
    local c=entry.object
    if entry.flags then
        for i,flag in ipairs(drawFlags) do
            if c[flag[1]]~=entry.flags[i] then c[flag[2]](c,entry.flags[i]) end
        end
    elseif c.bVisible~=entry.visible then
        c:SetVisibility(entry.visible,false)
    end
end

local function hide(view,component,seen)
    if not C.valid(component) then return end
    local name=component:GetFullName()
    seen[name]=true
    local entry=view.hidden[name]
    if not alive(entry) or not C.same(entry.object,component) then
        entry=remember(component)
        view.hidden[name]=entry
        if view.world then
            entry.flags={}
            for i,flag in ipairs(drawFlags) do entry.flags[i]=component[flag[1]] end
        else
            entry.visible=component.bVisible
        end
    end
    if view.world then
        for _,flag in ipairs(drawFlags) do
            if component[flag[1]] then component[flag[2]](component,false) end
        end
    elseif component.bVisible then
        component:SetVisibility(false,false)
    end
end

local function restoreHeld(view,item)
    if alive(item) and alive(view.follower) and alive(view.leader)
        and C.same(item.object:GetAttachParent(),view.follower.object) then
        item.object:K2_AttachToComponent(view.leader.object,item.socket,0,0,0,false)
    end
end

local function release(key)
    local view=views[key]
    if not view then return end
    views[key]=nil
    for _,item in pairs(view.held or {}) do restoreHeld(view,item) end
    if alive(view.follower) and alive(view.owner) then
        view.follower.object:K2_DestroyComponent(view.owner.object)
    end
    if alive(view.leader) then view.leader.object.VisibilityBasedAnimTickOption=view.tickOption end
    for _,entry in pairs(view.hidden) do restoreDraw(entry) end
end

local function attach(key,owner,leader,skin,world)
    if not rigs[skin.id] then rigs[skin.id]=pose.read(C,skin) end
    local mesh=R.loadMesh(skin.mesh)
    local ref=owner:AddComponentByClass(poseable,true,identity,false)
    assert(C.valid(ref),"Could not create skin mesh")
    local view={owner=remember(owner),leader=remember(leader),follower=remember(ref),skin=skin,
        world=world,hidden={},tickOption=leader.VisibilityBasedAnimTickOption,rig=rigs[skin.id]}
    views[key]=view
    local ok,err=pcall(function()
        ref:SetCollisionEnabled(0)
        ref:K2_AttachToComponent(leader,none,2,2,2,false)
        ref:SetSkinnedAssetAndUpdate(mesh,true)
        R.shade(ref,skin)
        ref:SetCastShadow(leader.CastShadow)
        if world then
            ref:SetCastHiddenShadow(leader.bCastHiddenShadow)
            ref:SetFirstPersonPrimitiveType(leader.FirstPersonPrimitiveType)
        end
        leader.VisibilityBasedAnimTickOption=0 -- the visible follower needs its hidden leader's bones
        pose.update(view.rig,leader,ref)
    end)
    if not ok then release(key); error(err) end
    return view
end

local function syncHeld(view,parts)
    local leader,follower=view.leader.object,view.follower.object
    local held={}
    for _,part in ipairs(parts) do
        local parent=part:GetAttachParent()
        local socket=handSockets[part:GetAttachSocketName():ToString()]
        if C.same(parent,follower) or (C.same(parent,leader) and follower:DoesSocketExist(socket)
            and part:K2_AttachToComponent(follower,socket,0,0,0,false)) then
            local item=remember(part)
            item.socket=socket
            held[item.name]=item
        end
    end
    for key,item in pairs(view.held or {}) do
        if not held[key] then restoreHeld(view,item) end
    end
    view.held=held
    local carrying=next(held)~=nil
    if carrying~=view.carrying then
        if carrying then pose.hold(C,view.rig,follower)
        elseif view.carrying then pose.update(view.rig,leader,follower) end
    end
    view.carrying=carrying
end

local function viewFor(key,owner,leader,skin,world)
    if not skin or not C.valid(owner) or not C.valid(leader) then release(key); return end
    local view=views[key]
    if view and view.skin==skin and alive(view.owner) and alive(view.leader) and alive(view.follower)
        and C.same(owner,view.owner.object) and C.same(leader,view.leader.object) then return view end
    release(key)
    return attach(key,owner,leader,skin,world)
end

local function finishHide(view,seen)
    for name,entry in pairs(view.hidden) do
        if not seen[name] then restoreDraw(entry); view.hidden[name]=nil end
    end
end

local function syncWorld(owner)
    local leader=owner.Mesh
    local view=viewFor("world",owner,leader,worldSkin,true)
    if not view then return end
    local follower=view.follower.object
    if follower.bOwnerNoSee~=leader.bOwnerNoSee then follower:SetOwnerNoSee(leader.bOwnerNoSee) end
    if follower.bOnlyOwnerSee~=leader.bOnlyOwnerSee then follower:SetOnlyOwnerSee(leader.bOnlyOwnerSee) end
    if follower.bVisible~=leader.bVisible then follower:SetVisibility(leader.bVisible,false) end
    if follower.bHiddenInGame~=leader.bHiddenInGame then follower:SetHiddenInGame(leader.bHiddenInGame,false) end
    local seen={}
    hide(view,leader,seen)
    hide(view,owner.HeadComponent,seen)
    hide(view,owner.TorsoComponent,seen)
    hide(view,owner.LegsComponent,seen)
    if not showWorldBack then hide(view,backMesh(owner),seen) end
    finishHide(view,seen)
end

local function syncPreview(display,owner)
    local key=display:GetFullName()
    local proxy=display.DisplayedActor
    local body=C.valid(proxy) and proxy.BodyMesh or nil
    local view=viewFor(key,proxy,body,previewSkin,false)
    local outfits={}
    local seen={}
    local held={}
    if view then
        if not view.stage then view.stage=display:GetLevel().OwningWorld:GetFName():ToString() end
        for _,field in ipairs({"HeadComponent","TorsoComponent","LegsComponent"}) do
            local part=owner[field]
            if C.valid(part) then
                local mesh=part:GetSkinnedAsset()
                if C.valid(mesh) then outfits[mesh:GetAddress()]=true end
            end
        end
        hide(view,body,seen)
    end
    if not C.valid(proxy) then return end
    proxy.MirroredMeshes:ForEach(function(_,val)
        local part=val:get()
        if not C.valid(part) then return end
        local socket=part:GetAttachSocketName():ToString()
        if socket=="S_Back" then
            if view and not showPreviewBack then hide(view,part,seen) end
        elseif view and handSockets[socket] then
            held[#held+1]=part
        elseif part:IsA(skeletal) then
            local mesh=part:GetSkinnedAsset()
            if C.valid(mesh) then
                local id=mesh:GetAddress()
                if socket=="None" and firstPersonAssets[id] then
                    -- Native rebuilt the first-person follower as a plain mesh in
                    -- this proxy. It is extraneous for every selection, including
                    -- Original. Leave it invisible until native frees the mirror.
                    if part.bVisible then part:SetVisibility(false,false) end
                elseif view and outfits[id] then hide(view,part,seen) end
            end
        end
    end)
    if view then
        syncHeld(view,held)
        finishHide(view,seen)
    end
end

local function refresh()
    if not alive(pawn) or not C.pawn_valid() or not C.same(C.pawn,pawn.object) then R.clear(); return end
    local owner=pawn.object
    syncWorld(owner)
    if not previewSkin and not next(firstPersonAssets) then
        for key in pairs(views) do if key~="world" then release(key) end end
        inventorySwitcher=nil
        syncDriver()
        return
    end
    local count=0
    for key,entry in pairs(displays) do
        if alive(entry) and C.same(entry.object.BoundCharacter:Get(),owner) then count=count+1
        else release(key); displays[key]=nil end
    end
    if count<2 then
        for _,display in ipairs(FindAllOf("BP_Player_Display_C") or {}) do
            if C.valid(display) and C.same(display.BoundCharacter:Get(),owner) then
                displays[display:GetFullName()]=remember(display)
            end
        end
    end
    for _,entry in pairs(displays) do syncPreview(entry.object,owner) end
    local hud=C.player:GetHUD()
    inventorySwitcher=nil
    if C.valid(hud) then
        hud.WidgetStack:ForEach(function(_,ref)
            local page=ref:get()
            if C.valid(page) and page:IsA(inventoryPath) and C.valid(page.ContentSwitcher) then
                inventorySwitcher=remember(page.ContentSwitcher)
                return true
            end
        end)
    end
    syncDriver()
end

local function worldCouldShow(view)
    if not view or not alive(view.follower) then return false end
    local ref=view.follower.object
    if not ref.bCastHiddenShadow and (not ref.bVisible or ref.bHiddenInGame) then return false end
    return not ref.bOwnerNoSee or ref.bCastHiddenShadow or not C.same(C.player:GetViewTarget(),pawn.object)
end

local function animate()
    if not alive(pawn) or not C.pawn_valid() then driver=nil; return end
    -- ContentSwitcher slots in WBP_Composite_Inventory+Status. The skin page
    -- opens over Status and uses that same render target.
    local index=alive(inventorySwitcher) and inventorySwitcher.object:GetActiveWidgetIndex()
    local activeStage=index==0 and "MultiWorld_Player" or index==4 and "MultiWorld_PlayerRime" or nil
    for _,view in pairs(views) do
        local visible
        if view.world then visible=worldCouldShow(view) and view.follower.object:WasRecentlyRendered(0.20)
        else visible=not view.carrying and activeStage~=nil and view.stage==activeStage and alive(view.follower) end
        if visible and alive(view.leader) then pose.update(view.rig,view.leader.object,view.follower.object) end
    end
end
syncDriver=function()
    if not (previewSkin and inventorySwitcher) and not worldCouldShow(views.world) then driver=nil; return end
    if driver then return end
    -- Retiring this token cancels an already queued frame on close, travel
    -- or rebinding. EngineTick queues at most one sample per engine frame.
    local token={}
    driver=token
    local function frame()
        if driver~=token then return end
        C.run(C.id,animate)
        if driver==token then ExecuteInGameThread(frame,EGameThreadMethod.EngineTick) end
    end
    ExecuteInGameThread(frame,EGameThreadMethod.EngineTick)
end
local function requestRefresh()
    if refreshQueued or not pawn or not (refreshTimer or next(firstPersonAssets)) then return end
    local binding=pawn
    refreshQueued=true
    ExecuteInGameThread(function()
        if pawn~=binding then return end
        refreshQueued=nil
        C.run(C.id,refresh)
    end,EGameThreadMethod.EngineTick)
end
local function watch()
    if hooks then return end
    hooks=true
    C.hook("/Script/Frostrail.CharacterDisplayActor:HandleEquipmentSlotChanged",nil,function(ctx)
        if alive(pawn) and C.same(ctx:get().BoundCharacter:Get(),pawn.object) then requestRefresh() end
    end)
    LoadAsset(hudPath)
    C.script_hook(hudPath..":OnWidgetStackChanged",function() requestRefresh() end)
end
local function stopTimers()
    driver=nil
    if refreshTimer then CancelDelayedAction(refreshTimer); refreshTimer=nil end
    refreshQueued=nil
end

function R.clear()
    stopTimers()
    for key in pairs(views) do release(key) end
    pawn,displays,inventorySwitcher=nil,{},nil
end
local function apply()
    if not pawn then return end
    refresh()
    if not pawn or not (worldSkin or previewSkin) then stopTimers(); return end
    if not refreshTimer then
        -- The game's deferred preview build can replace BodyMesh after its
        -- equipment event, including while the inventory is closed.
        refreshTimer=LoopInGameThreadWithDelay(300,function() C.run(C.id,refresh) end)
    end
end
function R.set(world,preview,worldBack,previewBack)
    worldSkin,previewSkin,showWorldBack,showPreviewBack=world,preview,worldBack,previewBack
    apply()
end

-- Traveling with the inventory open can leave its two background worlds alive:
-- each still has the last proxy, but both weak character references are empty.
-- A new inventory then reuses those worlds without running the displays' BeginPlay.
local function repairPreviews(pc,owner)
    local game=C.class("/Script/Engine.Default__GameplayStatics")
    local multi=C.class("/Script/MultiWorld.Default__MultiWorldStatics")
    local instance=game:GetGameInstance(pc)
    local abandoned={}
    local pending={}
    for _,display in ipairs(FindAllOf("BP_Player_Display_C") or {}) do
        if C.valid(display) and not C.valid(display.SourceCharacter:Get())
            and C.valid(display.DisplayedActor) and C.valid(display.DisplayedActor.BodyMesh)
            and C.same(instance,game:GetGameInstance(display)) then
            local stage=display:GetLevel().OwningWorld:GetFName():ToString()
            if stage=="MultiWorld_Player" or stage=="MultiWorld_PlayerRime" then
                local bound=display.BoundCharacter:Get()
                if not C.valid(bound) then
                    local handle=multi:GetThisWorldHandle(display)
                    if multi:IsValidHandle(pc,handle) then abandoned[stage]=handle end
                elseif not C.same(bound,owner) then
                    pending[#pending+1]=remember(display)
                end
            end
        end
    end
    for stage,handle in pairs(abandoned) do
        multi:EndWorld(pc,handle)
        C.log(C.id,"Released previous campaign's unbound preview "..stage)
    end
    if #pending==0 then return end
    local binding=pawn
    local function rebind()
        if pawn~=binding or not alive(binding) or not C.player_valid() then return end
        local items=owner.ItemSystemComponent
        local slot=assets[backSlotPath] or keep(backSlotPath,LoadAsset(backSlotPath))
        if not C.same(game:GetPlayerCharacter(pc,0),owner) or not C.valid(items)
            or not C.valid(items:GetEquipmentSlotOfClass(slot)) then
            ExecuteInGameThreadWithDelay(100,rebind)
            return
        end
        for _,entry in ipairs(pending) do
            if alive(entry) and not C.same(entry.object.BoundCharacter:Get(),owner) then
                entry.object:HandleEquipmentSlotChanged(nil,nil)
            end
        end
    end
    rebind()
end

function R.bind(owner)
    R.clear()
    if not C.valid(owner) or not C.player_valid() or not C.player:IsLocalController() then return end
    pawn=remember(owner)
    repairPreviews(C.player,owner)
    watch()
    apply()
end

return R
