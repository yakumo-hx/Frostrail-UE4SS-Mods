local M={title="控制台"}
local function widget_library() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end
function M:player()
    local C=self.core
    if not C.player_valid() then return end
    local pc=C.player
    if not pc:IsA("/Script/Frostrail.FrostrailPlayerControllerBase") or not pc:IsLocalController() or not C.pawn_valid() then return end
    local pawn=pc:GetBoundCharacterPawn()
    if not C.valid(pawn) or not pawn.bIsAlive then return end
    return pc,pawn
end
function M:host()
    local pc,pawn=self:player()
    if not pc or not pc:HasAuthority() or not pawn:HasAuthority() then return end
    local state=pc.PlayerState
    if not self.core.valid(state) or not state:IsServerHost() then return end
    return pc,pawn
end
function M:live()
    local C,S=self.core,self.panel
    local pc,pawn=self:player()
    return S and not S.building and pc and C.instance(S.widget,S.name) and S.widget:IsInViewport()
        and C.instance(pc,S.controller_name) and C.instance(pawn,S.pawn_name)
end
function M:close(restore)
    local C,S=self.core,self.panel
    if not S then return end
    self.panel=nil
    -- WidgetTree owns the controls and their materials. Drop dispatch entries
    -- before removing it; a delayed callback may only touch its own panel.
    if C.ui_state then
        for id,entry in pairs(C.ui_state.clicks) do
            if entry.scope_name==S.name then C.ui_state.clicks[id]=nil end
        end
    end
    if C.instance(S.widget,S.name) then S.widget:RemoveFromParent() end
    C.retain("console_skin",{})
    C.retain("console_panel",{})
    C.settings.set_busy(false)
    -- A respawn can retire the pawn while its local controller still owns our
    -- UI-only input mode. Restore that controller even when the pawn is gone.
    local pc=C.player_valid() and C.player
    if restore~=false and pc and C.instance(pc,S.controller_name) then
        pc.bShowMouseCursor=S.cursor
        if S.cursor then widget_library():SetInputMode_GameAndUIEx(pc,nil,0,false,true)
        else widget_library():SetInputMode_GameOnly(pc,true) end
    end
end
function M:toggle()
    local C=self.core
    if self.panel and self.panel.building then return end
    if self:live() then self:close(); return end
    self:close()
    local pc=self:player()
    if not pc then return end
    if not self:host() then C.message(C.text("只有单人游戏或房主能用","Only available in single player or to the host")); return end
    if C.settings.busy() or pc.bShowMouseCursor then return end
    if not self.rows then self.rows,self.excluded=self.catalog.build(C) end
    self.catalog.names(C,self.rows)
    local ok,err=xpcall(function() self.view.open(self) end,debug.traceback)
    if not ok then self:close(); C.log(C.id,"ERROR "..err) end
end
function M:restore(attribute)
    if not self:live() then return end
    local C=self.core
    local pc,pawn=self:host()
    if not pc then return end
    local values=pawn.AbilitySystemComponent:GetAttributeViewModel()
    local before=attribute=="warmth" and values.CurrentWarmth or values.CurrentHealth
    local cheat=C.new("/Script/Frostrail.FrostrailCheatManager",pc)
    C.retain("console_action",{cheat})
    local ok,err=xpcall(function()
        if attribute=="warmth" then cheat:SetWarmthAttribute(values.MaxWarmth,0)
        else cheat:HealCharacter(0) end
    end,debug.traceback)
    C.retain("console_action",{})
    if not ok then error(err) end
    local after=attribute=="warmth" and values.CurrentWarmth or values.CurrentHealth
    local maximum=attribute=="warmth" and values.MaxWarmth or values.MaxHealth
    self.last_restore={attribute=attribute,before=before,after=after,maximum=maximum}
    local label=attribute=="warmth" and C.text("体温","Warmth") or C.text("血量","Health")
    self:message(label..string.format("  %.0f / %.0f",after,maximum))
end
function M:message(value)
    if self:live() then self.view.message(self,value) end
    self.core.log(self.core.id,value)
