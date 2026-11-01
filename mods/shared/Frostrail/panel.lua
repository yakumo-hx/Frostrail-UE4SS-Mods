local M={}
local settings=require("Frostrail.settings")
local editors=require("Frostrail.editors")
local language=require("Frostrail.locale").language
local function tr(C,zh,en) return C.panel_state and C.panel_state.language=="en" and en or zh end
local function state(C)
    C.panel_state=C.panel_state or {menus={}}
    return C.panel_state
end
local function library() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end
local function live(C)
    local S=state(C)
    return C.instance(S.widget,S.widget_name) and C.instance(S.controller,S.controller_name) and S.widget:IsInViewport()
end
function M.close(C,restore_input)
    local S=state(C)
    if C.instance(S.widget,S.widget_name) then S.widget:RemoveFromParent() end
    if restore_input~=false and C.instance(S.controller,S.controller_name) and C.player_valid() and C.same(S.controller,C.player) then
        C.player.bShowMouseCursor=S.old_cursor or false
        if S.old_cursor then library():SetInputMode_GameAndUIEx(C.player,nil,0,false,false)
        else library():SetInputMode_GameOnly(C.player,false) end
    end
    if C.ui_state then
        for id,entry in pairs(C.ui_state.clicks) do
            if entry.scope_name==S.widget_name then C.ui_state.clicks[id]=nil end
        end
    end
    S.widget,S.widget_name,S.controller,S.controller_name,S.status,S.editors,S.old_cursor=nil,nil,nil,nil,nil,nil,nil
    C.panel_open=false; settings.set_busy(false)
end
function M.message(C,message)
    if live(C) then state(C).status:SetText(FText(message)) else M.close(C,false) end
end
function M.apply(C)
    if not live(C) then M.close(C,false); return end
    local changes={}
    for _,entry in ipairs(state(C).editors or {}) do
        local f,editor=entry.field,entry.editor
        local ok,value=pcall(entry.read or function() return editors.read(f,editor,state(C).language) end)
        if not ok then C.message(tostring(value)); return end
        -- Track edits against the displayed snapshot, not every visible field.
        if not editors.equal(value,editors.normalized(f,entry.original)) then
            local path=entry.config.path
            changes[path]=changes[path] or {description=entry.config,fields={}}
            changes[path].fields[f.key]={entry=entry,value=value}
        end
    end
    local changed_ids={}
    for path,change in pairs(changes) do
        -- Merge only edited fields into the latest file; preserve concurrent changes.
        local value=settings.read_config(C,change.description)
        local dirty=false
        for key,edit in pairs(change.fields) do
            if not editors.equal(editors.normalized(edit.entry.field,settings.get(value,key)),edit.value) then
                settings.set(value,key,edit.value)
                changed_ids[edit.entry.id]=true
                dirty=true
            end
        end
        if dirty then C.config.save(path,value) end
        for _,edit in pairs(change.fields) do edit.entry.original=edit.value end
    end
    for id in pairs(changed_ids) do settings.notify(C,id) end
    if next(changed_ids) then C.message(tr(C,"配置已保存，已通知对应模组应用即时设置。","Saved; the affected mods have applied their live settings."))
    else C.message(tr(C,"没有需要保存的修改。","No changes to save.")) end
