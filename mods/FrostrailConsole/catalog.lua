-- Schematics are retained by this mod's native ObjectLibrary while the world
-- is bound. Rows use full paths, never localized names, as their identity.
local M={}
local merged={Clothing="gear",Backpack="gear",Weapon="gear",SaintsTeeth="special",Research="special",Relic="special",
    Decor="misc",Misc="misc"}
M.order={"RawResource","Scrap","Junk","Component","Tools","Ammo","Food","Medical",
    "gear","Augment","special","misc"}
local labels={gear={"装备","Gear"},special={"特殊","Special"},misc={"杂项","Misc"}}
function M.group(category)
    if category=="other" then return "misc" end
    return merged[category:match("([^.]+)$")] or category
end
function M.is_mod(path)
    local asset=path:match("(/.*)") or path
    return asset:sub(1,16)~="/Game/Frostrail/"
end
function M.label(C,category)
    if category=="all" then return C.text("全部","All") end
    if category=="mod" then return C.text("Mod 物品","Mod items") end
    if labels[category] then return C.text(labels[category][1],labels[category][2]) end
    local out={}
    LoadAsset("/Game/Frostrail/UI/WidgetFunctionLibrary.WidgetFunctionLibrary_C"):GetCDO()
        :GetItemCategoryLocalization({TagName=FName(category)},true,C.player,out)
    local name=out.CategoryName:ToString()
    return name~="" and name~=category and name or category:match("([^.]+)$")
end
-- Inspect the same pickup mesh used by native icon rendering. An explicit
-- icon wins, so a mod may reuse a placeholder pickup with a finished icon.
function M.placeholder(C,item)
    if C.valid(item.OverrideIcon) then
        if item.OverrideIcon:GetFullName()=="Texture2D /Game/Frostrail/UI/Textures/T_UI_MissingAsset.T_UI_MissingAsset" then
            return item.OverrideIcon:GetFullName()
        end
        return
    end
    local path=item.PickupClass:GetObjectID():GetAssetPathName():ToString()
    if path=="" or path=="None" then return end
    local class=LoadAsset(path)
    if not C.valid(class) then return end
    local actor=class:GetCDO()
    for _,ref in ipairs(actor:K2_GetComponentsByClass(C.class("/Script/Engine.MeshComponent"))) do
        local component=ref:get()
        if component:IsA("/Script/Engine.StaticMeshComponent") and C.valid(component.StaticMesh)
            and component.StaticMesh:GetFullName()=="StaticMesh /Game/Frostrail/Common/SM_PlaceholderMesh.SM_PlaceholderMesh" then
            return component.StaticMesh:GetFullName()
        end
        for _,ref in ipairs(component:GetMaterials()) do
            local material=ref:get()
            if C.valid(material) and material:GetFullName()=="Material /Engine/EngineDebugMaterials/VertexColorViewMode_RedOnly.VertexColorViewMode_RedOnly" then
                return material:GetFullName()
            end
        end
    end
end
function M.category(tags)
    for _,tag in ipairs(tags) do
        if tag:sub(1,14)=="Item.Category." then
            -- The game's clothing and weapon subtypes share their top-level tab.
            return tag:match("^(Item%.Category%.[^.]+)")
        end
    end
    return "other"
end
function M.filter(rows,category,query)
    local result={}
    query=(query or ""):lower():match("^%s*(.-)%s*$")
    for _,row in ipairs(rows) do
        if (category=="all" or category=="mod" and row.mod or row.category==category) and row.name:lower():find(query,1,true) then
            result[#result+1]=row
        end
    end
    return result
end
function M.page(rows,page,size)
    local pages=math.max(1,math.ceil(#rows/size))
    page=math.max(1,math.min(page,pages))
    local result={}
    for i=(page-1)*size+1,math.min(page*size,#rows) do result[#result+1]=rows[i] end
    return result,page,pages
end
function M.build(C)
    local system=C.class("/Script/Engine.Default__KismetSystemLibrary")
    local ids={}
    system:GetPrimaryAssetIdList({Name=FName("ItemSchematicPrimaryAsset")},ids)
    local held,seen,rows={},{},{}
    local excluded={modular={},unnamed={},placeholder={}}
    local function add(item)
        if not C.valid(item) or not item:IsA("/Script/Frostrail.ItemSchematic") then return end
        local path=item:GetFullName()
        if seen[path] then return end
        seen[path]=true
        if path:find("Default__",1,true) then return end
        if item:IsModular() then excluded.modular[#excluded.modular+1]=path; return end
        local name=item.DisplayName:ToString()
        if name:match("^%s*$") then excluded.unnamed[#excluded.unnamed+1]=path; return end
        held[#held+1]=item
        C.retain("console_catalog",held)
        local placeholder=M.placeholder(C,item)
        if placeholder then
            excluded.placeholder[#excluded.placeholder+1]={path=path,name=name,resource=placeholder}
            return
        end
        local tags={}
        item.ItemTags.GameplayTags:ForEach(function(_,ref) tags[#tags+1]=ref:get().TagName:ToString() end)
        local original=M.category(tags)
        rows[#rows+1]={object=item,path=path,name=name,category=M.group(original),original_category=original,
            mod=M.is_mod(path),tags=tags}
    end
    for _,ref in ipairs(ids) do
        local id=ref:get()
        local item=system:GetObjectFromPrimaryAssetId(id)
        if not C.valid(item) then item=system:LoadAsset_Blocking(system:GetSoftObjectReferenceFromPrimaryAssetId(id)) end
        add(item)
    end
    -- Content packs load their own independent assets; no registry mutation or
    -- dependency on a particular content pack's implementation is necessary.
    for _,item in ipairs(FindAllOf("ItemSchematic") or {}) do add(item) end
    M.names(C,rows)
    C.log(C.id,"Catalog: "..#ids.." primary assets; "..#rows.." entries; excluded modular="..#excluded.modular
        .." unnamed="..#excluded.unnamed.." placeholder="..#excluded.placeholder)
    return rows,excluded
end
function M.names(C,rows)
    for _,row in ipairs(rows) do
        if C.instance(row.object,row.path) then row.name=row.object.DisplayName:ToString() end
    end
    table.sort(rows,function(a,b) return a.name==b.name and a.path<b.path or a.name<b.name end)
end
return M
