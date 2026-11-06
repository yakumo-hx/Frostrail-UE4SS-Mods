local V={}
-- Fixed Slate dimensions; title, actions and output stay inside the frame.
local TILE,COLUMNS,MAX_ROWS=60,8,7
local MARGIN,PAD,TABS=16,10,84
local PANEL_SCALE=1.5
local ICON_SCALE=1.3
local CHROME=2*PAD+40+36+26
local function padding(n) return {Left=n,Top=n,Right=n,Bottom=n} end
local function close_label(C)
    local names={}
    local settings=FindFirstOf("FREnhancedInputUserSettings")
    if C.valid(settings) then
        local profile=settings:GetActiveKeyProfile()
        local id=FName("FrostrailMods.Console")
        if C.valid(profile) and profile.PlayerMappedKeys:Contains(id) then
            profile.PlayerMappedKeys:Find(id):get().Mappings:ForEach(function(ref)
                local key=ref:get().CurrentKey
                if key.KeyName:ToString()~="None" then
                    names[#names+1]=C.class("/Script/Engine.Default__KismetInputLibrary"):Key_GetDisplayName(key,false):ToString()
                end
            end)
        end
    end
    names[#names+1]="Esc"
    return table.concat(names," / ")..C.text(" 关闭"," Close")
end
function V.open(M)
    local C=M.core
    local pc,pawn=M:host()
    local lib=C.class("/Script/UMG.Default__WidgetBlueprintLibrary")
    local width,height=2*PAD+TABS+10+COLUMNS*TILE,CHROME+MAX_ROWS*TILE
    local w=lib:Create(pc,C.class("/Script/Frostrail.FRCompositeWidgetBase"),pc)
    local hud=pc:GetHUD()
    local S={widget=w,name=w:GetFullName(),controller_name=pc:GetFullName(),pawn_name=pawn:GetFullName(),building=true,
        hud=hud,hud_name=hud:GetFullName(),category="all",query="",page=1,cells={},categories={}}
    M.panel=S
    -- Asset loads may collect the unfinished widget tree before it is attached.
    C.retain("console_panel",{w})
    w.RequiredInputState=2 -- UIOnly, applied by the native HUD stack.
    w.bHideHud=false;w.bHideCrosshair=true;w.bHideCursor=false
    w.bIsClosableByUserInput=true;w.bIsFocusable=true
    local tree=w.WidgetTree
    local function new(name) return C.new("/Script/UMG."..name,tree) end
    local function sized(widget,x,y)
        local box=new("SizeBox")
        if x then box:SetWidthOverride(x) end
        if y then box:SetHeightOverride(y) end
        box:SetContent(widget);return box
    end
    local skin=dofile(C.dir.."/skin.lua")(C)
    S.skin=skin
    local function text(value,kind) return skin.text(tree,value,kind) end
    local function button(label,callback,kind)
        local e=C.ui.button(C,w,label,callback,12)
        skin.button(e,kind or "base");return e
    end
    local root=new("Overlay");tree.RootWidget=sized(root,width,height);skin.frame(root)
    local inset=new("Border");inset:SetBrushColor({R=0,G=0,B=0,A=0});inset:SetPadding(padding(PAD))
    local inset_slot=root:AddChildToOverlay(inset);inset_slot:SetHorizontalAlignment(0);inset_slot:SetVerticalAlignment(0)
    local column=new("VerticalBox");inset:SetContent(column)
    local header=new("VerticalBox");column:AddChildToVerticalBox(sized(header,nil,40))
    local top=new("HorizontalBox");header:AddChildToVerticalBox(sized(top,nil,32))
    local title=text(C.text("控制台","Console"),"title")
    top:AddChildToHorizontalBox(sized(title,TABS+10,nil)):SetVerticalAlignment(2)
    S.search=new("EditableTextBox");skin.search(S.search)
    S.search:SetHintText(FText(C.text("搜索物品名称…","Search item names…")))
    local ss=top:AddChildToHorizontalBox(sized(S.search,nil,28));ss:SetSize({SizeRule=1,Value=1});ss:SetVerticalAlignment(2)
    local close=button(close_label(C),function() M:close() end)
    top:AddChildToHorizontalBox(close.widget):SetPadding({Left=8,Top=2,Right=0,Bottom=2})
    S.close_label=close.text
    header:AddChildToVerticalBox(skin.title_line(tree,TABS))
    local body=new("HorizontalBox");column:AddChildToVerticalBox(sized(body,nil,MAX_ROWS*TILE))
    local tabs=new("VerticalBox")
    body:AddChildToHorizontalBox(sized(tabs,TABS,nil)):SetPadding({Left=0,Top=0,Right=10,Bottom=0})
    local counts,has_mod={},false
    for _,row in ipairs(M.rows) do counts[row.category]=(counts[row.category] or 0)+1;has_mod=has_mod or row.mod end
    S.category_labels={}
    local function tab(id)
        local label=M.catalog.label(C,id)
        local e=button(label,function()
            if M.panel~=S or not M:live() then return end
            S.category=id;S.page=1;V.render(M)
        end,"category")
        e.text:SetJustification(1)
        tabs:AddChildToVerticalBox(sized(e.widget,TABS,26)):SetPadding({Left=0,Top=0,Right=0,Bottom=2})
        S.categories[id]=e;S.category_labels[id]=label;counts[id]=nil
    end
    tab("all");if has_mod then tab("mod") end
    for _,key in ipairs(M.catalog.order) do
        local id=(key=="gear" or key=="special" or key=="misc") and key or "Item.Category."..key
        if counts[id] then tab(id) end
    end
    local unknown={};for id in pairs(counts) do unknown[#unknown+1]=id end;table.sort(unknown)
    for _,id in ipairs(unknown) do tab(id) end
    S.grid=new("UniformGridPanel");S.grid:SetSlotPadding(padding(2))
    S.columns,S.row_count=COLUMNS,MAX_ROWS;S.page_size=COLUMNS*MAX_ROWS
    body:AddChildToHorizontalBox(S.grid)
    S.icon_parent=skin.icon_parent
    for i=1,S.page_size do
        local cell
        cell=button("",function() if cell.row then M:click(cell.row) end end,"slot")
        local overlay=C.new("/Script/UMG.Overlay",cell.widget.WidgetTree)
        local slot=cell.button:SetContent(overlay);slot:SetHorizontalAlignment(0);slot:SetVerticalAlignment(0)
        local image=C.new("/Script/UMG.Image",cell.widget.WidgetTree)
        local image_slot=overlay:AddChildToOverlay(image);image_slot:SetHorizontalAlignment(0);image_slot:SetVerticalAlignment(0)
        image:SetRenderScale({X=ICON_SCALE,Y=ICON_SCALE});cell.button:SetClipping(1);cell.image=image
        cell.badge=skin.badge(cell.widget.WidgetTree,overlay)
        S.grid:AddChildToUniformGrid(sized(cell.widget,TILE-4,TILE-4),math.floor((i-1)/COLUMNS),(i-1)%COLUMNS)
        S.cells[i]=cell
    end
    local nav=new("HorizontalBox");column:AddChildToVerticalBox(sized(nav,nil,36))
    S.action_buttons={}
    for _,action in ipairs({
        {id="warmth",zh="恢复体温",en="Restore warmth",material="MI_UI_Icon_Warmth_Base",tint={R=1,G=.55,B=.20,A=1}},
        {id="health",zh="恢复血量",en="Restore health",material="MI_UI_Icon_Health_Base",tint={R=.94,G=.36,B=.31,A=1}},
    }) do
        local e=button("",function() M:restore(action.id) end,"slot")
        local icon=C.new("/Script/UMG.Image",e.widget.WidgetTree)
        icon:SetBrushFromMaterial(skin.material("Base/"..action.material));icon:SetColorAndOpacity(action.tint)
        local inset_icon=C.new("/Script/UMG.Border",e.widget.WidgetTree)
        inset_icon:SetBrushColor({R=0,G=0,B=0,A=0});inset_icon:SetPadding(padding(6));inset_icon:SetContent(icon)
        local bs=e.button:SetContent(inset_icon);bs:SetHorizontalAlignment(0);bs:SetVerticalAlignment(0)
        nav:AddChildToHorizontalBox(sized(e.widget,30,30)):SetPadding({Left=0,Top=3,Right=6,Bottom=3})
        e.label=C.text(action.zh,action.en);S.action_buttons[action.id]=e
    end
    nav:AddChildToHorizontalBox(new("Spacer")):SetSize({SizeRule=1,Value=1})
    local previous=button("‹",function() V.turn(M,-1) end)
    nav:AddChildToHorizontalBox(sized(previous.widget,30,26)):SetVerticalAlignment(2)
    S.page_label=text("")
    nav:AddChildToHorizontalBox(sized(S.page_label,100,nil)):SetVerticalAlignment(2)
    S.page_label:SetJustification(1)
    local next_page=button("›",function() V.turn(M,1) end)
    nav:AddChildToHorizontalBox(sized(next_page.widget,30,26)):SetVerticalAlignment(2)
    S.previous=previous.button;S.next_page=next_page.button
    local output=new("Overlay");output:SetClipping(1)
    column:AddChildToVerticalBox(sized(output,nil,26))
    S.hover=new("HorizontalBox");local hs=output:AddChildToOverlay(S.hover);hs:SetHorizontalAlignment(0);hs:SetVerticalAlignment(2)
    S.hover_name=text("","name");S.hover_category=text("","muted")
    S.hover:AddChildToHorizontalBox(S.hover_name)
    S.hover:AddChildToHorizontalBox(S.hover_category):SetPadding({Left=8,Top=0,Right=0,Bottom=0})
    S.status=text("");local os=output:AddChildToOverlay(S.status);os:SetHorizontalAlignment(0);os:SetVerticalAlignment(2);S.status:SetVisibility(1)
    w:SetRenderTransformPivot({X=0,Y=0});w:SetRenderScale({X=PANEL_SCALE,Y=PANEL_SCALE})
    assert(hud:AddWidgetToStack(w,{X=MARGIN,Y=MARGIN})>=0,"Console could not join the HUD stack")
    w.Slot:SetHorizontalAlignment(1);w.Slot:SetVerticalAlignment(1)
    S.building=false
    C.settings.set_busy(true)
    M.icons.prepare(M)
    V.render(M);C.log(C.id,"Opened "..COLUMNS.."x"..MAX_ROWS.." item grid")
end
function V.turn(M,delta)
    if not M:live() then return end
    M.panel.page=M.panel.page+delta;V.render(M)
end
function V.render(M)
    local C,S=M.core,M.panel
    if not M:live() then return end
    local rows=M.catalog.filter(M.rows,S.category,S.query)
    local page;page,S.page,S.pages=M.catalog.page(rows,S.page,S.page_size)
    S.page_label:SetText(FText(S.page.." / "..S.pages.." · "..#rows))
    S.previous:SetIsEnabled(S.page>1);S.next_page:SetIsEnabled(S.page<S.pages)
    for id,e in pairs(S.categories) do S.skin.button(e,"category",id==S.category) end
    M.icons.request(M,page)
    for i,cell in ipairs(S.cells) do
        local row=page[i];cell.row=row;cell.material=nil
        cell.icon=row and M.icons.get(M,row)
        cell.button:SetIsEnabled(row~=nil);cell.image:SetVisibility(1);cell.badge:SetVisibility(row and row.mod and 3 or 1)
    end
    V.icons(M)
end
function V.icons(M)
    local C,S=M.core,M.panel
    for _,cell in ipairs(S.cells) do
        local texture=cell.row and (C.valid(cell.row.object.OverrideIcon) and cell.row.object.OverrideIcon
            or (C.valid(cell.icon) and cell.icon.RenderedIcon))
        if cell.row and not cell.material and C.valid(texture) then
            -- Change only this per-cell dynamic instance, never shared materials.
            local mat=C.class("/Script/Engine.Default__KismetMaterialLibrary")
                :CreateDynamicMaterialInstance(S.widget,S.icon_parent,FName("None"),0)
            mat:SetTextureParameterValue(FName("ItemIcon"),texture)
            cell.image:SetBrushFromMaterial(mat);cell.image:SetVisibility(3);cell.material=mat
        end
    end
end
function V.message(M,value)
    local S=M.panel
    S.status:SetText(FText(value));S.status:SetVisibility(3);S.hover:SetVisibility(1)
    S.feedback_until=M.core.class("/Script/Engine.Default__GameplayStatics"):GetRealTimeSeconds(M.core.player)+3
end
function V.refresh(M)
    local C,S=M.core,M.panel
    local query=S.search:GetText():ToString()
    if query~=S.query then S.query=query;S.page=1;V.render(M) end
    V.icons(M)
    if S.feedback_until and C.class("/Script/Engine.Default__GameplayStatics"):GetRealTimeSeconds(C.player)<S.feedback_until then return end
    S.feedback_until=nil;S.status:SetVisibility(1);S.hover:SetVisibility(4)
    local name,category="",""
    for _,cell in ipairs(S.cells) do
        if cell.row and cell.button:IsHovered() then
            name=cell.row.name;category=S.category_labels[cell.row.category] or M.catalog.label(C,cell.row.category)
            if cell.row.mod then category=category.." · Mod" end
            break
        end
    end
    for _,e in pairs(S.action_buttons) do if e.button:IsHovered() then name=e.label;category="" end end
    S.hover_name:SetText(FText(name));S.hover_category:SetText(FText(category))
end
return V
