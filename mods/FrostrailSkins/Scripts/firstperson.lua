local C,R=...
local FP={}
local pawn,pawnName,skin
local stanceBody
local pieces={}
local originals={}
local fields={"FirstPersonMesh","FirstPersonHeadComponent","FirstPersonTorsoComponent","FirstPersonLegsComponent"}
local identity={
    Rotation={X=0,Y=0,Z=0,W=1},
    Translation={X=0,Y=0,Z=0},
    Scale3D={X=1,Y=1,Z=1}
}

local function restore(original)
    if original and C.instance(original.component,original.name) then
        original.component:SetRenderInMainPass(original.mainPass)
        original.component:SetRenderInDepthPass(original.depthPass)
    end
end

local function remove()
    stanceBody=nil
    if C.instance(pawn,pawnName) then
        for _,piece in pairs(pieces) do
            if C.instance(piece.mesh,piece.name) then piece.mesh:K2_DestroyComponent(pawn) end
        end
    end
    pieces={}
    for _,original in pairs(originals) do restore(original) end
    originals={}
end

local function suppress(field)
    local component=pawn[field]
    local original=originals[field]
    if original and not (C.instance(original.component,original.name) and C.same(original.component,component)) then
        restore(original)
        originals[field]=nil
        original=nil
    end
    if not C.valid(component) then return end
    if not original then
        originals[field]={component=component,name=component:GetFullName(),
            mainPass=component.bRenderInMainPass,depthPass=component.bRenderInDepthPass}
    end
    -- Keep the stock meshes, animation graph, visibility decisions and weapon children intact.
    if component.bRenderInMainPass then component:SetRenderInMainPass(false) end
    if component.bRenderInDepthPass then component:SetRenderInDepthPass(false) end
end

local function attach(key,leader,path)
    local asset=R.loadFirstPersonMesh(path)
    local mesh=pawn:AddComponentByClass(C.class("/Script/Engine.SkeletalMeshComponent"),true,identity,false)
    assert(C.valid(mesh),"Could not attach first-person skin "..path)
    pieces[key]={mesh=mesh,name=mesh:GetFullName(),leader=leader,leaderName=leader:GetFullName()}
    mesh:SetCollisionEnabled(0)
    mesh:SetCastShadow(false)
    mesh:SetOnlyOwnerSee(true)
    mesh:SetFirstPersonPrimitiveType(leader.FirstPersonPrimitiveType)
    mesh:K2_AttachToComponent(leader,FName("None"),2,2,2,false)
    if key=="body" and skin.firstPersonBodyLean then
        -- Lean away from the camera around the foot-level mesh origin. Moving the
        -- whole body backwards also moves the boots out of the look-down view.
        mesh:K2_SetRelativeRotation({Pitch=0,Yaw=0,Roll=skin.firstPersonBodyLean},false,{},true)
    end
    mesh:SetSkeletalMeshAsset(asset)
    mesh:SetLeaderPoseComponent(leader,true,false)
    R.shade(mesh,skin)
end

local function follows(piece,leader)
    return piece and C.instance(piece.mesh,piece.name) and C.instance(piece.leader,piece.leaderName)
        and C.same(piece.leader,leader)
end

local function watchStance()
    local body=pieces.body
    if not body or stanceBody==body then return end
    stanceBody=body
    local previous
    local status={}
    local function frame()
        -- remove() retires this piece on a skin change, travel or rebind.
        if stanceBody~=body then return end
        if not C.valid(pawn) or not body.mesh:IsValid() then stanceBody=nil; return end
        C.player:IsDowned(status)
        local hidden=status.bIsDowned or (skin.hideFirstPersonBodyWhenCrouched and pawn.bIsCrouched) or false
        if hidden~=previous then
            if not C.instance(pawn,pawnName) or not C.instance(body.mesh,body.name) then stanceBody=nil; return end
            body.mesh:SetVisibility(not hidden,false)
            previous=hidden
        end
        ExecuteInGameThread(frame,EGameThreadMethod.EngineTick)
    end
    frame()
end

function FP.refresh()
    if not skin or not C.instance(pawn,pawnName) then return end
    local arms,body=pawn.FirstPersonMesh,pawn.Mesh
    if not C.valid(arms) or not C.valid(arms:GetSkinnedAsset()) or not C.valid(body) then remove(); return end
    if not follows(pieces.arms,arms) or (skin.firstPersonBodyMesh and not follows(pieces.body,body)) then
        remove()
        local ok,err=pcall(function()
            attach("arms",arms,skin.firstPersonMesh)
            if skin.firstPersonBodyMesh then attach("body",body,skin.firstPersonBodyMesh) end
        end)
        if not ok then remove(); error(err) end
    end
    watchStance()
    for _,field in ipairs(fields) do suppress(field) end
end

function FP.set(selected)
    if selected~=skin then
        remove()
        skin=selected
    end
    FP.refresh()
end

function FP.bind(character)
    if not C.instance(pawn,pawnName) or not C.same(character,pawn) then
        remove()
        pawn=character
        pawnName=C.valid(pawn) and pawn:GetFullName() or nil
    end
    FP.refresh()
end

function FP.clear()
    remove()
    pawn,pawnName,skin=nil,nil,nil
end

return FP
