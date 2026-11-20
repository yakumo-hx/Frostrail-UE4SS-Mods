-- Both meshes use the game's bone names. Keep the animated rotations and
-- translation offsets, substituting the authored limb lengths in each pose.
local M={}

local function rotate(q,x,y,z)
    local tx=2*(q.Y*z-q.Z*y)
    local ty=2*(q.Z*x-q.X*z)
    local tz=2*(q.X*y-q.Y*x)
    return x+q.W*tx+q.Y*tz-q.Z*ty,y+q.W*ty+q.Z*tx-q.X*tz,z+q.W*tz+q.X*ty-q.Y*tx
end

local function correct(q,c,out)
    if c then
        local x,y,z,w=c[1],c[2],c[3],c[4]
        out.X=q.W*x+q.X*w+q.Y*z-q.Z*y
        out.Y=q.W*y+q.Y*w+q.Z*x-q.X*z
        out.Z=q.W*z+q.Z*w+q.X*y-q.Y*x
        out.W=q.W*w-q.X*x-q.Y*y-q.Z*z
    else
        out.X,out.Y,out.Z,out.W=q.X,q.Y,q.Z,q.W
    end
end

function M.read(C,skin)
    local original=C.config.read(C.dir.."/"..skin.stockReference).bones
    local authored=C.config.read(C.dir.."/"..skin.reference).bones
    local rig,byName={},{}
    for i=1,skin.boneCount or #authored do
        local a,b=original[i],authored[i]
        assert(a.name==b.name and a.parent==b.parent,"Skin skeleton mismatch at "..b.name)
        local bone={key=FName(b.name),parent=byName[b.parent],stock=a.translation_cm,
            authored=b.translation_cm,correction=b.pose_correction_xyzw,sourceRotation={},
            output={Rotation={},Translation={},Scale3D={}}}
        rig[i],byName[b.name]=bone,bone
    end
    return rig
end

function M.update(rig,leader,follower)
    -- Numeric scratch is reused by the next mesh. No returned UE struct or
    -- component reference survives this call. Parents precede their children.
    for _,bone in ipairs(rig) do
        local native=leader:GetBoneTransform(bone.key,2) -- RTS_Component
        local rot,pos,scale=native.Rotation,native.Translation,native.Scale3D
        local out=bone.output
        local parent=bone.parent
        local stock,authored=bone.stock,bone.authored
        if parent then
            local s=parent.output.Scale3D
            local ox,oy,oz=rotate(parent.sourceRotation,stock[1]*s.X,stock[2]*s.Y,stock[3]*s.Z)
            local nx,ny,nz=rotate(parent.output.Rotation,authored[1]*s.X,authored[2]*s.Y,authored[3]*s.Z)
            bone.dx,bone.dy,bone.dz=parent.dx+nx-ox,parent.dy+ny-oy,parent.dz+nz-oz
        else
            bone.dx,bone.dy,bone.dz=authored[1]-stock[1],authored[2]-stock[2],authored[3]-stock[3]
        end
        correct(rot,nil,bone.sourceRotation)
        correct(rot,bone.correction,out.Rotation)
        out.Translation.X,out.Translation.Y,out.Translation.Z=pos.X+bone.dx,pos.Y+bone.dy,pos.Z+bone.dz
        out.Scale3D.X,out.Scale3D.Y,out.Scale3D.Z=scale.X,scale.Y,scale.Z
        follower:SetBoneTransformByName(bone.key,out,1) -- EBoneSpaces::ComponentSpace
    end
end

return M
