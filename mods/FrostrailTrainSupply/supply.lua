-- Native inventory operations only. No synthetic inventory, item creation or consumption.
local S={}
local box_class="/Game/Frostrail/Blueprints/Interactables/Containers/TrainContainers/BP_TrainContainer_Base.BP_TrainContainer_Base_C"
local train_class="/Script/TrainSystem.TrainUnitBase"

function S.world(C,actor)
    -- UE4SS GetWorld follows outers and returns a streamed carriage's asset world.
    -- Native research compares the actual world owning its loaded level instead.
    local level=actor:GetLevel()
    return C.valid(level) and level.OwningWorld or nil
end

function S.head(C,actor)
    local seen={}
    while C.valid(actor) do
        local id=actor:GetAddress()
        if seen[id] then return nil end
        seen[id]=true
        if actor:IsA(train_class) then
            local front=actor.FrontAttachedUnit
            if not C.valid(front) then return actor end
            actor=front
        else
            actor=actor:GetAttachParentActor()
        end
    end
end

function S.train(C,pc)
    local world=S.world(C,pc)
    for _,spawner in ipairs(FindAllOf("TrainSpawner") or {}) do
        if C.valid(spawner) and C.same(S.world(C,spawner),world) then
            local head=S.head(C,spawner.FrontmostUnitUponSpawn)
            if head then return head end
        end
    end
    -- The native research path also chooses the closest train when the spawner
    -- reference is absent. Distance chooses a train here; it never filters boxes.
    local pawn=pc:GetBoundCharacterPawn()
    local nearest,distance
    if C.valid(pawn) then
        for _,unit in ipairs(FindAllOf("TrainUnitBase") or {}) do
            if C.valid(unit) and C.same(S.world(C,unit),world) then
                local d=unit:GetDistanceTo(pawn)
                if not distance or d<distance then nearest,distance=unit,d end
            end
        end
    end
    return nearest and S.head(C,nearest)
end

function S.boxes(C,pc,backpack,returning)
    local result,seen={},{}
    local head=S.train(C,pc)
    if not head then return result end
    local world=S.world(C,pc)
    seen[backpack:GetAddress()]=true
    for _,container in ipairs(FindAllOf("ContainerComponent") or {}) do
        if C.valid(container) then
            local owner=container:GetOwner()
            if C.valid(owner) and C.same(S.world(C,owner),world) and owner:IsA(box_class) and C.same(S.head(C,owner),head) then
                local inv=container:GetInventory()
                if C.valid(inv) and not seen[inv:GetAddress()]
                    and (returning and container.bCanEverAddItems and inv:GetCanEverAddItems()
                        or not returning and container.bCanEverRemoveItems and inv:GetCanEverRemoveItems()) then
                    seen[inv:GetAddress()]=true
                    result[#result+1]=inv
                end
            end
        end
    end
    return result
end

function S.costs(C,component)
    local result,by_id={},{}
    -- Returned struct arrays are Lua tables of reflected values in pinned UE4SS;
    -- unlike a UObject TArray property they do not expose ForEach.
    local info=component:GetCurrentTotalResourceCost()
    for _,ref in ipairs(info.Resources) do
        local cost=ref:get()
        if cost.Quantity<0 or not C.valid(cost.Item) then return nil end
        if cost.Quantity>0 then
            local id=cost.Item:GetAddress()
            local entry=by_id[id]
            if not entry then
                entry={item=cost.Item,quantity=0}; by_id[id]=entry; result[#result+1]=entry
            end
            entry.quantity=entry.quantity+cost.Quantity
        end
    end
    return result
end

function S.count(inv,item) return inv:CalculateTotalItemAmountByType(item) end
function S.total(backpack,boxes,item)
    local total=S.count(backpack,item)
    for _,inv in ipairs(boxes) do total=total+S.count(inv,item) end
    return total
end
function S.enough(backpack,boxes,costs,amount)
    for _,cost in ipairs(costs) do
        if S.total(backpack,boxes,cost.item)<cost.quantity*amount then return false end
    end
    return true
end

function S.transfer(C,source,target,schematic,amount)
    local moved=0
    -- Re-read slots after every mutation: a condensed source can shift its slots.
    local slot=0
    while moved<amount and slot<source:GetInventorySize() do
        local item=source:GetContainableInSlot({ID=slot})
        if C.valid(item) and C.same(item:GetSchematic(),schematic) then
            local dest=target:FindFirstStackableSlot(item,true)
            if dest.ID<0 then dest=target:GetFreeSlot(item) end
            if dest.ID<0 then break end
            local other=target:GetContainableInSlot(dest)
            local room=C.valid(other) and other:GetMaxInventoryStackNum()-other:GetInventoryStackNum()
                or item:GetMaxInventoryStackNum()
            local take=math.min(amount-moved,item:GetInventoryStackNum(),room)
            if take<=0 then break end
            local before=S.count(target,schematic)
            -- TransferContainable is called on the TARGET, with an explicit source.
            target:TransferContainable({ID=slot},source,dest,take,false,false)
            local actual=S.count(target,schematic)-before
            if actual<=0 then slot=slot+1 else moved=moved+actual end
        else slot=slot+1 end
    end
    return moved
end

function S.borrow(C,backpack,boxes,costs,amount,ledger)
    if not S.enough(backpack,boxes,costs,amount) then return false end
    for _,cost in ipairs(costs) do
        local before=S.count(backpack,cost.item)
        local missing=math.max(0,cost.quantity*amount-before)
        if missing>0 then
            local entry={item=cost.item,name=cost.item:GetFullName(),before=before,moved=0}
            -- Record before the native call: inventory notifications can reenter Lua.
            ledger[#ledger+1]=entry
            for _,inv in ipairs(boxes) do
                entry.moved=entry.moved+S.transfer(C,inv,backpack,cost.item,missing-entry.moved)
                if entry.moved>=missing then break end
            end
            if entry.moved<missing then return false end
        end
    end
    return true
end

function S.refund(C,backpack,boxes,ledger)
    local returned,left=0,0
    -- Several crafts can borrow the same material in one open panel. Unwind each
    -- recorded baseline in reverse order, so a later borrow cannot revive an old one.
    for i=#ledger,1,-1 do
        local entry=ledger[i]
        if C.instance(entry.item,entry.name) then
            local amount=math.min(entry.moved,math.max(0,S.count(backpack,entry.item)-entry.before))
            local targets={}
            for _,inv in ipairs(boxes) do if S.count(inv,entry.item)>0 then targets[#targets+1]=inv end end
            for _,inv in ipairs(boxes) do if S.count(inv,entry.item)==0 then targets[#targets+1]=inv end end
            local moved=0
            for _,inv in ipairs(targets) do
                moved=moved+S.transfer(C,backpack,inv,entry.item,amount-moved)
                if moved>=amount then break end
            end
            returned=returned+moved
            left=left+amount-moved
        end
        ledger[i]=nil
    end
    return returned,left
end
return S
