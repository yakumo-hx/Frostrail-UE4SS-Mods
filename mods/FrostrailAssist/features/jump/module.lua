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

function M:air_jump(pawn)
    local C=self.core
    if not self.cfg.enabled or not C.pawn_valid() or not C.same(pawn,C.pawn) then return end
    local move=pawn.CharacterMovement
    if not move:IsFalling() or not pawn:CanJump() then return end
    -- Frostrail's DoJump requires a walkable CurrentFloor even in midair.
    -- The original ability already accepted this press (including its carry /
    -- encumbrance restrictions). Supply only the missing second launch, using
    -- native count/reset and retaining horizontal velocity from the first jump.
    local speed=math.max(move.JumpZVelocity,pawn:GetVelocity().Z)
    pawn:StopJumping()
    pawn.JumpCurrentCount=2
    pawn:LaunchCharacter({X=0,Y=0,Z=speed},false,true)
end

function M:init()
    local C=self.core
    C.hook("/Script/Engine.Character:Jump",nil,function(ctx)
        if not self.failed then C.run(C.id,function() self:air_jump(ctx:get()) end) end
    end)
end

function M:player_ready() self:apply() end
function M:changed() self:apply() end
function M:player_left() self:restore() end
return M
