-- The actor owns each shell component. Only definition textures and source mesh
-- arrays live for the process. No actor or preview world is held across travel.
return function(M)
    local C=M.core
    local S={models={},textures={},retained={}}
    local prefix="/Script/Frostrail."
    local marker=FName("FrostrailArmsWW2.Shell")
    local zero=FName("None")
    local function vec(p) return {X=p[1],Y=p[2],Z=p[3]} end
    local identity={Rotation={X=0,Y=0,Z=0,W=1},Translation=vec({0,0,0}),Scale3D=vec({1,1,1})}
    local render=C.class("/Script/Engine.Default__KismetRenderingLibrary")
    local function texture(pc,path)
        if not S.textures[path] then
            local object=render:ImportFileAsTexture2D(pc,C.dir.."/"..path)
            assert(C.valid(object),"Cannot load "..path)
            S.textures[path]=object
            S.retained[#S.retained+1]=object
            C.retain("shell_textures",S.retained)
        end
        return S.textures[path]
    end
    function S:load_icons(pc)
        for i,spec in ipairs(M.catalog) do
            if spec.shell then
                M.guns[i].OverrideIcon=texture(pc,spec.shell.."/"..spec.id..".ui.png")
            end
        end
    end
    local function model(spec)
        if S.models[spec.id] then return S.models[spec.id] end
        local mesh=C.config.read(C.dir.."/"..spec.shell.."/"..spec.id..".mesh.json")
        local data=C.config.read(C.dir.."/"..spec.shell.."/attachments.json")
        data.sections={}
        for i,src in ipairs(mesh.sections) do
            local part={name=src.name,vertices={},normals={},uv={},tangents={},indices=src.triangles}
            for j,p in ipairs(src.vertices) do
                part.vertices[j]=vec(p)
                part.normals[j]=vec(src.normals[j])
                part.uv[j]={X=src.uv[j][1],Y=src.uv[j][2]}
                local t=src.tangents[j]
                part.tangents[j]={TangentX=vec(t),bFlipTangentY=t[4]<0}
            end
            data.sections[i]=part
        end
        S.models[spec.id]=data
        return data
    end
    local function show_preview(actor,components)
        local world=actor:GetLevel().OwningWorld
        if world:GetFName():ToString()~="MultiWorld_Crafting" then return end
        local statics=C.class("/Script/Engine.Default__GameplayStatics")
        local cls=C.class("/Game/Frostrail/Blueprints/Items/RenderDisplays/BP_Crafting_Display.BP_Crafting_Display_C")
        local display=statics:GetActorOfClass(actor,cls)
        if not C.valid(display) then return end
        local camera=display:GetComponentByClass(C.class("/Script/Engine.SceneCaptureComponent2D"))
        for _,part in pairs(components) do camera:ShowOnlyComponent(part) end
        camera:CaptureScene()
    end
    local function attach(actor,rig,spec)
        local data=model(spec)
        if rig:GetSkinnedAsset():GetFName():ToString()~=data.rig then return end
        local sockets={}
        for _,ref in ipairs(actor:K2_GetComponentsByClass(C.class(prefix.."ItemStaticMeshComponent"))) do
            local native=ref:get()
            native:SetVisibility(false,false)
            sockets[native:GetAttachSocketName():ToString()]=native
        end
        local parts={}
        local pmclass=C.class("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
        for _,ref in ipairs(actor:K2_GetComponentsByClass(pmclass)) do
            local comp=ref:get()
            if comp:ComponentHasTag(marker) then parts[comp.ComponentTags[2]:ToString()]=comp end
        end
        local new,material={}
        for _,s in ipairs(data.sections) do
            local pm=parts[s.name]
            if not pm then
                pm=actor:AddComponentByClass(pmclass,false,identity,false)
                if not C.valid(pm) then return end
                pm:SetFirstPersonPrimitiveType(rig.FirstPersonPrimitiveType)
                pm:SetOnlyOwnerSee(rig.bOnlyOwnerSee)
                pm:SetOwnerNoSee(rig.bOwnerNoSee)
                pm:SetCollisionEnabled(0)
                pm.ComponentTags={marker,FName(s.name)}
                parts[s.name]=pm
                new[s.name]=true
            end
            if new[s.name] then
                if not material then
                    local base=M:asset("/Game/Frostrail/Common/Materials/Items/Junk/MI_CannedBeans_01")
                    material=pm:CreateDynamicMaterialInstance(0,base,zero)
                    for key,image in pairs({BaseColor=texture(actor,spec.shell.."/colormap.png"),
                        CRMH=texture(actor,"assets/rough-nonmetal.png"),Normal=M:asset("/Engine/EngineProduction/ReferenceNormalMap")}) do
                        material:SetTextureParameterValueByInfo({Name=FName(key),Association=0,Index=0},image)
                    end
                end
                local index=pm:GetNumSections()
                pm:CreateMeshSection_LinearColor(index,s.vertices,s.indices,s.normals,s.uv,{},{},{},{},s.tangents,false,false)
                pm:SetMaterial(index,material)
            end
        end
        for _,part in pairs(parts) do
            part:K2_AttachToComponent(rig,zero,2,2,2,false)
            part:K2_SetRelativeLocation(vec(data.offset),false,{},true)
        end
        for name,bone in pairs(data.bones) do
            parts[name]:K2_AttachToComponent(rig,FName(bone),1,1,1,false)
        end
        for name,socket in pairs(data.sockets or {}) do
            if sockets[socket] then parts[name]:K2_AttachToComponent(sockets[socket],zero,1,1,1,false) end
        end
        rig.VisibilityBasedAnimTickOption=0
        rig:SetVisibility(false,false)
        if actor:IsA(prefix.."FirearmWeaponActor") then
            local muzzle=actor.MuzzleComponent
            if C.valid(muzzle) then
                local pos=C.class("/Script/Engine.Default__KismetMathLibrary"):TransformLocation(
                    rig:K2_GetComponentToWorld(),vec(data.muzzle))
                muzzle:K2_SetWorldLocation(pos,false,{},true)
            end
            -- The ADS animation lines up these two native markers with the eye.
            for _,sight in ipairs({actor.RearSight,actor.FrontSight}) do
                local location=sight.RelativeLocation
                sight:K2_SetRelativeLocation({X=location.X,Y=0,Z=data.sightHeight},false,{},true)
            end
        end
        show_preview(actor,parts)
    end
    function S:watch()
        -- Held, pickup and assembly actors all build a native receiver component.
        -- Wait until construction assigns its mesh and owning item.
        NotifyOnNewObject(prefix.."ItemSkeletalMeshComponent",function(rig)
            local key=rig:GetFullName()
            ExecuteInGameThread(function()
                C.run(C.id,function()
                    if not C.instance(rig,key) or not C.valid(rig:GetSkinnedAsset()) then return end
                    local actor=rig:GetOwner()
                    if not C.valid(actor) or not C.valid(actor.ItemInstance) then return end
                    local def=actor.ItemInstance:GetSchematic()
                    local spec=C.valid(def) and M.by_name[def:GetFName():ToString()]
                    if spec and spec.shell then attach(actor,rig,spec) end
                end)
            end,EGameThreadMethod.EngineTick)
        end)
    end
    return S
end
