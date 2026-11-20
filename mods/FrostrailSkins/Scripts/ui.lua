-- The status page owns the entry button and the capture that feeds both portraits.
local C, api = ...
local UI = {}
local hudPath = "/Game/Frostrail/UI/BP_FrostrailHUD.BP_FrostrailHUD_C"
local inventoryPath = "/Game/Frostrail/UI/Widgets/Composites/WBP_Composite_Inventory+Status.WBP_Composite_Inventory+Status_C"
local statusPath = "/Game/Frostrail/UI/Widgets/Status/WBP_Main_PlayerStatus.WBP_Main_PlayerStatus_C"
local entry, panel, styles
local cream = {R=.96,G=.91,B=.81,A=1}
local gold = {R=.85,G=.68,B=.42,A=1}
local function margin(l,t,r,b) return {Left=l,Top=t,Right=r,Bottom=b} end
local function paint(text,color)
    text:SetColorAndOpacity({SpecifiedColor=color,ColorUseRule=0})
end
local function size(tree,child,width,height)
    local box = C.new("/Script/UMG.SizeBox",tree)
    if width then box:SetWidthOverride(width) end
    if height then box:SetHeightOverride(height) end
    box:SetContent(child)
    return box
end
local function styleAssets()
    if styles then return end
    local result, held = {}, {}
    for _,name in ipairs({"Idle","Hover","Clicked"}) do
        local path = "/Game/Frostrail/UI/Materials/Base/MI_UI_BasicButton_"..name
        local asset = LoadAsset(path.."."..path:match("([^/]+)$"))
        assert(C.valid(asset),"Missing skin menu brush "..name)
        held[#held+1] = asset
        C.retain("skins_ui_brushes",held)
        result[name] = asset
    end
    styles = result
end
local function button(owner,label,callback)
    local e = C.ui.button(C,owner,label,callback,16)
    local style = e.button.WidgetStyle
    for state,name in pairs({Normal="Idle",Hovered="Hover",Pressed="Clicked",Disabled="Idle"}) do
        style[state].ResourceObject = styles[name]
        style[state].DrawAs = 3
        style[state].TintColor = {SpecifiedColor={R=1,G=1,B=1,A=1},ColorUseRule=0}
    end
    style.NormalPadding = margin(8,4,8,4)
    style.PressedPadding = margin(8,5,8,3)
    e.button:SetStyle(style)
    e.text:SetJustification(1)
    paint(e.text,cream)
    return e
end
local function attached(e)
    return e and C.pawn_valid() and C.instance(C.pawn,e.pawnName) and C.instance(C.player,e.pcName)
        and C.instance(e.hud,e.hudName) and C.same(e.hud,C.player:GetHUD())
        and C.instance(e.inventory,e.inventoryName) and e.hud:IsWidgetInStack(e.inventory)
        and C.instance(e.status,e.statusName) and C.same(e.status:GetOwningPlayer(),C.player)
end
local function forgetButton(e)
    if e and C.ui_state then C.ui_state.clicks[e.widgetId] = nil end
end
local function removeEntry()
    local e = entry
    entry = nil
    if not e then return end
    forgetButton(e)
    if C.instance(e.widget,e.widgetName) then e.widget:RemoveFromParent() end
end
local function close()
    local p = panel
    if not p then return end
    panel = nil
    for _,e in ipairs(p.buttons) do forgetButton(e) end
    if C.instance(p.widget,p.name) then
        local index
        if C.instance(p.hud,p.hudName) then
            p.hud.WidgetStack:ForEach(function(i,ref)
                if C.same(p.widget,ref:get()) then index=i-1 end
            end)
        end
        if index then p.hud:RemoveWidgetFromStackByIndex(index) end
        if C.valid(p.widget:GetParent()) then p.widget:RemoveFromParent() end
    end
    C.retain("skins_ui_page",{})
    if p.busy then C.settings.set_busy(false) end
    api.preview(nil)
end
local function active(p)
    return p==panel and attached(entry) and C.instance(p.widget,p.name)
        and C.same(p.hud:GetTopmostWidgetFromStack(),p.widget)
end
local function render(p)
    for _,row in ipairs(p.rows) do
        local candidate = row.id == p.candidate
        paint(row.entry.text,candidate and gold or cream)
        row.mark:SetVisibility(candidate and 3 or 1)
    end
    local shown = api.showBack(p.candidate)
    p.back.widget:SetVisibility(p.candidate=="original" and 1 or 0)
    p.back.text:SetText(FText(shown and C.text("背部装备　显示","Back equipment   On")
        or C.text("背部装备　隐藏","Back equipment   Off")))
end
local function buildPage(e)
    local lib = C.class("/Script/UMG.Default__WidgetBlueprintLibrary")
    local w = lib:Create(C.player,C.class("/Script/Frostrail.FRCompositeWidgetBase"),C.player)
    local tree = w.WidgetTree
    local p = {widget=w,name=w:GetFullName(),hud=e.hud,hudName=e.hudName,
        candidate=api.selected(),buttons={},rows={},building=true}
    panel = p
    C.retain("skins_ui_page",{w})
    w.RequiredInputState=2
    w.bHideHud=false
    w.bHideCrosshair=true
    w.bHideCursor=false
    w.bIsClosableByUserInput=true
    w.bIsFocusable=true
    local function new(class) return C.new("/Script/UMG."..class,tree) end
    local function makeButton(label,callback)
        local b = button(w,label,function() if active(p) then callback() end end)
        b.widgetId=b.widget:GetAddress()
        p.buttons[#p.buttons+1]=b
        return b
    end
    local shade = new("Border")
    tree.RootWidget=shade
    shade:SetBrushColor({R=.012,G=.014,B=.016,A=1})
    shade:SetHorizontalAlignment(2)
    shade:SetVerticalAlignment(2)
    local column = new("VerticalBox")
    shade:SetContent(size(tree,column,800,644))
    local title=C.ui.text(C,tree,C.text("人物皮肤","Character Skins"),28)
    paint(title,gold)
    column:AddChildToVerticalBox(title):SetPadding(margin(0,0,0,10))
    local line=new("Border")
    line:SetBrushColor({R=.43,G=.36,B=.24,A=.85})
    column:AddChildToVerticalBox(size(tree,line,nil,1))
    local body = new("HorizontalBox")
    column:AddChildToVerticalBox(body):SetSize({SizeRule=1,Value=1})
    local portrait = new("Image")
    portrait:SetBrushFromMaterial(e.status.PlayerRenderMaterial)
    portrait:SetVisibility(3)
    body:AddChildToHorizontalBox(size(tree,portrait,432,576)):SetVerticalAlignment(2)
    local controls=new("VerticalBox")
    local cs=body:AddChildToHorizontalBox(controls)
    cs:SetPadding(margin(28,24,0,12))
    cs:SetSize({SizeRule=1,Value=1})
    local choices=new("ScrollBox")
    controls:AddChildToVerticalBox(choices):SetSize({SizeRule=1,Value=1})
    for _,skin in ipairs(api.list()) do
        local id=skin.id
        local b=makeButton(C.text(skin.name.zh,skin.name.en),function()
            api.preview(id)
            p.candidate=id
            render(p)
        end)
        local row=new("HorizontalBox")
        local mark=new("Border")
        mark:SetBrushColor(gold)
        local marker=size(tree,mark,4,nil)
        row:AddChildToHorizontalBox(marker):SetPadding(margin(0,3,4,3))
        row:AddChildToHorizontalBox(b.widget):SetSize({SizeRule=1,Value=1})
        choices:AddChild(size(tree,row,nil,38))
        p.rows[#p.rows+1]={id=id,mark=mark,entry=b}
    end
    p.back=makeButton("",function()
        api.setBack(p.candidate,not api.showBack(p.candidate))
        render(p)
    end)
    controls:AddChildToVerticalBox(p.back.widget):SetPadding(margin(0,8,0,12))
    local actions=new("HorizontalBox")
    controls:AddChildToVerticalBox(actions)
    local cancel=makeButton(C.text("取消","Cancel"),close)
    local apply=makeButton(C.text("确定","Apply"),function()
        if api.apply(p.candidate)~=false then close() end
    end)
    for _,b in ipairs({cancel,apply}) do
        actions:AddChildToHorizontalBox(b.widget):SetSize({SizeRule=1,Value=1})
    end
    render(p)
    assert(p.hud:AddWidgetToStack(w,{X=0,Y=0})>=0,"Could not open the character skins page")
    w.Slot:SetHorizontalAlignment(0)
    w.Slot:SetVerticalAlignment(0)
    p.building=false
    p.busy=true
    C.settings.set_busy(true)
end
local function open(e)
    if panel or C.settings.busy() or not attached(e) or not C.valid(e.status.PlayerRenderMaterial)
        or not C.same(e.hud:GetTopmostWidgetFromStack(),e.inventory) then return end
    local ok,err=xpcall(function() buildPage(e) end,debug.traceback)
    if not ok then close(); error(err) end
end
local function sync(hud)
    if panel and panel.building then return end
    if not C.pawn_valid() or not C.same(hud,C.player:GetHUD()) then return end
    if panel and (not attached(entry) or not C.instance(panel.widget,panel.name)
        or not hud:IsWidgetInStack(panel.widget) or not C.valid(panel.widget:GetParent())) then close() end
    if attached(entry) and C.instance(entry.widget,entry.widgetName) and C.valid(entry.widget:GetParent()) then return end
    removeEntry()
    local inventory=hud:GetTopmostWidgetFromStack()
    if not C.valid(inventory) or not inventory:IsA(inventoryPath) or not C.same(inventory:GetOwningPlayer(),C.player) then return end
    local status=inventory.WBP_Main_PlayerStatus
    if not C.valid(status) or not C.valid(status.PlayerDisplayButton) then return end
    local canvas=status.PlayerDisplayButton:GetParent()
    if not C.valid(canvas) or not canvas:IsA("/Script/UMG.CanvasPanel") then return end
    styleAssets()
    local e={inventory=inventory,inventoryName=inventory:GetFullName(),status=status,statusName=status:GetFullName(),
        hud=hud,hudName=hud:GetFullName(),pcName=C.player_name,pawnName=C.pawn_name}
    local b=button(status,C.text("人物皮肤","Skins"),function() if entry==e then open(e) end end)
    e.widget,e.widgetName,e.widgetId=b.widget,b.widget_name,b.widget:GetAddress()
    entry=e
    local slot=canvas:AddChildToCanvas(b.widget)
    slot:SetAnchors({Minimum={X=.73,Y=0},Maximum={X=.73,Y=0}})
    slot:SetAlignment({X=.5,Y=0})
    slot:SetPosition({X=0,Y=8})
    slot:SetSize({X=110,Y=34})
    slot:SetZOrder(1)
end
function UI.bind()
    if C.pawn_valid() then sync(C.player:GetHUD()) end
end
function UI.clear()
    close()
    removeEntry()
    styles=nil
    C.retain("skins_ui_brushes",{})
end
LoadAsset(hudPath)
C.script_hook(hudPath..":OnWidgetStackChanged",function(ctx)
    C.run(C.id,sync,ctx:get())
end)
-- A lower inventory's input mode (3) otherwise wins the HUD's fold over this
-- page's UIOnly (2). The HUD reapplies the lower page's mode when it pops us.
C.hook("/Script/Frostrail.FrostrailHUDBase:GetCurrentInputState",nil,function(ctx)
    if panel and C.instance(ctx:get(),panel.hudName) and C.instance(panel.widget,panel.name)
        and C.same(panel.hud:GetTopmostWidgetFromStack(),panel.widget) then return 2 end
end)
LoadAsset(statusPath)
C.script_hook(statusPath..":Construct",function()
    -- Construct may precede insertion in the inventory/HUD hierarchy.
    ExecuteInGameThreadWithDelay(1,function() C.run(C.id,UI.bind) end)
end)
return UI
