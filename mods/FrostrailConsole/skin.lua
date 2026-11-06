-- Native shared materials are read-only. All state colors are brush tints.
return function(C)
    local S={}
    local held,cache={},{}
    local function asset(path)
        if not cache[path] then
            local o=LoadAsset(path);assert(C.valid(o),"Missing console style: "..path)
            cache[path]=o;held[#held+1]=o;C.retain("console_skin",held)
        end
        return cache[path]
    end
    function S.material(path)
        local name=path:match("([^/]+)$")
        return asset("/Game/Frostrail/UI/Materials/"..path.."."..name)
    end
    local function color(r,g,b,a) return {R=r,G=g,B=b,A=a or 1} end
    local function slate(c) return {SpecifiedColor=c,ColorUseRule=0} end
    local WHITE=color(1,1,1)
    local BODY=color(1,.989176,.957114)
    local TITLE=color(.631373,.537255,.411765)
    local DISABLED=color(.197917,.197917,.197917)
    local function font(widget,kind)
        local f=widget.Font
        local name=kind=="category" and "SofiaSans_ExtraCondensed_Regular" or "JosephineSans"
        f.FontObject=asset("/Game/Frostrail/UI/Fonts/UI_Font_"..name..".UI_Font_"..name)
        f.TypefaceFontName=FName(kind=="category" and "SofiaSans_ExtraCondense_Regular" or kind=="title" and "Bold" or "Relugar")
        f.Size=kind=="title" and 16 or 12
        widget:SetFont(f)
        widget:SetColorAndOpacity(slate((kind=="title" or kind=="name") and TITLE or kind=="muted" and color(BODY.R,BODY.G,BODY.B,.6) or BODY))
    end
    function S.text(tree,value,kind)
        local t=C.ui.text(C,tree,value,12);font(t,kind);return t
    end
    function S.button(entry,kind,active)
        local style=entry.button.WidgetStyle
        for _,state in ipairs({"Normal","Hovered","Pressed","Disabled"}) do
            local path,tint
            if kind=="category" then
                path="Base/MI_UI_CategoryButtonTab"
                tint=active and color(.848958,.848958,.848958,.93913) or color(.46875,.46875,.46875,.669565)
                if state=="Hovered" then tint=color(.677083,.677083,.677083,.67) end
                if state=="Pressed" then tint=color(.630208,.630208,.630208,.67) end
            elseif kind=="slot" then
                local suffix=state=="Hovered" and "Hovered" or state=="Pressed" and "Clicked" or "Idle"
                path="Inventory/MI_UI_InventorySlot_"..suffix;tint=WHITE
            else
                local suffix=state=="Hovered" and "Hover" or state=="Pressed" and "Clicked" or "Idle"
                path="Base/MI_UI_BasicButton_"..suffix;tint=WHITE
            end
            if state=="Disabled" then tint=DISABLED end
            local brush=style[state]
            brush.ResourceObject=S.material(path);brush.DrawAs=3;brush.TintColor=slate(tint)
        end
        local n=kind=="slot" and 3 or 2
        style.NormalPadding={Left=n,Top=n,Right=n,Bottom=n}
        style.PressedPadding={Left=n,Top=n,Right=n,Bottom=n}
        entry.button:SetStyle(style);font(entry.text,kind=="category" and "category" or nil)
    end
    function S.search(widget)
        local style=widget.WidgetStyle
        for state,path in pairs({BackgroundImageNormal="MI_UI_InputField",BackgroundImageHovered="MI_UI_InputField_Hovered",
            BackgroundImageFocused="MI_UI_InputField_Clicked",BackgroundImageReadOnly="MI_UI_Stroke_HealthBar"}) do
            style[state].ResourceObject=S.material("Base/"..path);style[state].DrawAs=3;style[state].TintColor=slate(WHITE)
        end
        local f=style.TextStyle.Font
        f.FontObject=asset("/Game/Frostrail/UI/Fonts/UI_Font_SourceSerif.UI_Font_SourceSerif")
        f.TypefaceFontName=FName("SourceSerif-Regular");f.Size=12
        style.TextStyle.ColorAndOpacity=slate(WHITE)
        style.TextStyle.SelectedBackgroundColor=color(.130208,.127234,.023432)
        style.TextStyle.HighlightColor=color(.251736,.243626,.11234)
        style.ForegroundColor=slate(WHITE);style.FocusedForegroundColor=slate(WHITE);style.BackgroundColor=slate(WHITE)
        style.Padding={Left=2,Top=0,Right=2,Bottom=0}
        widget:SetForegroundColor(WHITE)
    end
    local function image(tree,path)
        local i=C.new("/Script/UMG.Image",tree)
        i:SetBrushFromMaterial(S.material(path));i:SetVisibility(3);return i
    end
    function S.frame(overlay)
        local tree=overlay:GetOuter()
        for _,path in ipairs({"Inventory/MI_UI_ContainerBG","Base/MI_UI_Grid_ContainerFrame"}) do
            local slot=overlay:AddChildToOverlay(image(tree,path));slot:SetHorizontalAlignment(0);slot:SetVerticalAlignment(0)
        end
    end
    function S.title_line(tree,width)
        local box=C.new("/Script/UMG.SizeBox",tree);box:SetHeightOverride(8)
        local overlay=C.new("/Script/UMG.Overlay",tree);box:SetContent(overlay)
        local line=overlay:AddChildToOverlay(image(tree,"Base/MI_UI_GridSeparator"));line:SetHorizontalAlignment(0);line:SetVerticalAlignment(0)
        local accent=C.new("/Script/UMG.Border",tree);accent:SetBrushColor(TITLE);accent:SetVisibility(3)
        local size=C.new("/Script/UMG.SizeBox",tree);size:SetWidthOverride(width);size:SetHeightOverride(3);size:SetContent(accent)
        local slot=overlay:AddChildToOverlay(size);slot:SetHorizontalAlignment(1);slot:SetVerticalAlignment(2)
        return box
    end
    function S.badge(tree,overlay)
        local mark=C.new("/Script/UMG.Border",tree);mark:SetBrushColor(TITLE)
        local box=C.new("/Script/UMG.SizeBox",tree);box:SetWidthOverride(7);box:SetHeightOverride(7);box:SetContent(mark)
        local slot=overlay:AddChildToOverlay(box);slot:SetHorizontalAlignment(3);slot:SetVerticalAlignment(1)
        slot:SetPadding({Left=0,Top=1,Right=1,Bottom=0});box:SetVisibility(1)
        return box
    end
    -- Load every resource before constructing any controls. A synchronous asset
    -- load can run GC while a freshly created button/search/text is unattached.
    -- The panel's ObjectLibrary holds these assets until close; WidgetTree then
    -- owns all controls without an intervening asset load in the skin helpers.
    for _,path in ipairs({"Base/MI_UI_ItemIcon","Inventory/MI_UI_ContainerBG","Base/MI_UI_Grid_ContainerFrame",
        "Base/MI_UI_GridSeparator","Base/MI_UI_CategoryButtonTab","Base/MI_UI_BasicButton_Idle",
        "Base/MI_UI_BasicButton_Hover","Base/MI_UI_BasicButton_Clicked","Inventory/MI_UI_InventorySlot_Idle",
        "Inventory/MI_UI_InventorySlot_Hovered","Inventory/MI_UI_InventorySlot_Clicked","Base/MI_UI_InputField",
        "Base/MI_UI_InputField_Hovered","Base/MI_UI_InputField_Clicked","Base/MI_UI_Stroke_HealthBar",
        "Base/MI_UI_Icon_Warmth_Base","Base/MI_UI_Icon_Health_Base"}) do S.material(path) end
    for _,name in ipairs({"JosephineSans","SofiaSans_ExtraCondensed_Regular","SourceSerif"}) do
        asset("/Game/Frostrail/UI/Fonts/UI_Font_"..name..".UI_Font_"..name)
    end
    S.icon_parent=S.material("Base/MI_UI_ItemIcon")
    return S
end
