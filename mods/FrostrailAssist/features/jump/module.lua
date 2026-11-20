local M={title="二段跳"}

function M:restore()
    local entry=self.applied
    if entry and self.core.instance(entry.pawn,entry.name) then
        entry.pawn.JumpMaxCount=entry.original
    end
    self.applied=nil
end

function M:apply()
    local C=self.core
    if not self.cfg.enabled then self:restore();return end
    if not C.pawn_valid() then return end
    local pawn=C.pawn
    local entry=self.applied
    if not entry or not C.instance(entry.pawn,entry.name) or not C.same(entry.pawn,pawn) then
        self:restore()
        -- The game owns the pawn. Keep its identity and original limit only
        -- until unbind; never retain it or reset its in-air count on reconfigure.
        self.applied={pawn=pawn,name=pawn:GetFullName(),original=pawn.JumpMaxCount}
    end
    pawn.JumpMaxCount=2
end

local jumpAbility="Ability_Player_Jump_C"

local function jumpHandle(abilities)
    local handle
    abilities.ActivatableAbilities.Items:ForEach(function(_,ref)
        local spec=ref:get()
        if spec.Ability:IsValid() and spec.Ability:GetClass():GetFName():ToString()==jumpAbility then
            handle=spec.Handle.Handle
            return true
        end
    end)
    return handle
end

-- The local jump ability accepts the press before either side calls launch.
-- DoJump needs a walkable floor, so supply the second impulse on both copies.
local function launch(pawn)
    local move=pawn.CharacterMovement
    local speed=math.max(move.JumpZVelocity,pawn:GetVelocity().Z)
    pawn:StopJumping()
    pawn.JumpCurrentCount=2
    pawn:LaunchCharacter({X=0,Y=0,Z=speed},false,true)
end

function M:air_jump(pawn)
    local C=self.core
    if not self.cfg.enabled or not C.pawn_valid() or not C.same(pawn,C.pawn) then return end
    if not pawn.CharacterMovement:IsFalling() or not pawn:CanJump() then return end
    launch(pawn)
    if not pawn:HasAuthority() then
        local abilities=pawn.AbilitySystemComponent
        local handle=jumpHandle(abilities)
        if handle then
            abilities:ServerSetInputPressed({Handle=handle})
            abilities:ServerSetInputReleased({Handle=handle})
        end
    end
end

function M:remote_press(abilities,handle)
    if not self.cfg.enabled then return end
    local C=self.core
    local pawn=abilities:GetOwner()
    if not C.valid(pawn) or not pawn:HasAuthority() or not pawn:IsA("/Script/Frostrail.PlayerCharacter")
        or not pawn.bIsAlive or pawn:IsLocallyControlled() or not pawn.CharacterMovement:IsFalling()
        or pawn.JumpCurrentCount>=2 or jumpHandle(abilities)~=handle then return end
    local limit=pawn.JumpMaxCount
    pawn.JumpMaxCount=2
    local can=pawn:CanJump()
    pawn.JumpMaxCount=limit
    if can then launch(pawn) end
end

function M:init()
    local C=self.core
    C.hook("/Script/GameplayAbilities.AbilitySystemComponent:ServerSetInputPressed",function(ctx,handle)
        if not self.failed then C.run(C.id,function() self:remote_press(ctx:get(),handle:get().Handle) end) end
    end)
    C.hook("/Script/Engine.Character:Jump",nil,function(ctx)
        if not self.failed then C.run(C.id,function() self:air_jump(ctx:get()) end) end
    end)
end

function M:player_ready() self:apply() end
function M:changed() self:apply() end
function M:player_left() self:restore() end
return M
