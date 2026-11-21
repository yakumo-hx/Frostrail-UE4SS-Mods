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
    local original=C.readSkinJson(skin.stockReference).bones
    local authored=C.readSkinJson(skin.reference).bones
    local rig,byName={reference=authored,weaponOnBack=skin.previewWeaponOnBack},{}
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

local function xyzw(q) return {X=q[1],Y=q[2],Z=q[3],W=q[4]} end
local function xyz(v) return {X=v[1],Y=v[2],Z=v[3]} end
local function product(a,b)
    local out={}
    correct(a,{b.X,b.Y,b.Z,b.W},out)
    return out
end

local function rotateBranch(joint,pivot,delta)
    local t=joint.transform
    local pos=t.Translation
    local x,y,z=rotate(delta,pos.X-pivot.X,pos.Y-pivot.Y,pos.Z-pivot.Z)
    t.Translation={X=pivot.X+x,Y=pivot.Y+y,Z=pivot.Z+z}
    t.Rotation=product(delta,t.Rotation)
    for _,child in ipairs(joint.children) do rotateBranch(child,pivot,delta) end
end

local function heldPose(C,rig)
    local joints,byName={},{}
    for i=1,#rig do
        local bone=rig.reference[i]
        local t={Rotation=xyzw(bone.rotation_xyzw),Translation=xyz(bone.translation_cm),Scale3D=xyz(bone.scale)}
        local joint={transform=t,children={}}
        local parent=byName[bone.parent]
        if parent then
            local p=parent.transform
            local v,s=t.Translation,p.Scale3D
            local x,y,z=rotate(p.Rotation,v.X*s.X,v.Y*s.Y,v.Z*s.Z)
            t.Translation={X=p.Translation.X+x,Y=p.Translation.Y+y,Z=p.Translation.Z+z}
            t.Rotation=product(p.Rotation,t.Rotation)
            t.Scale3D={X=s.X*t.Scale3D.X,Y=s.Y*t.Scale3D.Y,Z=s.Z*t.Scale3D.Z}
            parent.children[#parent.children+1]=joint
        end
        joints[i],byName[bone.name]=joint,joint
    end
    local mathLib=C.class("/Script/Engine.Default__KismetMathLibrary")
    local function bend(joint,child,direction)
        local pivot,to=joint.transform.Translation,child.transform.Translation
        local delta=mathLib:Quat_FindBetweenVectors({X=to.X-pivot.X,Y=to.Y-pivot.Y,Z=to.Z-pivot.Z},direction)
        rotateBranch(joint,pivot,delta)
    end
    for _,side in ipairs({"l","r"}) do
        local sign=side=="l" and 1 or -1
        local upper,elbow,hand=byName["upperarm_"..side],byName["lowerarm_"..side],byName["hand_"..side]
        local grip=byName["weapon_"..side].transform
        local along,up
        if rig.weaponOnBack then
            -- An outfit with hands in pockets can show the weapon against its back.
            local shoulder=upper.transform.Translation
            local hip=byName.pelvis.transform.Translation
            grip.Translation={X=shoulder.X,Y=shoulder.Y-19,Z=(shoulder.Z+hip.Z)*.5+4}
            along,up={X=sign*.42,Y=0,Z=-.91},{X=0,Y=-1,Z=0}
        else
            -- Lower the arms outside the torso using each mesh's authored arm lengths.
            bend(upper,elbow,{X=sign*.51,Y=.14,Z=-.85})
            bend(elbow,hand,{X=sign*.38,Y=.5,Z=-.77})
            local wrist,knuckle=hand.transform.Translation,byName["middle_01_"..side].transform.Translation
            -- Keep the stock and receiver to the outside of the forearm.
            grip.Translation={X=(wrist.X+knuckle.X)*.5+sign*3,Y=(wrist.Y+knuckle.Y)*.5,Z=(wrist.Z+knuckle.Z)*.5}
            along,up={X=-sign*.24,Y=.28,Z=-.93},{X=sign*.55,Y=0,Z=1}
        end
        local q=mathLib:Conv_RotatorToQuaternion(mathLib:MakeRotFromXZ(along,up))
        grip.Rotation={X=q.X,Y=q.Y,Z=q.Z,W=q.W}
    end
    local transforms={}
    for i,joint in ipairs(joints) do transforms[i]=joint.transform end
    return transforms
end

function M.hold(C,rig,follower)
    if not rig.held then
        rig.held=heldPose(C,rig)
        rig.reference=nil
    end
    for i,transform in ipairs(rig.held) do
        follower:SetBoneTransformByName(rig[i].key,transform,1)
    end
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
