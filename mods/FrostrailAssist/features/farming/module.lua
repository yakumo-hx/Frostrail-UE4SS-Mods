local M={title="种植",registered={}}
local allowed={BlueBerries=true,RedBerries=true,GreenBerries=true,Fireberries=true,Dewgranate=true,Chimerelle=true,Mushroom=true}
function M:init()
    local C=self.core
    local planned,seen,originals={},{},{}
    for row,r in ipairs(self.cfg.recipes) do
        assert(allowed[r.item],"Unsupported crop: "..tostring(r.item))
        if seen[r.item] then
            C.log(C.id,"WARNING duplicate crop "..r.item.." at row "..row.." ignored; using first recipe")
        else
            seen[r.item]=true
            assert(type(r.input)=="number" and r.input>=1 and r.input%1==0
                and type(r.seconds)=="number" and r.seconds>0 and r.seconds<math.huge
                and type(r.output)=="number" and r.output>=1 and r.output%1==0,"Invalid crop recipe: "..r.item)
            local name="ISCH_"..r.item
            local item=LoadAsset("/Game/Frostrail/Data/Items/Resources/Nature/"..name.."."..name)
            assert(C.valid(item),"Missing crop "..name)
            local map=item.RefinementRules.RefinementConfig
            local key={TagName=FName("Crafting.Refinery.Recycler")}
            local baseline={refineable=item.bIsRefineable,recipes={}}
            map:ForEach(function(k,v)
                local rule=v:get()
                baseline.recipes[#baseline.recipes+1]={tag=k:get().TagName:ToString(),input=rule.ConsumedPerProcess,seconds=rule.Duration}
            end)
            originals[r.item]=baseline
            assert(not map:Contains(key),"Recipe conflict for "..r.item..": existing Recycler recipe retained")
            planned[#planned+1]={recipe=r,item=item,map=map,key=key}
        end
    end
    -- Every effective row is checked before any native asset is changed.
    self.originals=originals
    self.registered={}
    for _,p in ipairs(planned) do self.registered[#self.registered+1]=p.item end
    C.retain(self.id,self.registered)
    for _,p in ipairs(planned) do
        local r,item,map,key=p.recipe,p.item,p.map,p.key
        -- The pinned UE4SS build reliably fills a new map entry through its
        -- reflected fields; assigning a nested value table at Add loses fields.
        map:Add(key,{})
        local rule=map:Find(key):get()
        rule.ConsumedPerProcess=r.input
        rule.Duration=r.seconds
        rule.CatalystItem=nil
        rule.RefinementResults={{Item=item,Quantity=r.output}}
        -- Tier-0 sorting-table insertion and its green inventory hint require
        -- this flag before considering the item's native refinement recipes.
        item.bIsRefineable=true
        C.log(C.id,"Sorting-table recipe "..r.item.."="..rule.ConsumedPerProcess.."/"..rule.Duration.."/"..rule.RefinementResults[1].Quantity.." refineable=true original_recipes="..#originals[r.item].recipes)
    end
    C.config.save(self.dir.."/original-recipes.json",self.originals)
end
return M
