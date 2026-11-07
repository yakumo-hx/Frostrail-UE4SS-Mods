-- Native items, pickup actors and saving keep their identity.
return function(C,dir,catalog)
    local V={records={},items={}}
    local function vector(p) return {X=p[1],Y=p[2],Z=p[3]} end
    for _,spec in ipairs(catalog.items) do
        if spec.icon then
            local data=C.config.read(dir.."/assets/"..spec.id..".mesh.json")
            local visual={id=spec.id,tag=FName("FrostrailItems."..spec.id),data=data,sections={}}
            for i,source in ipairs(data.sections) do
                local section={vertices={},normals={},uv={},tangents={},triangles=source.triangles,material=source.material}
                for j,p in ipairs(source.vertices) do section.vertices[j]=vector(p);section.normals[j]=vector(source.normals[j]) end
                for j,p in ipairs(source.uv) do section.uv[j]={X=p[1],Y=p[2]} end
                for j,p in ipairs(source.tangents) do section.tangents[j]={TangentX=vector(p),bFlipTangentY=p[4]<0} end
                visual.sections[i]=section
            end
            local name="ISCH_FRI_"..spec.id
            V.items["ItemSchematic /Game/FrostrailMods/FrostrailItems/"..name.."."..name]=visual
        end
    end
    function V:resources(pc)
        if self.assets then return self.assets end
        local library=C.class("/Script/Engine.Default__KismetRenderingLibrary")
        local assets={palettes={},
            surface=library:ImportFileAsTexture2D(pc,dir.."/assets/rough-nonmetal.png"),
            normal=LoadAsset("/Engine/EngineProduction/ReferenceNormalMap.ReferenceNormalMap"),
            material=LoadAsset("/Game/Frostrail/Common/Materials/Items/Junk/MI_CannedBeans_01.MI_CannedBeans_01"),
            glass=LoadAsset("/Engine/EngineDebugMaterials/M_SimpleTranslucent.M_SimpleTranslucent")}
        local retained={}
        for key,asset in pairs(assets) do
            if key~="palettes" then
                assert(C.valid(asset),"Missing item visual resource: "..key)
                retained[#retained+1]=asset
            end
        end
        for _,visual in pairs(self.items) do
            local file=visual.data.palette or "colormap.png"
            if not assets.palettes[file] then
                local texture=library:ImportFileAsTexture2D(pc,dir.."/assets/"..file)
                assert(C.valid(texture),"Missing item color palette: "..file)
                assets.palettes[file]=texture;retained[#retained+1]=texture
            end
        end
        -- Process resources belong to the rooted native library. Each dynamic
        -- material also owns its texture references; no world/actor is rooted.
        C.retain("item_visual_resources",retained)
        self.assets=assets
        return assets
    end
    function V:apply(actor,pc,visual)
        local actor_name=actor:GetFullName()
        local previous=self.records[actor_name]
        if previous and C.instance(previous.actor,actor_name) and C.instance(previous.component,previous.component_name) then
            return previous
        end
        local class=C.class("/Script/ProceduralMeshComponent.ProceduralMeshComponent")
        assert(C.valid(class),"Missing item ProceduralMeshComponent class")
        -- A player rebind clears Lua records, but an existing actor still owns
        -- its component. Find its tag before creating another visual.
        for _,ref in ipairs(actor:K2_GetComponentsByClass(class)) do
            local component=ref:get()
            if component:ComponentHasTag(visual.tag) then
                return {actor=actor,component=component,component_name=component:GetFullName()}
            end
        end
        local assets=self:resources(pc)
        local component=actor:AddComponentByClass(class,false,
            {Rotation={X=0,Y=0,Z=0,W=1},Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}},false)
        -- A pickup can retire while resources load. Keep the scan and icons
        -- alive if creation is declined; retry only while it remains in the
        -- next native actor list.
        if not C.valid(component) then
            if not previous or not previous.pending then
                C.log(C.id,"Deferred "..visual.id.." visual for "..actor_name..": AddComponentByClass returned no component")
            end
            return {actor=actor,pending=true}
        end
        component.ComponentTags={visual.tag}
        for i,section in ipairs(visual.sections) do
            component:CreateMeshSection_LinearColor(i-1,section.vertices,section.triangles,section.normals,
                section.uv,{},{},{},{},section.tangents,false,false)
            local glass=section.material and section.material.alpha_mode=="BLEND"
            local material=component:CreateDynamicMaterialInstance(i-1,glass and assets.glass or assets.material,FName("None"))
            assert(C.valid(material),"Cannot create item material instance")
            if glass then
                local color=section.material.color
                material:SetVectorParameterValue(FName("Color"),{R=color[1],G=color[2],B=color[3],A=color[4]})
            else
                -- The native material is layered. LayerParameter is 0 in this build.
                for key,texture in pairs({BaseColor=assets.palettes[visual.data.palette or "colormap.png"],CRMH=assets.surface,Normal=assets.normal}) do
                    material:SetTextureParameterValueByInfo({Name=FName(key),Association=0,Index=0},texture)
                end
            end
        end
        -- Keep the native root and its Pickup profile/physics. Match its actual
        -- template bounds to the item, then undo that scale on the visual child.
        local mesh=actor.Mesh
        local lo,hi={},{};mesh:GetLocalBounds(lo,hi)
        local data=visual.data
        local sx,sy,sz=data.bounds_cm[1]/(hi.X-lo.X),data.bounds_cm[2]/(hi.Y-lo.Y),data.bounds_cm[3]/(hi.Z-lo.Z)
        mesh:SetRelativeScale3D({X=sx,Y=sy,Z=sz})
        component:SetRelativeScale3D({X=1/sx,Y=1/sy,Z=1/sz})
        component:K2_SetRelativeLocation({X=(hi.X+lo.X)/2,Y=(hi.Y+lo.Y)/2,Z=(hi.Z+lo.Z)/2},false,{},true)
        mesh:SetVisibility(false,false)
        C.log(C.id,visual.id.." visual attached to "..actor_name)
        return {actor=actor,component=component,component_name=component:GetFullName()}
    end
    function V:scan(pc)
        local world=pc:GetLevel().OwningWorld
        local current={}
        -- UE4SS FindAllOf/IsValid include garbage pickups awaiting GC. Their
        -- actor UFunctions no longer execute, even IsActorBeingDestroyed.
        -- Let the engine enumerate live actors in the current world instead.
        local actors={}
        C.class("/Script/Engine.Default__GameplayStatics"):GetAllActorsOfClass(pc,
            C.class("/Script/Frostrail.StaticMeshItemPickable"),actors)
        for _,ref in ipairs(actors) do
            local actor=ref:get()
            if C.valid(actor)
                and C.same(actor:GetLevel().OwningWorld,world) and C.valid(actor.ItemInstance) then
                local schematic=actor.ItemInstance:GetSchematic()
                local visual=C.valid(schematic) and self.items[schematic:GetFullName()]
                if visual then
                    current[actor:GetFullName()]=self:apply(actor,pc,visual)
                end
            end
        end
        -- Components are held by their actors. Forget pickups that were taken,
        -- destroyed or unloaded; never use a Lua wrapper as a GC owner.
        self.records=current
    end
    function V:clear() self.records={} end
    return V
end
