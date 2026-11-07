local here=debug.getinfo(1,"S").source:sub(2):gsub("\\","/"):match("^(.*)/module.lua$")
local train=dofile(here.."/../supply/supply.lua")
local M={title="回列车"}

function M:message(text,is_error)
    local C=self.core
    C.message(text)
    -- PrintString is hidden in Shipping; use the existing HUD message area.
    if not C.player_valid() then return end
    local hud=C.player:GetHUD()
    local main=C.valid(hud) and hud:GetMainWidget() or nil
    local messages=C.valid(main) and main.WBP_Sub_HUD_Message or nil
    if C.valid(messages) then messages:DisplayMessage(is_error==true,FText(text),4) end
end

function M:destination(pc)
    local C=self.core
    local world=train.world(C,pc)
    local subsystems=C.class("/Script/Engine.Default__SubsystemBlueprintLibrary")
    local environment=subsystems:GetWorldSubsystem(pc,C.class("/Script/EnvironmentSystem.EnvironmentSubsystem"))
    local engine=C.valid(environment) and environment:GetEdenEngineActor() or nil
    local head=C.valid(engine) and C.same(train.world(C,engine),world) and train.head(C,engine) or nil
    if not head then
        for _,spawner in ipairs(FindAllOf("TrainSpawner") or {}) do
            if C.valid(spawner) and C.same(train.world(C,spawner),world) then
                head=train.head(C,spawner.FrontmostUnitUponSpawn)
                if head then break end
            end
        end
    end
    local points={}
    if head then
        for _,point in ipairs(FindAllOf("FRPlayerStart") or {}) do
            if C.valid(point) and C.same(train.world(C,point),world) and C.same(train.head(C,point),head) then
                points[#points+1]=point
            end
        end
    end
    -- Stable ordering; transforms and collision are still read at each attempt.
    table.sort(points,function(a,b) return a:GetFullName()<b:GetFullName() end)
    return points
end

function M:teleport()
    local C=self.core
    if not self.cfg.enabled then return false end
    if not C.pawn_valid() then return false end
    local pc,pawn=C.player,C.pawn
    if not pc:IsLocalController() or not pc:HasAuthority() or not pawn:HasAuthority() then
        self:message(C.text("回列车目前仅房主可用。","Return to train is currently host-only."),true);return false
    end
    if not C.same(pc:GetBoundCharacterPawn(),pawn) or not pawn.bIsAlive then return false end
    local inside=pawn:IsInsideAnyDungeon()
    local points=self:destination(pc)
    if #points==0 then
        self:message(C.text("当前列车出生点尚未加载，请稍后重试。","The current train spawn points are not loaded. Try again shortly."),true);return false
    end
    for _,point in ipairs(points) do
        local rotation=point:K2_GetActorRotation()
        if pawn:K2_TeleportTo(point:K2_GetActorLocation(),rotation) then
            pawn.CharacterMovement:StopMovementImmediately()
            pc:SetControlRotation(rotation)
            if inside then
                -- Same loose-tag decrement and replicated-tag removal as the
                -- native dungeon exit. InsideDungeonTags is the tag definition,
                -- not mutable occupancy data: never clear that container.
                local abilities=C.class("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
                assert(abilities:RemoveLooseGameplayTags(pawn,pawn.InsideDungeonTags,true),"Could not clear dungeon status")
            end
            self:message(C.text("已回到列车出生点。","Returned to the train spawn point."))
            return true
        end
    end
    self:message(C.text("列车出生点被占用，暂时无法传送。","The train spawn points are obstructed. Cannot teleport now."),true)
    return false
end

function M:setup()
    self.core.action("ReturnToTrain",{zh="回列车",en="Return to train"},"O",function() self:teleport() end)
    RegisterConsoleCommandGlobalHandler("frostrail.assist.return_to_train",function()
        ExecuteInGameThread(function() self.core.run(self.core.id,function() self:teleport() end) end)
        return true
    end)
    self:changed()
end
function M:changed() ModRef:SetSharedVariable("FrostrailAssist.return_to_train.enabled",self.cfg.enabled==true) end
return M
