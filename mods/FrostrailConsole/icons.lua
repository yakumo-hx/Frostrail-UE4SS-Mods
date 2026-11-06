-- World-scoped native ViewModels. The rooted ObjectLibrary, not a panel,
-- owns them until map load, player departure or an explicit reset.
local I={}
local none={}
function I.clear(M)
    M.icon_cache=nil
    M.core.retain("console_icons",{})
end
function I.prepare(M)
    local C=M.core
    local world=C.player:GetWorld()
    local cache=M.icon_cache
    if cache and C.instance(world,cache.world_name) then return cache end
    I.clear(M)
    cache={world=world,world_name=world:GetFullName(),icons={},held={},next=1}
    M.icon_cache=cache
    return cache
end
-- The cached ViewModel for a row, or nil for explicit icons and unrequested rows.
function I.get(M,row)
    local C,cache=M.core,M.icon_cache
    local entry=cache and cache.icons[row.path]
    if entry and C.instance(entry.object,entry.name) then return entry.object end
end
-- Request every row that still needs a native capture. One retain covers the
-- whole batch: each retain rewrites the library's full object list.
function I.request(M,rows)
    local C=M.core
    local cache=I.prepare(M)
    local fresh={}
    for _,row in ipairs(rows) do
        if not I.get(M,row) and not C.valid(row.object.OverrideIcon) then
            -- Native RequestRegularSchematicIcon resolves its subsystem via GetWorld.
            -- The library roots the VM, while World supplies that native context.
            local vm=C.new("/Script/Frostrail.ItemIconViewModel",cache.world)
            cache.icons[row.path]={object=vm,name=vm:GetFullName()}
            cache.held[#cache.held+1]=vm
            fresh[#fresh+1]={vm=vm,row=row}
        end
    end
    if #fresh==0 then return end
    C.retain("console_icons",cache.held)
    for _,f in ipairs(fresh) do f.vm:RequestRegularSchematicIcon(f.row.object) end
end
-- After the first opening, queue eight more rows per game-thread tick. A cursor
-- keeps finished passes from re-reading every row's icon each tick.
function I.warm(M)
    local C,cache=M.core,M.icon_cache
    if not cache then return end -- Start only after the first opening.
    if not C.player_valid() or not C.instance(C.player:GetWorld(),cache.world_name) then
        I.clear(M);return
    end
    local rows=M.rows or none
    if cache.rows~=rows then cache.rows,cache.next=rows,1 end
    local batch={}
    while cache.next<=#rows and #batch<8 do
        local row=rows[cache.next];cache.next=cache.next+1
        if not cache.icons[row.path] and not C.valid(row.object.OverrideIcon) then batch[#batch+1]=row end
    end
    if #batch>0 then I.request(M,batch) end
end
return I