end
-- Shift-click amount comes from the settings (F8 or the manager), default 10.
function M:batch_count()
    local n=self.cfg and self.cfg.batch_count
    if type(n)~="number" or n<1 or n%1~=0 then return 10 end
    return math.min(n,999)
end
-- Native OnClicked runs on the game thread, so read Slate's modifier snapshot
-- here: Shift still held when the click completes gives the batch amount.
function M:click(row)
    local input=self.core.class("/Script/Engine.Default__KismetInputLibrary")
    local shift=input:ModifierKeysState_IsShiftDown(input:GetModifierKeysState())
    self:give(row,shift and self:batch_count() or 1)
end
function M:escape()
    local C,S=self.core,self.panel
    if not self:live() or S.closing then return end
    S.closing=true
    -- Keep UI-only input through the physical press so the same Esc
    -- cannot reach the game's menu action or Assist's menu pause.
    ExecuteInGameThreadWithDelay(120,function()
        if self.panel==S then C.run(C.id,function() self:close() end) end
    end)
end
function M:give(row,quantity)
    local C=self.core
    if not self:live() then self:close(); return end
    local pc,pawn=self:host()
    if not pc or not C.instance(row.object,row.path) then return end
    local system=pawn.ItemSystemComponent
    local bag=system:GetInventory()
    local before=bag:CalculateTotalItemAmountByType(row.object)
    local created=C.class("/Script/Frostrail.Default__GameplayUtils"):CreateItems(bag,row.object,quantity)
    -- The returned TArray is not a GC owner. Retain all newly created stacks
    -- until native storage transfers ownership to the bag or a pickup actor.
    local items={}
    for _,ref in ipairs(created) do items[#items+1]=ref:get() end
    C.retain("console_giving",items)
    local generated,unplaced=0,false
    local ok,err=xpcall(function()
        for _,item in ipairs(items) do
            generated=generated+item:GetInventoryStackNum()
            if not system:StoreContainable(item,true) then unplaced=true end
        end
    end,debug.traceback)
    C.retain("console_giving",{})
    if not ok then self:message(C.text("给予中断，请检查背包；没有重试。","Giving interrupted; check your inventory. No retry was made.")); error(err) end
    local gained=bag:CalculateTotalItemAmountByType(row.object)-before
    local text=C.text("已获得 ","Received ")..row.name.." ×"..gained
    if gained<generated or unplaced then
        text=text..C.text("；其余物品请查看脚边（×","; check your feet for the remainder (×")..math.max(0,generated-gained)..")"
    end
    self.last_give={path=row.path,requested=quantity,created=generated,gained=gained,stacks=#items,unplaced=unplaced}
    self:message(text)
end
function M:reset(restore)
    self:close(restore)
    self.icons.clear(self)
    self.rows,self.excluded=nil,nil
    self.core.retain("console_catalog",{})
end
function M:player_left() self:reset() end
function M:language_changed()
    -- The next opening reads names after all content packs finish their own
    -- language callbacks. World-scoped icons survive until departure/map reset.
    self:close()
end
function M:setup()
    local C=self.core
    self.catalog=dofile(C.dir.."/catalog.lua")
    self.icons=dofile(C.dir.."/icons.lua")
    self.view=dofile(C.dir.."/view.lua")
    C.action("Console",{zh="控制台",en="Console"},"Y",function() self:toggle() end,{allow_ui=true})
    C.key(Key.ESCAPE,function() self:escape() end)
end
function M:init()
    local C=self.core
    RegisterLoadMapPreHook(function() C.run(C.id,function() self:reset(false) end) end)
    -- Runs on the game thread. A LoopAsync body ran Lua on another thread of
    -- this VM and lost a queued callback (`Ref was not function`).
    LoopInGameThreadWithDelay(100,function()
        C.run(C.id,function()
            if self.panel and not self.panel.building then
                if not self:live() then self:close() else self.view.refresh(self) end
            end
            self.icons.warm(self)
        end)
    end)
end
return M
