-- Native UMG controls shared by the menu and inventory extensions.
local M={}
local function state(C)
    C.ui_state=C.ui_state or {clicks={}}
    return C.ui_state
end
local function live(C,entry)
    return C.instance(entry.owner,entry.owner_name) and C.instance(entry.scope,entry.scope_name)
        and C.instance(entry.button,entry.button_name)
end
function M.owned(C,entry,scope)
    return entry and C.instance(scope,entry.scope_name) and C.instance(entry.widget,entry.widget_name)
end
function M.text(C,tree,value,size)
    local text=C.new("/Script/UMG.TextBlock",tree)
    text.Font.Size=size or 12 -- Native default is 24; the settings UI uses half.
    text:SetFont(text.Font)
    text:SetText(FText(value))
    return text
end
function M.button(C,owner,label,callback,size)
    local S=state(C)
    if not S.hooked then
        -- The engine owns this CDO for the process lifetime. Its soft path has
        -- no subpath: pinned UE4SS miscopies nonempty UE 5.6 UTF-8 subpaths as
        -- UTF-16 when allocating a delegate target's first weak serial.
        S.target=StaticFindObject("/Script/UMG.Default__UserWidget")
        assert(C.valid(S.target),"Missing UserWidget CDO")
        S.target_name=S.target:GetFullName()
        C.hook("/Script/UMG.UserWidget:StopAllAnimations",function(ctx)
            if not C.instance(S.target,S.target_name) or not C.same(ctx:get(),S.target) then return end
            local callback
            for id,entry in pairs(S.clicks) do
                if not live(C,entry) then S.clicks[id]=nil
                elseif not callback and entry.button:IsHovered() then callback=entry.callback end
            end
            if callback then C.run("FrostrailUI",callback) end
        end)
        S.hooked=true
    end
    -- Attached hosts/buttons are held by the native widget tree, never rooted
    -- by this Lua registry. Reuse belongs to the owning UI (M.owned). Drop dead
    -- or recycled instances on creation/dispatch; panel.close also removes its
    -- scope immediately. The shared CDO and hook survive world/UI recreation.
    for id,entry in pairs(S.clicks) do if not live(C,entry) then S.clicks[id]=nil end end
    local host=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(owner,C.class("/Script/UMG.UserWidget"),owner:GetOwningPlayer())
    local button=C.new("/Script/UMG.Button",host.WidgetTree)
    button.IsFocusable=false
    local text=M.text(C,host.WidgetTree,label,size)
    text:SetColorAndOpacity({SpecifiedColor={R=0.025,G=0.04,B=0.055,A=1},ColorUseRule=0})
    button:SetContent(text)
    host.WidgetTree.RootWidget=button
    local host_name,scope_name=host:GetFullName(),owner:GetFullName()
    S.clicks[host:GetAddress()]={owner=host,owner_name=host_name,scope=owner,scope_name=scope_name,
        button=button,button_name=button:GetFullName(),callback=callback}
    button.OnClicked:Add(S.target,"StopAllAnimations")
    return {widget=host,widget_name=host_name,scope_name=scope_name,button=button,text=text}
end
function M.icon_button(C,owner,callback)
    local entry=M.button(C,owner,"",callback)
    local tree=entry.widget.WidgetTree
    local image=C.new("/Script/UMG.Image",tree)
    entry.button:SetContent(image)
    local style=entry.button.WidgetStyle
    for _,state in ipairs({"Normal","Hovered","Pressed","Disabled"}) do style[state].DrawAs=0 end
    style.NormalPadding={Left=0,Top=0,Right=0,Bottom=0}
    style.PressedPadding={Left=0,Top=0,Right=0,Bottom=0}
    entry.button:SetStyle(style)
    local box=C.new("/Script/UMG.SizeBox",tree)
    box:SetWidthOverride(24); box:SetHeightOverride(24)
    box:SetContent(entry.button)
    tree.RootWidget=box
    entry.image=image
    return entry
end
return M