end
local function live_fields(description)
    local fields={}
    for _,f in ipairs(description.fields or {}) do
        if f.live then fields[#fields+1]=f end
    end
    return fields
end
function M.toggle(C,controller)
    if live(C) then M.close(C); return end
    M.close(C,false)
    local pc=controller or C.player
    if not C.player_valid() or not C.same(pc,C.player) then return end
    local S=state(C)
    S.language=language()
    local w=library():Create(pc,C.class("/Script/UMG.UserWidget"),pc)
    assert(C.valid(w),"Cannot create settings panel")
    S.widget,S.widget_name,S.controller,S.controller_name=w,w:GetFullName(),pc,pc:GetFullName()
    S.editors={}; C.panel_open=true; settings.set_busy(true)
    local tree=w.WidgetTree
    local function new(name) return C.new("/Script/UMG."..name,tree) end
    local function text(value) return C.ui.text(C,tree,value,12) end
    local border=new("Border")
    border:SetBrushColor({R=0.025,G=0.04,B=0.055,A=0.98})
    border:SetPadding({Left=18,Top=16,Right=18,Bottom=16})
    local column=new("VerticalBox"); border:SetContent(column); tree.RootWidget=border
    local function row(widget) column:AddChildToVerticalBox(widget):SetPadding({Left=0,Top=4,Right=0,Bottom=4}) end
    row(text(tr(C,"Frostrail 模组设置","Frostrail mod settings")))
    row(text(tr(C,"这里只显示即时设置；完整设置在管理器，按键在游戏“设置 → 控制”。",
        "Live settings only. Use the manager for all settings; rebind keys in Settings > Controls.")))
    local scroll=new("ScrollBox")
    column:AddChildToVerticalBox(scroll):SetSize({SizeRule=1,Value=1})
    local body=new("VerticalBox"); scroll:AddChild(body)
    for _,record in ipairs(settings.list()) do
        do
            local description=record.config
            local descriptors=live_fields(description)
            if #descriptors>0 then
                local cfg=settings.read_config(C,description)
                local group=new("Border")
                group:SetBrushColor({R=0.055,G=0.075,B=0.09,A=1})
                group:SetPadding({Left=12,Top=9,Right=12,Bottom=9})
                body:AddChildToVerticalBox(group):SetPadding({Left=0,Top=4,Right=0,Bottom=5})
                local fields=new("VerticalBox"); group:SetContent(fields)
                local title=text(settings.label(record.title,S.language))
                title:SetColorAndOpacity({SpecifiedColor={R=0.55,G=0.85,B=1,A=1},ColorUseRule=0})
                fields:AddChildToVerticalBox(title):SetPadding({Left=0,Top=0,Right=0,Bottom=7})
                local previous_group
                for _,f in ipairs(descriptors) do
                    local group_name=settings.label(f.group,S.language)
                    if group_name~="" and group_name~=previous_group then
                        fields:AddChildToVerticalBox(text(group_name)):SetPadding({Left=0,Top=8,Right=0,Bottom=4})
                    end
                    previous_group=group_name
                    local line=new("HorizontalBox")
                    line:AddChildToHorizontalBox(text(settings.label(f.label,S.language))):SetSize({SizeRule=1,Value=1})
                    local default=settings.get(description.defaults,f.key)
                    local value=settings.get(cfg,f.key)
                    if value==nil then value=default end
                    local editor,read=editors.create(C,w,f,value,default,S.language)
                    line:AddChildToHorizontalBox(editor)
                    fields:AddChildToVerticalBox(line):SetPadding({Left=0,Top=2,Right=0,Bottom=2})
                    S.editors[#S.editors+1]={id=record.id,config=description,field=f,editor=editor,read=read,original=value}
                end
            end
        end
    end
    local actions=new("HorizontalBox"); row(actions)
    local function button(label,callback)
        local entry=C.ui.button(C,w,label,callback)
        local slot=actions:AddChildToHorizontalBox(entry.widget)
        slot:SetSize({SizeRule=1,Value=1}); slot:SetPadding({Left=2,Top=0,Right=2,Bottom=0})
    end
    button(tr(C,"应用并保存","Apply and save"),function() M.apply(C) end)
    button(tr(C,"重新读取配置","Reload settings"),function() M.close(C); M.toggle(C,pc) end)
    button(tr(C,"关闭","Close"),function() M.close(C) end)
    S.status=text(tr(C,"只应用即时设置，未显示的配置保持不变。","Only edited live settings are applied."))
    row(S.status)
    w:SetDesiredSizeInViewport({X=670,Y=720})
    w:SetPositionInViewport({X=80,Y=50},false)
    w:AddToViewport(100)
    S.old_cursor=pc.bShowMouseCursor; pc.bShowMouseCursor=true
    library():SetInputMode_UIOnlyEx(pc,w,0,false)
    C.log(C.id,"Settings panel opened; "..#S.editors.." live controls; main_menu="..tostring(not C.pawn_valid()))
end
function M.bind_menu(C,menu)
    if not C.valid(menu) or not C.valid(menu.Settings) then return end
    local pc=menu:GetOwningPlayer()
    if not C.valid(pc) then pc=FindFirstOf("PlayerController") end
    if not C.valid(pc) then return end
    C.set_player(pc,nil)
    local S=state(C)
    local id=menu:GetAddress()
    local entry=S.menus[id]
    if C.ui.owned(C,entry,menu) then return end
    for key,value in pairs(S.menus) do if not C.ui.owned(C,value,value.owner) then S.menus[key]=nil end end
    entry=C.ui.button(C,menu,language()=="en" and "Mod settings" or "模组设置",function()
        local owner=menu:GetOwningPlayer()
        if not C.valid(owner) then owner=FindFirstOf("PlayerController") end
        C.set_player(owner,nil)
        M.toggle(C,owner)
    end,18)
    entry.owner=menu
    menu.Settings:GetParent():AddChildToVerticalBox(entry.widget):SetPadding({Left=0,Top=6,Right=0,Bottom=6})
    S.menus[id]=entry
    require("Frostrail.input").attach(C,pc)
    C.log(C.id,"Main-menu settings button registered")
end
function M.install_menu(C)
    local path="/Game/Frostrail/UI/Widgets/Menus/MainMenu/WBP_Menu_Main.WBP_Menu_Main_C"
    LoadAsset(path)
    C.script_hook(path..":Construct",function(ctx) C.run(C.id,M.bind_menu,C,ctx:get()) end)
    for _,menu in ipairs(FindAllOf("WBP_Menu_Main_C") or {}) do if menu:IsInViewport() then M.bind_menu(C,menu) end end
end
return M
