local M={title="自动保存"}

function M:host(pc)
    local C=self.core
    if not C.valid(pc) or not pc:IsA("/Script/Frostrail.FrostrailPlayerControllerBase")
        or not pc:IsLocalController() or not pc:HasAuthority() then return false end
    local ps=pc.PlayerState
    return C.valid(ps) and ps:IsA("/Script/Frostrail.FrostrailPlayerState") and ps:IsServerHost()
end

function M:controller()
    -- Do not use UEHelpers: it can return the MultiWorld_Item preview controller.
    for _,pc in ipairs(FindAllOf("BP_FrostrailPlayerController_C") or {}) do
        if self:host(pc) then return pc end
    end
end

function M:reset()
    self.elapsed=0
    self.last_time=nil
    self.world_name=nil
end

function M:ready(pc)
    local C=self.core
    local pawn=pc:GetBoundCharacterPawn()
    if not C.valid(pawn) or not pawn.bIsAlive or not pawn.bHasInitializedInitialItems then return false end
    local items=pawn.ItemSystemComponent
    if not C.valid(items) then return false end
    local inventory=items:GetInventory()
    return C.valid(inventory) and inventory:GetInventorySize()>0
end

function M:message(pc,text,is_error)
    local C=self.core
    C.message(text)
    -- The synchronous writer blocks rendering. Only show its result on screen;
    -- otherwise a stale "Saving" row would remain below "Saved" for 4 seconds.
    if is_error==nil then return end
    -- PrintString is not visible in this shipping build. Use the HUD's own
    -- message widget, resolved for this controller each time; retain no widget.
    local hud=pc:GetHUD()
    if not C.valid(hud) then return end
    local main=hud:GetMainWidget()
    if not C.valid(main) then return end
    local messages=main.WBP_Sub_HUD_Message
    if C.valid(messages) then messages:DisplayMessage(is_error==true,FText(text),4) end
end

function M:save(pc,reason)
    local C=self.core
    if self.saving or not self:host(pc) then return false end
    -- Real death-state reload lost the transitional inventory (death-119.sav).
    -- Wait for native respawn/restore instead of writing that incomplete state.
    if not self:ready(pc) then
        if reason~="timer" then
            self:message(pc,C.text("角色尚未重生，无法保存；继续退出","Cannot save before respawn; continuing to leave"),true)
            C.log(self.id,"save reason="..reason.." success=false detail=waiting for restored living character")
        elseif self.status~="waiting_for_respawn" then
            C.log(self.id,"Timer save deferred until the living character and inventory are restored")
        end
        self.status="waiting_for_respawn"
        return false
    end
    self.saving=true
    self.status="saving"
    self:message(pc,C.text("正在保存…","Saving…"))
    local called,ok,detail,slot,writes=pcall(self.native,pc:GetAddress())
    self.saving=false
    if not called then detail=ok; ok=false end
    ok=ok==true
    self.status=ok and "saved" or "failed"
    self.elapsed=0
    self.last_time=self.gameplay:GetTimeSeconds(pc)
    C.log(self.id,"save reason="..reason.." success="..tostring(ok).." writes="..tostring(writes)
        .." slot="..tostring(slot).." detail="..tostring(detail))
    self:message(pc,ok and C.text("已保存","Saved") or C.text("保存失败","Save failed"),not ok)
    return ok
end

function M:tick()
    if self.leaving or not self.cfg.autosave then self.last_time=nil; return end
    local C=self.core
    local pc=self:controller()
    if not pc then self.last_time=nil; return end
    local world=pc:GetWorld()
    if not C.valid(world) then self.last_time=nil; return end
    local name=world:GetFullName()
    if self.world_name~=name then self:reset(); self.world_name=name end
    -- Native game time stops when paused. Loading/menu/lobby have no eligible PC.
    local now=self.gameplay:GetTimeSeconds(pc)
    if self.last_time and now>=self.last_time then self.elapsed=self.elapsed+now-self.last_time end
    self.last_time=now
    local minutes=tonumber(self.cfg.interval_minutes)
    if not minutes or minutes<=0 then return end
    if self.elapsed>=minutes*60 then self:save(pc,"timer") end
end

function M:leave(pc,kind)
    if (kind~=1 and kind~=2) or self.leaving or not self:host(pc) then return end
    self.leaving=true
    if self.cfg.save_on_exit then self:save(pc,kind==1 and "exit_menu" or "exit_game") end
    -- The native writer completes synchronously. Return to the original leave
    -- call exactly once, including when saving fails; do not reissue the request.
end

function M:init()
    local C=self.core
    self.gameplay=C.class("/Script/Engine.Default__GameplayStatics")
    self:reset()
    C.hook("/Script/Frostrail.FrostrailPlayerControllerBase:RequestGracefulLeaveGame",function(ctx,kind)
        C.run(self.id,function() self:leave(ctx:get(),kind:get()) end)
    end)
    RegisterLoadMapPreHook(function()
        self:reset()
        self.leaving=false
    end)
    local queued=false
    LoopAsync(1000,function()
        if queued then return end
        queued=true
        ExecuteInGameThread(function()
            C.run(self.id,function() self:tick() end)
            queued=false
        end)
    end)
end

function M:changed()
    -- Only timer-related settings restart its interval.
    if self.timer_enabled~=self.cfg.autosave or self.timer_minutes~=self.cfg.interval_minutes then
        self:reset()
    end
    self.timer_enabled,self.timer_minutes=self.cfg.autosave,self.cfg.interval_minutes
end

function M:setup() self:changed() end

return M
