-- Public support library. Every create() owns its callbacks and native objects.
local config=require("Frostrail.config")
local input=require("Frostrail.input")
local settings=require("Frostrail.settings")
local find=require("Frostrail.find")
local M={version="0.3.4"}
local validity_system,native_valid
local menu_path="/Game/Frostrail/UI/Widgets/Menus/MainMenu/WBP_Menu_Main.WBP_Menu_Main_C"
local language_menu="/Game/Frostrail/UI/Widgets/Menus/SettingsMenu/WBP_Element_Settings_General.WBP_Element_Settings_General_C"
local function native_name(id)
    return (id:gsub(".",function(c) return string.format("%02X",c:byte()) end))
end
local function game_root(mods_root)
    local suffix="/frostrail/binaries/win64/ue4ss/mods"
    if mods_root:lower():sub(-#suffix)==suffix then return mods_root:sub(1,-#suffix-1) end
end
function M.create(options)
    options=options or {}
    local caller=debug.getinfo(2,"S").source:sub(2):gsub("\\","/")
    local dir=(caller:match("^(.*)/Scripts/") or caller:match("^(.*)/[^/]+$"))
        :gsub("\\","/"):gsub("/$","")
    local id=dir:match("([^/]+)$")
    local root=dir:match("^(.*)/[^/]+$")
    local C={id=id,title=id,dir=dir,root=root,version=M.version,
        game_root=game_root(root),
        actions={},config=config,settings=settings,native_id=native_name(id)}
    C.ui=require("Frostrail.ui")
    C.text=require("Frostrail.locale").text
    function C.log(id,message) print("["..id.."] "..message.."\n") end
    function C.valid(o)
        if o==nil or not o:IsValid() then return false end
        if not native_valid then
            validity_system=StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
            native_valid=StaticFindObject("/Script/Engine.KismetSystemLibrary:IsValid")
        end
        -- system:IsValid(o) resolves to UE4SS's same-named Lua method.
        return native_valid(validity_system,o)
    end
    function C.same(a,b) return C.valid(a) and C.valid(b) and a:GetAddress()==b:GetAddress() end
    function C.instance(o,name) return name~=nil and C.valid(o) and o:GetFullName()==name end
    function C.player_valid() return C.instance(C.player,C.player_name) end
    function C.pawn_valid() return C.player_valid() and C.instance(C.pawn,C.pawn_name) end
    function C.class(path) return StaticFindObject(path) end
    function C.new(path,outer,name) return StaticConstructObject(C.class(path),outer,name and FName(name) or 0) end
    function C.run(label,fn,...)
        local args=table.pack(...)
        local ok,value=xpcall(function() return fn(table.unpack(args,1,args.n)) end,debug.traceback)
        if not ok then C.log(label,"ERROR "..tostring(value)); return nil end
        return value
    end
    function C.hook(path,pre,post)
        local a,b=RegisterHook(path,pre or function() end,post)
        C.log(C.id,"Hook "..path.." ids="..a..","..b)
    end
    function C.script_hook(path,callback)
        local a,b=RegisterHook(path,callback)
        C.log(C.id,"Script post-hook "..path.." ids="..a..","..b)
    end
    function C.retain(group,objects)
        if not C.valid(C.assets) then
            C.assets=StaticConstructObject(C.class("/Script/Engine.ObjectLibrary"),StaticFindObject("/Script/Engine"),
                FName("Frostrail_Assets_"..C.native_id),0,EInternalObjectFlags.RootSet)
            C.asset_groups={}
        end
        C.asset_groups[group]=objects
        local all={}
        for _,items in pairs(C.asset_groups) do for _,item in ipairs(items) do all[#all+1]=item end end
        C.assets.Objects=all
    end
    function C.action(name,label,key,callback,action_options)
        local a=action_options or {}
        C.actions[#C.actions+1]={name=(options.action_prefix or C.id).."."..name,
            label=label,key=key,callback=callback,allow_ui=a.allow_ui==true,requires_pawn=a.requires_pawn~=false}
    end
    -- Internal, not in the package spec: Console closes on Esc with it while
    -- its search box holds focus, where the native page never sees the key.
    -- A fixed (not rebindable) key whose callback runs on the game thread.
    function C.key(code,callback) input.key(C,code,callback) end
    function C.message(message)
        C.log(C.id,message)
        if C.panel_open then require("Frostrail.panel").message(C,message) end
        if C.player_valid() then
            C.class("/Script/Engine.Default__KismetSystemLibrary"):PrintString(C.player,message,true,false,{R=0.5,G=0.9,B=1,A=1},4,FName("FrostrailMods"))
        end
    end
    function C.snapshot(inv)
        local result={}
        inv.InventoryRecord.ContainableTable:ForEach(function(k,v) result[k:get().ID]=v:get() end)
        return result
    end
    function C.call(method,...)
        local m=C.module
        if not m or m.failed then return false end
        if not m[method] then return true end
        local args=table.pack(...)
        local ok,err=xpcall(function() m[method](m,table.unpack(args,1,args.n)) end,debug.traceback)
        if not ok then m.failed=true; C.log(C.id,"ERROR "..err) end
        return ok
    end
    function C.set_player(pc,pawn)
        local same_player=C.player_valid() and C.same(C.player,pc)
        local same_pawn=(C.pawn==nil and pawn==nil) or (C.pawn_valid() and C.same(C.pawn,pawn))
        if same_player and same_pawn then return false end
        if C.panel_state then require("Frostrail.panel").close(C,false) end
        if C.initialized then C.call("player_left") end
        C.player,C.pawn=pc,pawn
        C.player_name=C.valid(pc) and pc:GetFullName() or nil
        C.pawn_name=C.valid(pawn) and pawn:GetFullName() or nil
        return true
    end
    function C.initialize()
        if C.initialized then return end
        C.initialized=true
        if C.call("init") then C.log(C.id,"initialized") end
    end
    function C.player_ready(pc,pawn)
        if not C.valid(pc) then return end
        if not C.valid(pawn) or not pawn:IsA("/Script/Frostrail.PlayerCharacter") then
            C.set_player(pc,nil)
            if #C.actions>0 then input.attach(C,pc) end
            return
        end
        C.initialize()
        if not C.set_player(pc,pawn) then return end
        if #C.actions>0 then input.attach(C,pc) end
        C.call("player_ready",pc,pawn)
        C.log(C.id,"Player bound "..pawn:GetFullName().." authority="..tostring(pawn:HasAuthority()))
    end
    function C.register_settings() return settings.register(C) end
    function C.reload()
        local m=C.module
        m.cfg=config.load(C.dir)
        if not C.call("changed") then return false end
        C.log(C.id,"Configuration reloaded; live settings applied")
    end
    function C.start(module)
        C.module=module
        module.id,module.dir,module.core=C.id,C.dir,C
        C.title=module.title or C.id
        module.cfg=config.load(C.dir)
        C.call("setup")
        RegisterConsoleCommandGlobalHandler(settings.command(C.id),function()
            ExecuteInGameThread(function() C.run(C.id,C.reload) end)
            return true
        end)
        if options.settings~=false then C.run(C.id,C.register_settings) end
        C.hook("/Script/Engine.PlayerController:ClientRestart",nil,function(ctx,pawn)
            C.run(C.id,C.player_ready,ctx:get(),pawn:get())
        end)
        if module.actor_ready then
            RegisterBeginPlayPostHook(function(ctx)
                local actor=ctx:get()
                if C.initialized and C.valid(actor) then C.call("actor_ready",actor) end
            end)
        end
        ExecuteInGameThreadWithDelay(2000,function()
            if #C.actions>0 or module.language_changed then
                LoadAsset(language_menu)
                -- The menu's native SetGameLanguage call bypasses RegisterHook
                -- in the pinned build. Its Blueprint selection event does not.
                C.script_hook(language_menu..":BndEvt__WBP_Element_Settings_General_WBP_Common_Dropdown_Language_K2Node_ComponentBoundEvent_0_OnSelectionChanged__DelegateSignature",function()
                    C.run(C.id,function()
                        if #C.actions>0 then input.refresh_labels(C) end
                        if C.initialized then C.call("language_changed") end
                    end)
                end)
            end
            C.initialize()
            if #C.actions>0 then
                local function attach_menu(menu)
                    if not C.valid(menu) then return end
                    local pc=find.controller(C,menu)
                    if C.valid(pc) then C.set_player(pc,nil); input.attach(C,pc) end
                end
                LoadAsset(menu_path)
                C.script_hook(menu_path..":Construct",function(ctx) C.run(C.id,attach_menu,ctx:get()) end)
                for _,menu in ipairs(FindAllOf("WBP_Menu_Main_C") or {}) do
                    if menu:IsInViewport() then C.run(C.id,attach_menu,menu) end
                end
            end
            local pc=find.controller(C,nil,"BP_FrostrailPlayerController_C")
            if C.valid(pc) then C.run(C.id,C.player_ready,pc,pc:GetBoundCharacterPawn()) end
        end)
        C.log(C.id,"Independent entry registered")
        return C
    end
    return C
end
return M
