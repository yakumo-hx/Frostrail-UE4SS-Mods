local M={title="圣物"}
local duration="GameplayEffect.Magnitude.Duration"

function M:begin(asc,inventory)
    local frame={}
    self.calls[#self.calls+1]=frame
    local C=self.core
    if self.failed or not C.valid(asc) or not C.valid(inventory)
        or not asc:GetOwner():HasAuthority() then return end
    -- The shrine owns the items and their states. Keep map references only
    -- across this synchronous native call, never across ticks or world changes.
    local seconds=self.cfg.minutes*60
    for slot=0,inventory:GetInventorySize()-1 do
        local item=inventory:GetContainableInSlot({ID=slot})
        if C.valid(item) then
            local state=item:GetItemState()
            if C.valid(state) and state:IsA("/Script/Frostrail.RelicItemState") then
                state.RelicEffects:ForEach(function(_,ref)
                    local map=ref:get().CallerMagnitudes
                    map:ForEach(function(key,value)
                        if key:get().TagName:ToString()==duration then
                            frame[#frame+1]={map=map,original=value:get()}
                        end
                    end)
                end)
            end
        end
    end
    for _,entry in ipairs(frame) do entry.map:Add({TagName=FName(duration)},seconds) end
end

function M:finish()
    local frame=table.remove(self.calls)
    if not frame then return end
    for _,entry in ipairs(frame) do entry.map:Add({TagName=FName(duration)},entry.original) end
end

function M:init()
    self.calls={}
    local C=self.core
    -- Both thunks synchronously apply the Spec before returning. Request is
    -- also called on clients; only the authoritative copy may touch the item.
    for _,name in ipairs({"RequestApplyRelicEffects","Server_RequestApplyRelicEffects"}) do
        C.hook("/Script/Frostrail.FRAbilitySystemComponent:"..name,function(ctx,inventory)
            local ok,err=xpcall(function() self:begin(ctx:get(),inventory:get()) end,debug.traceback)
            if not ok then
                -- Roll back even a partially prepared call before native code runs.
                self:finish();self.calls[#self.calls+1]={}
                C.log(C.id,"ERROR relic: "..tostring(err))
            end
        end,function() self:finish() end)
    end
end
return M
