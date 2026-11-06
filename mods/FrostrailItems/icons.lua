-- Native food slots render the borrowed pickup and bypass OverrideIcon.
-- Read the current hunger binding and change only these three food textures.
return function(C,catalog)
    local I={known={}}
    for _,spec in ipairs(catalog.items) do
        if spec.kind=="food" then
            local name="ISCH_FRI_"..spec.id
            I.known["ItemSchematic /Game/FrostrailMods/FrostrailItems/"..name.."."..name]=true
        end
    end
    function I:refresh()
        if not C.pawn_valid() then return end
        local hunger=C.pawn.HungerComponent
        local model=hunger.ViewModel
        if not C.valid(model) then return end
        local slots={}
        for index=1,hunger:GetFoodSlotCount() do
            local prefix="FoodSlot_"..index.."_"
            local item,view=model[prefix.."FoodSchematic"],model[prefix.."IconViewModel"]
            if C.valid(item) and self.known[item:GetFullName()] and C.valid(view) and C.valid(item.OverrideIcon) then
                slots[#slots+1]={view=view,icon=item.OverrideIcon}
            end
        end
        if #slots==0 then return end
        -- Widgets own their materials/view models; rooted schematics own icons.
        -- Everything is looked up within this operation. No UI object is cached.
        for _,class in ipairs({"WBP_Element_FoodSlot_C","WBP_Element_FoodSlotMenu_C"}) do
            for _,widget in ipairs(FindAllOf(class) or {}) do
                if C.valid(widget) and C.same(widget:GetOwningPlayer(),C.player) and C.valid(widget.IconMaterial) then
                    for _,slot in ipairs(slots) do
                        if C.same(widget.ItemIconViewModel,slot.view) then
                            widget.IconMaterial:SetTextureParameterValue(FName("ItemIcon"),slot.icon)
                            break
                        end
                    end
                end
            end
        end
    end
    return I
end
