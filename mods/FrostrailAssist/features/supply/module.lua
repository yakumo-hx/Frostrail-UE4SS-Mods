local here=debug.getinfo(1,"S").source:sub(2):gsub("\\","/"):match("^(.*)/module.lua$")
local S=dofile(here.."/supply.lua")
local M={title="同列车供料"}
local composite="/Game/Frostrail/UI/Widgets/Composites/WBP_Composite_Crafting.WBP_Composite_Crafting_C"
local info_path="/Game/Frostrail/UI/Widgets/Crafting/Basic/WBP_Sub_CraftingInfo.WBP_Sub_CraftingInfo_C"
local inventory_ui="/Game/Frostrail/UI/Widgets/Composites/WBP_Composite_Inventory+Status.WBP_Composite_Inventory+Status_C"
local function identity(o) return {object=o,name=o:GetFullName()} end
local function current(C,e) return e and C.instance(e.object,e.name) end

function M:host(pc)
    local C=self.core
    if not C.valid(pc) or not pc:IsLocalController() or not pc:HasAuthority() then return false end
    local ps=pc.PlayerState
    return self.system:IsStandalone(pc) or C.valid(ps) and ps:IsServerHost()
end

function M:owned(s)
    local C=self.core
    return s and current(C,s.pc) and current(C,s.pawn) and current(C,s.component)
        and current(C,s.inventory) and current(C,s.world) and self:host(s.pc.object)
        and C.same(s.pc.object:GetBoundCharacterPawn(),s.pawn.object)
        and C.same(s.pawn.object:GetWorld(),s.world.object)
        and C.same(s.pawn.object.CraftingComponent,s.component.object)
        and C.same(s.pawn.object.ItemSystemComponent:GetInventory(),s.inventory.object)
end

function M:ordinary(component)
    local C,s=self.core,self.session
    if self.cfg and self.cfg.enabled==false then return nil end
    if not self:owned(s) or not C.same(component,s.component.object) then return nil end
    -- The native component also uses ModifyItemInstance for a NEW staged item.
    -- NonModular is the discriminator; a non-null staged item does not mean editing.
    if component:GetCraftingSessionState()~=2 then return nil end
    -- The first native inventory is also the output inventory. Never replace it.
    local first
    component.SessionInventories:ForEach(function(_,ref) first=ref:get(); return true end)
    if not C.same(first,s.inventory.object) then return nil end
    return S.costs(C,component)
end

function M:present(s)
    local C=self.core
    if not current(C,s.ui) then return false end
    local ui=s.ui.object
    if not ui:IsInViewport() and not C.valid(ui:GetParent()) then return false end
    local hud=s.pc.object:GetHUD()
    if not C.valid(hud) then return false end
    local found=false
    hud.WidgetStack:ForEach(function(_,ref)
        local root=ref:get()
        if C.valid(root) and (C.same(root,ui) or root:IsA(inventory_ui) and C.same(root.WBP_Composite_Crafting,ui))
            and (root:IsInViewport() or C.valid(root:GetParent())) then found=true; return true end
    end)
    return found
end

function M:adopt(ui)
    local C=self.core
    if self.cfg and self.cfg.enabled==false then return end
    if not C.valid(ui) or not self:host(ui:GetOwningPlayer()) then return end
    if self.session and current(C,self.session.ui) and C.same(self.session.ui.object,ui)
        and self:owned(self.session) then return self.session end
    local pc=ui:GetOwningPlayer()
    local pawn=pc:GetBoundCharacterPawn()
    if not C.valid(pawn) or not C.valid(ui.CraftingComponent) or not C.valid(ui.CraftingInventory) then return end
    local candidate={ui=identity(ui),info=identity(ui.WBP_Sub_CraftingInfo),pc=identity(pc),
        pawn=identity(pawn),world=identity(pc:GetWorld()),component=identity(ui.CraftingComponent),
        inventory=identity(ui.CraftingInventory),ledger={}}
    -- Removed native widgets can still receive the component's multicast events.
    -- They must not adopt (and cancel/refund) a newer visible crafting session.
    if not self:owned(candidate) or not self:present(candidate) then return end
    self:close()
    self.session=candidate
    return self.session
end

