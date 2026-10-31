local M={title="分拣台"}
function M:bind(refinery)
    local C=self.core
    local owner=refinery:GetOwner()
    if not C.valid(owner) or not owner:HasAuthority() then return end
    if refinery.RefineryTypeTag.TagName:ToString()~="Crafting.Refinery.Recycler" then return end
    local input,output=refinery.InputContainer,refinery.OutputContainer
    if not C.valid(input) or not C.valid(output) then return end
    for _,pair in ipairs({{input,self.input_slots},{output,self.output_slots}}) do
        local container,size=pair[1],pair[2]
        container.ContainerInventorySize=size
        if container.bRuntimeVariableInventorySize then container.VariableInventorySize=size end
        local inv=container:GetInventory()
        if C.valid(inv) then
            -- Never hide an existing out-of-range item when opening an older save.
            local required=size
            for slot in pairs(C.snapshot(inv)) do required=math.max(required,slot+1) end
            inv.InventoryRecord.InventorySize=required
            local vm=inv:GetViewModel()
            if C.valid(vm) then vm.InventorySize=inv.InventoryRecord.InventorySize end
        end
    end
    refinery.MaxParallelRefineProcesses=1
    C.log(self.id,"Bound "..refinery:GetFullName().." input="..input.ContainerInventorySize.." output="..output.ContainerInventorySize.." parallel=1")
end
function M:init()
    assert(self.cfg.input_slots>=1 and self.cfg.input_slots%1==0 and self.cfg.output_slots>=1 and self.cfg.output_slots%1==0,"Invalid inventory capacity")
    self.input_slots,self.output_slots=self.cfg.input_slots,self.cfg.output_slots
    for _,ref in ipairs(FindAllOf("RefineryComponent") or {}) do self:bind(ref) end
    self.core.hook("/Script/Frostrail.RefineryComponent:OnInputInventoryChanged",function(ctx) self:bind(ctx:get()) end)
    self.core.log(self.id,"Native sequential processor hooks registered; awaiting recycler instance")
end
function M:actor_ready(actor)
    if actor:GetClass():GetFName():ToString():find("Recycler") then
        local refs=actor:K2_GetComponentsByClass(self.core.class("/Script/Frostrail.RefineryComponent"))
        for _,r in ipairs(refs) do self:bind(r:get()) end
    end
end
return M
