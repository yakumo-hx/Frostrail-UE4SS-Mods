local M={title="房主菜单暂停"}
local hud_path="/Game/Frostrail/UI/BP_FrostrailHUD.BP_FrostrailHUD_C"
local escape_path="/Game/Frostrail/UI/Widgets/Menus/EscapeMenu/WBP_Menu_Escape.WBP_Menu_Escape_C"

local function host(C,pc)
    if not C.valid(pc) or not pc:IsLocalController() or not pc:HasAuthority() then return false end
    local ps=pc.PlayerState
    return C.valid(ps) and ps:IsA("/Script/Frostrail.FrostrailPlayerState") and ps:IsServerHost()
end

local function remember(object)
    return {object=object,name=object:GetFullName()}
end

-- The world and native HUD own all these objects. Lua only keeps identities;
-- map travel discards them, and a replaced object is never accessed as the old one.
local function current(C,entry)
    return entry and C.instance(entry.object,entry.name)
end

function M:restore_permission()
    local C,entry=self.core,self.pause
    if not entry then return end
    if not current(C,entry.world) or not current(C,entry.mode) or not current(C,entry.settings) then
        self.pause=nil
        return
    end
    if not self.gameplay:IsGamePaused(entry.world.object) then
        if entry.changed_permission and entry.mode.object.bPauseable then
            entry.mode.object.bPauseable=false
        end
        self.pause=nil
    end
end

function M:release()
    local C,entry=self.core,self.pause
    if not entry then return end
    if entry.owned and current(C,entry.world) and current(C,entry.controller)
        and current(C,entry.settings) and current(C,entry.player_state)
        and C.same(entry.controller.object:GetWorld(),entry.world.object)
        and C.same(entry.settings.object.PauserPlayerState,entry.player_state.object) then
        -- Drop ownership before the native call, including its post-hook.
        entry.owned=false
        local resumed=self.gameplay:SetGamePaused(entry.controller.object,false)
        C.log(C.id,"Esc closed; native resume="..tostring(resumed))
    end
    entry.owned=false
    -- ClearPause needs bPauseable to remain true until its delegate list clears.
    -- If another pause remains, leave its permission intact until it ends.
    self:restore_permission()
end

function M:acquire(pc)
    local C=self.core
    if self.cfg and self.cfg.enabled==false then return end
    local world=pc:GetWorld()
    if not C.valid(world) or self.gameplay:IsGamePaused(pc) then return end
    self:restore_permission()
    local mode=self.gameplay:GetGameMode(pc)
    local level=world.PersistentLevel
    local settings=C.valid(level) and level.WorldSettings or nil
    if not C.valid(mode) or not C.valid(settings) then return end
    local entry={world=remember(world),controller=remember(pc),mode=remember(mode),
        settings=remember(settings),player_state=remember(pc.PlayerState),changed_permission=not mode.bPauseable}
    if entry.changed_permission then mode.bPauseable=true end
    local paused=self.gameplay:SetGamePaused(pc,true)
    self.pause=entry
    entry.owned=paused and C.same(settings.PauserPlayerState,pc.PlayerState)
    if not entry.owned then self:restore_permission() end
    C.log(C.id,"Esc opened; native pause="..tostring(paused).." owned="..tostring(entry.owned))
end

function M:prepare_dialog(dialog)
    local C=self.core
    if not self.pause or not self.pause.owned or not C.valid(dialog) then return end
    local pc=dialog:GetOwningPlayer()
    if not current(C,self.menu) or not C.same(pc,self.pause.controller.object) then return end
    -- Native AddButton initializes its text with SetTimerForNextTick. Pausing
    -- that callback leaves "Text Block" buttons and a dangling callback on exit.
    -- Let one complete world tick run before reacquiring our menu pause.
    local pending={menu=self.menu,controller=remember(pc),world=self.pause.world,
        frame=self.system:GetFrameCount()}
    self.settling=pending
    self:release()
    local function finish()
        if self.settling~=pending then return end
        if not current(C,pending.menu) or not current(C,pending.controller)
            or not current(C,pending.world) or self.menu~=pending.menu then
            self.settling=nil
            return
        end
        if self.system:GetFrameCount()<pending.frame+2 then
            ExecuteInGameThreadWithDelay(50,finish)
            return
        end
        self.settling=nil
        self:acquire(pending.controller.object)
    end
    ExecuteInGameThreadWithDelay(50,finish)
end

function M:stack_changed(hud)
    local C=self.core
    if self.cfg and self.cfg.enabled==false then return end
    if not C.valid(hud) then return end
    local pc=hud:GetOwningPlayerController()
    if not host(C,pc) then return end
    local root
    hud.WidgetStack:ForEach(function(_,ref)
        local widget=ref:get()
        if C.valid(widget) and widget:IsA(escape_path) and C.same(widget:GetOwningPlayer(),pc) then
            root=widget
            return true
        end
    end)
    if root and current(C,self.menu) and C.same(root,self.menu.object) then return end
    self.settling=nil
    self:release()
    self.menu=root and remember(root) or nil
    if root then self:acquire(pc) end
end

function M:init()
    local C=self.core
    self.gameplay=C.class("/Script/Engine.Default__GameplayStatics")
    self.system=C.class("/Script/Engine.Default__KismetSystemLibrary")
    LoadAsset(hud_path)
    C.script_hook(hud_path..":OnWidgetStackChanged",function(ctx)
        C.run(C.id,function() self:stack_changed(ctx:get()) end)
    end)
    C.hook("/Script/Frostrail.FRDialogBoxWidget:AddButton",function(ctx)
        C.run(C.id,function() self:prepare_dialog(ctx:get()) end)
    end)
    -- An external native resume ends our ownership even if Esc stays open.
    -- Native post-hooks pass (self, return_value, function arguments...).
    C.hook("/Script/Engine.GameplayStatics:SetGamePaused",nil,function(_,result,context)
        C.run(C.id,function()
            local entry=self.pause
            local object=context:get()
            if not entry or not current(C,entry.world) or not C.valid(object)
                or not C.same(object:GetWorld(),entry.world.object) then return end
            self:restore_permission()
        end)
    end)
    RegisterLoadMapPreHook(function()
        C.run(C.id,function() self.settling=nil; self:release(); self.menu=nil; self.pause=nil end)
    end)
end

function M:player_ready(pc)
    if host(self.core,pc) then self:stack_changed(pc:GetHUD()) end
end

function M:changed()
    self.settling=nil
    self:release()
    self.menu=nil
    if self.core.player_valid() then self:player_ready(self.core.player) end
end

return M