function M:refresh(info)
    local C=self.core
    if self.busy or not C.valid(info) then return end
    local s=self:adopt(info.CraftingUI)
    if not s or not self:owned(s) then return end
    local component=s.component.object
    local state=component:GetCraftingSessionState()
    if state~=2 and state~=4 then s.ordinary_progress=false; return end
    if state==4 and not s.ordinary_progress then return end
    local boxes=S.boxes(C,s.pc.object,s.inventory.object,false)
    local rows={}
    info.ResourceCostElements:ForEach(function(_,ref) rows[#rows+1]=ref:get() end)
    for _,row in ipairs(rows) do
        if C.valid(row) and C.valid(row.Resource) and row.Quantity>=0 then
            row.HeldQuantity=S.total(s.inventory.object,boxes,row.Resource)
            row:SetCraftingMultiplier(info.CraftingAmount)
            row.InBagText:SetText(FText(C.text("背包 + 列车","Backpack + train")))
        end
    end
    if state==2 then info:UpdateCraftingButtonState() end
end

function M:request(component)
    local C,s=self.core,self.session
    if self.busy then return end
    local costs=self:ordinary(component)
    if not costs then return end
    s.ordinary_progress=true
    self.busy=true
    local ok,err=xpcall(function()
        local boxes=S.boxes(C,s.pc.object,s.inventory.object,false)
        local first=#s.ledger+1
        local borrowed=S.borrow(C,s.inventory.object,boxes,costs,component:GetCraftingAmount(),s.ledger)
        if not borrowed then
            local attempt={}
            for i=first,#s.ledger do attempt[#attempt+1]=s.ledger[i] end
            for i=#s.ledger,first,-1 do s.ledger[i]=nil end
            S.refund(C,s.inventory.object,S.boxes(C,s.pc.object,s.inventory.object,true),attempt)
            C.message(C.text("材料不足或背包放不下，未开始列车供料制作。",
                "Not enough materials or backpack space to start crafting from train storage."))
        end
    end,debug.traceback)
    self.busy=false
    if not ok then error(err) end
end

function M:close(ui)
    local C,s=self.core,self.session
    if not s or self.busy or ui and (not current(C,s.ui) or not C.same(ui,s.ui.object)) then return end
    self.session=nil -- Notifications during cancellation/refund cannot reuse this ledger.
    if not self:owned(s) then return end
    self.busy=true
    local ok,err=xpcall(function()
        if s.component.object:GetCraftingSessionState()==4 then
            s.component.object:RequestCancelCraftingInProgress()
        end
        local returned,left=S.refund(C,s.inventory.object,S.boxes(C,s.pc.object,s.inventory.object,true),s.ledger)
        C.log(C.id,"Crafting closed; returned="..returned.." remaining in backpack="..left)
        if left>0 then C.message(C.text("列车箱子放不下，未退回的材料仍在背包里。",
            "Train storage cannot accept all leftovers; the remaining materials stay in your backpack.")) end
    end,debug.traceback)
    self.busy=false
    if not ok then error(err) end
end

function M:init()
    local C=self.core
    self.system=C.class("/Script/Engine.Default__KismetSystemLibrary")
    -- These classes are loaded at the main menu. Keep their UFunctions alive
    -- across map travel, otherwise UE4SS discards the registered script hooks.
    local composite_class=LoadAsset(composite)
    local info_class=LoadAsset(info_path)
    C.retain(self.id.."_classes",{composite_class,info_class})
    C.script_hook(composite..":InitializeCraftingUI",function(ctx)
        C.run(C.id,function() local ui=ctx:get(); self:adopt(ui); self:refresh(ui.WBP_Sub_CraftingInfo) end)
    end)
    for _,event in ipairs({"SetResources","OnCraftingAmountChanged","OnCraftingIterationCompleted","StateChanged"}) do
        C.script_hook(info_path..":"..event,function(ctx) C.run(C.id,function() self:refresh(ctx:get()) end) end)
    end
    C.hook("/Script/Frostrail.CraftingComponent:HasResourcesToCraft",nil,function(ctx)
        return C.run(C.id,function()
            if self.busy then return end
            local component=ctx:get()
            local costs=self:ordinary(component)
            if costs then
                local s=self.session
                return S.enough(s.inventory.object,S.boxes(C,s.pc.object,s.inventory.object,false),costs,component:GetCraftingAmount())
            end
        end)
    end)
    C.hook("/Script/Frostrail.CraftingViewModel:RequestCraft",function(ctx,pc)
        C.run(C.id,function()
            local s=self.session
            if s and self:owned(s) and C.same(pc:get(),s.pc.object)
                and C.same(ctx:get(),s.component.object:GetViewModel()) then self:request(s.component.object) end
        end)
    end)
    C.hook("/Script/Frostrail.CraftingViewModel:RequestExitCrafting",nil,function(_,pc)
        C.run(C.id,function()
            if self.session and C.same(pc:get(),self.session.pc.object) then self:close() end
        end)
    end)
    for _,event in ipairs({"ExternallyToggledOff","OnRemovedFromStack"}) do
        C.script_hook(composite..":"..event,function(ctx) C.run(C.id,function() self:close(ctx:get()) end) end)
    end
    -- A half-second refresh exists only while crafting is open. It catches native
    -- inventory mutations/attachments that bypass UFunction hooks, without Tick hooks.
    LoopInGameThreadWithDelay(500,function()
        if self.failed or not self.session then return end
        C.run(C.id,function()
            local s=self.session
            if not s then return end
            if not self:owned(s) or not self:present(s) or s.component.object:GetCraftingSessionState()==0 then self:close(); return end
            if current(C,s.info) then self:refresh(s.info.object) end
        end)
    end)
    RegisterLoadMapPreHook(function() C.run(C.id,function() self:close() end) end)
end

function M:player_left() self:close() end
function M:changed()
    -- Closing still uses the old ledger when new borrowing is switched off.
    local s=self.session
    if self.cfg.enabled==false then
        self:close()
    elseif not s then
        for _,ui in ipairs(FindAllOf("WBP_Composite_Crafting_C") or {}) do
            s=self:adopt(ui)
            if s then break end
        end
    end
    if self:owned(s) and current(self.core,s.info) then
        -- Rebuild native backpack counts/labels; our hook adds train totals
        -- again only while the feature is enabled.
        local costs={}
        s.info.object.ResourceCostElements:ForEach(function(_,ref)
            local row=ref:get()
            if self.core.valid(row) then costs[#costs+1]={Item=row.Resource,Quantity=row.Quantity} end
        end)
        s.info.object:SetResources(costs)
    end
end
return M
