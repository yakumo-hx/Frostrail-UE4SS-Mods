local here=debug.getinfo(1,"S").source:sub(2):gsub("\\","/"):match("^(.*)/module.lua$")
local logic=dofile(here.."/logic.lua")
local M={title="快存与格子锁",pending={}}
function M:setup()
    self.core.action("Quickstash","附近箱子快存",nil,function() self:stash() end)
    self.core.action("ToggleSlotLock","切换悬停格子锁",nil,function() self:toggle_hovered() end)
end
function M:changed()
    self.locks=logic.locked(self.cfg.locked_slots)
    for _,w in ipairs(FindAllOf("WBP_Element_ItemSlot_C") or {}) do self:decorate(w) end
end
function M:init()
    local C=self.core
    C.retain(self.id.."_icons",{})
    local renderer=StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    self.icons={}
    for _,state in ipairs({"locked","unlocked"}) do
        self.icons[state]=renderer:ImportFileAsTexture2D(C.assets,self.dir.."/icons/"..state..".png")
        assert(C.valid(self.icons[state]),"Missing lock icon: "..state)
    end
    C.retain(self.id.."_icons",{self.icons.locked,self.icons.unlocked})
    self:changed()
    LoadAsset("/Game/Frostrail/UI/Widgets/Inventory/WBP_Sub_InventorySlots.WBP_Sub_InventorySlots_C")
    -- Refresh after the native grid finishes assigning slots and their flags.
    for _,event in ipairs({"CreateSlots","PopulateSlots"}) do
        C.script_hook("/Game/Frostrail/UI/Widgets/Inventory/WBP_Sub_InventorySlots.WBP_Sub_InventorySlots_C:"..event,function(ctx)
            self:decorate_grid(ctx:get())
        end)
    end
    C.hook("/Script/Frostrail.ReplicationRequestComponent:RequestInventorySorting",function(ctx,kind,descending,target)
        local inv=target:get()
        if not C.pawn_valid() or not C.pawn:HasAuthority() or not C.same(inv,C.pawn.ItemSystemComponent:GetInventory()) or kind:get()==0 then return end
        self:merge_stacks(inv)
        local before=C.snapshot(inv)
        local has_locked=false
        for slot in pairs(before) do if self.locks[slot] then has_locked=true end end
        if not has_locked then return end
        local scratch=C.new("/Script/Frostrail.Inventory",C.player)
        scratch.InventoryRecord.InventorySize=inv:GetInventorySize()
        scratch.QuickSlotNum=0
        local next_slot=0
        for slot=inv:GetQuickSlotNum(),inv:GetInventorySize()-1 do
            if before[slot] and not self.locks[slot] then
                scratch.InventoryRecord.ContainableTable:Add({ID=next_slot},before[slot]); next_slot=next_slot+1
            end
        end
        self.pending[scratch:GetAddress()]={inv=inv,before=before,kind=kind:get()}
        target:set(scratch)
    end,function(ctx,kind,descending,target)
        local scratch=target:get()
        local transaction=self.pending[scratch:GetAddress()]
        if not transaction then return end
        self.pending[scratch:GetAddress()]=nil
        local inv=transaction.inv
        local sorted,by_slot={},C.snapshot(scratch)
        for slot=0,scratch:GetPopulatedSlotCount()-1 do sorted[#sorted+1]=by_slot[slot] end
        local result=logic.sort_layout(transaction.before,sorted,self.locks,inv:GetQuickSlotNum(),inv:GetInventorySize())
        local map=inv.InventoryRecord.ContainableTable
        map:Empty()
        local last_slot,last_item
        for slot,item in pairs(result) do map:Add({ID=slot},item); last_slot,last_item=slot,item end
        -- A single native insertion publishes the completed table to the native
        -- view model and replication state. It cannot stack: its slot is empty.
        if last_item then
            map:Remove({ID=last_slot})
            assert(inv:AssignContainableToSlot({ID=last_slot},last_item),"Native inventory refresh insertion failed")
        end
        inv.SortingType=transaction.kind
        local vm=inv:GetViewModel()
        if C.valid(vm) then
            vm.ActiveSortingType=transaction.kind
            vm:K2_BroadcastFieldValueChanged({FieldName=FName("ActiveSortingType")})
        end
        C.log(self.id,"Native sorting completed with occupied locked slots preserved")
    end)
    C.log(self.id,"Sorting collection/writeback hook registered; locks="..table.concat(self.cfg.locked_slots,","))
end
function M:merge_stacks(inv)
    local C=self.core
    local quick,size=inv:GetQuickSlotNum(),inv:GetInventorySize()
    -- Fixed stacks may receive items, but never donate. Let the native item
    -- compatibility and transfer code decide whether a pair can be combined.
    local targets={}
    for slot=0,size-1 do if slot<quick or self.locks[slot] then targets[#targets+1]=slot end end
    for slot=quick,size-1 do if not self.locks[slot] then targets[#targets+1]=slot end end
    for source=quick,size-1 do
        if not self.locks[source] then
            for _,target in ipairs(targets) do
                local item=inv:GetContainableInSlot({ID=source})
                if not C.valid(item) then break end
                if target~=source and (target<quick or self.locks[target] or target<source) then
                    local other=inv:GetContainableInSlot({ID=target})
                    if C.valid(other) and other:CanStackInInventoryWith(item,false) then
                        local amount=math.min(item:GetInventoryStackNum(),other:GetMaxInventoryStackNum()-other:GetInventoryStackNum())
                        if amount>0 then inv:TransferContainable({ID=source},inv,{ID=target},amount,false,false) end
                    end
                end
            end
        end
    end
end
function M:stash()
    local C=self.core
    if not C.pawn_valid() or not C.pawn:HasAuthority() then C.message("快存首版仅支持单人主机"); return end
    local source=C.pawn.ItemSystemComponent:GetInventory()
    local boxes={}
    for _,container in ipairs(FindAllOf("ContainerComponent") or {}) do
        local owner=container:GetOwner()
        if C.valid(owner) and owner:IsA("/Game/Frostrail/Blueprints/Interactables/Containers/TrainContainers/BP_TrainContainer_Base.BP_TrainContainer_Base_C") then
            local inv=container:GetInventory()
            local distance=owner:GetDistanceTo(C.pawn)
            if C.valid(inv) and not C.same(inv,source) and container.bCanEverAddItems and distance<=self.cfg.range_m*100 then
                boxes[#boxes+1]={inventory=inv,distance=distance}
            end
        end
    end
    table.sort(boxes,function(a,b) return a.distance<b.distance end)
    local moved=0
    for slot=0,source:GetInventorySize()-1 do
        if not self.locks[slot] then
            for _,box in ipairs(boxes) do
                local item=source:GetContainableInSlot({ID=slot})
                if not C.valid(item) then break end
                local has_type=not self.cfg.existing_items_only
                for _,other in pairs(C.snapshot(box.inventory)) do if C.same(other:GetSchematic(),item:GetSchematic()) then has_type=true; break end end
                if has_type then
                    local before=item:GetInventoryStackNum()
                    -- The game's native transfer picks compatible partial stacks
                    -- and then a free slot, respecting target insertion rules.
                    C.pawn.ItemSystemComponent:Server_RequestTransferContainableToFreeSlot(source,{ID=slot},box.inventory,before)
                    local remaining=source:GetContainableInSlot({ID=slot})
                    moved=moved+before-(C.valid(remaining) and remaining:GetInventoryStackNum() or 0)
                end
            end
        end
    end
    C.message("快存完成："..moved.." 个物品，附近 "..#boxes.." 个玩家储物箱")
    C.log(self.id,"Quickstash moved="..moved.." containers="..#boxes)
end
function M:toggle_hovered()
    local C=self.core
    for _,w in ipairs(FindAllOf("WBP_Element_ItemSlot_C") or {}) do
        if w:IsHovered() and w.bIsPlayerInventory then
            self:toggle_slot(w.SlotId.ID)
            return
        end
    end
end
function M:toggle_slot(slot)
    self.locks[slot]=not self.locks[slot] or nil
    self.cfg.locked_slots={}
    for id in pairs(self.locks) do self.cfg.locked_slots[#self.cfg.locked_slots+1]=id+1 end
    table.sort(self.cfg.locked_slots)
    self.core.config.save(self.dir.."/config.json",self.cfg)
    self:changed()
    self.core.log(self.id,"Inventory slot "..(slot+1)..(self.locks[slot] and " locked" or " unlocked"))
end
function M:decorate_grid(grid)
    local C=self.core
    if not C.valid(grid) then return end
    -- Creating UMG widgets can rebuild/clear the native grid. Do not retain
    -- a TArray iterator across those calls; take references before decorating.
    local slots={}
    grid.Slots:ForEach(function(_,p) slots[#slots+1]=p:get() end)
    for id,entry in pairs(self.labels or {}) do if not C.ui.owned(C,entry,entry.owner) then self.labels[id]=nil end end
    for _,w in ipairs(slots) do self:decorate(w) end
    if not C.valid(grid) or not C.pawn_valid() or not C.same(grid.Inventory,C.pawn.ItemSystemComponent:GetInventory()) then return end
    self.grids=self.grids or {}
    local id=grid:GetAddress()
    local entry=self.grids[id]
    if C.ui.owned(C,entry,grid) then return end
    for key,value in pairs(self.grids) do if not C.ui.owned(C,value,value.owner) then self.grids[key]=nil end end
    entry=C.ui.button(C,grid,"快存",function() self:stash() end,12)
    entry.owner=grid
    entry.button:SetToolTipText(FText("将未锁定物品存入附近玩家储物箱"))
    local slot=grid.SortingControlsHolder:AddChildToHorizontalBox(entry.widget)
    slot:SetPadding({Left=6,Top=0,Right=0,Bottom=0}); slot:SetVerticalAlignment(2)
    self.grids[id]=entry
    C.log(self.id,"Quickstash button attached at the right of native inventory sorting controls")
end
function M:decorate(w)
    local C=self.core
    if not C.valid(w) or not w.bIsPlayerInventory or not C.valid(w.Content) then return end
    local parent=w.Content:GetParent()
    if not C.valid(parent) then return end
    self.labels=self.labels or {}
    local id=w:GetAddress()
    local entry=self.labels[id]
    if not C.ui.owned(C,entry,w) then
        entry=C.ui.icon_button(C,w,function()
            if C.valid(w) then self:toggle_slot(w.SlotId.ID) end
        end)
        entry.owner=w
        -- Keep the rest of the native cell available for drag/drop and use.
        local slot=parent:AddChildToOverlay(entry.widget)
        slot:SetHorizontalAlignment(1); slot:SetVerticalAlignment(3)
        slot:SetPadding({Left=2,Top=0,Right=0,Bottom=2})
        self.labels[id]=entry
    end
    local locked=self.locks[w.SlotId.ID]
    entry.image:SetBrushFromTexture(locked and self.icons.locked or self.icons.unlocked,false)
    entry.image:SetColorAndOpacity(locked and {R=1,G=0.8,B=0.2,A=1} or {R=0.7,G=0.75,B=0.8,A=0.65})
    entry.button:SetToolTipText(FText(locked and "点击解锁：允许向外快存和整理" or "点击锁定：保留整理位置，禁止向外快存"))
end
return M
