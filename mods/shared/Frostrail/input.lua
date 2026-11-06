local M={}
local settings=require("Frostrail.settings")
local locale=require("Frostrail.locale")
local function state(C)
    local S=C.input_state or {registered={},dispatch={}}
    C.input_state=S
    if not S.presses then
        -- UE4SS calls key callbacks on its input thread while game-thread Lua
        -- may run in this VM. They only read held[code] and bump presses[code];
        -- every virtual-key slot exists up front, so neither table grows later.
        S.held,S.presses,S.seen,S.remapped,S.keys=S.held or {},{},{},{},{}
        for code=1,255 do
            if S.held[code]==nil then S.held[code]=false end
            S.presses[code],S.seen[code],S.remapped[code]=0,0,0
        end
    end
    return S
end
local function editing_text()
    for _,w in ipairs(FindAllOf("EditableTextBox") or {}) do if w:HasKeyboardFocus() then return true end end
    for _,w in ipairs(FindAllOf("InputKeySelector") or {}) do if w:GetIsSelectingKey() then return true end end
    return false
end
local function virtual_key(name)
    if #name==1 then return name:upper():byte() end
    local f=name:match("^F(%d+)$")
    if f then return 111+tonumber(f) end
    local aliases={LeftMouseButton="LEFT_MOUSE_BUTTON",RightMouseButton="RIGHT_MOUSE_BUTTON",MiddleMouseButton="MIDDLE_MOUSE_BUTTON",ThumbMouseButton="XBUTTON_ONE",ThumbMouseButton2="XBUTTON_TWO",SpaceBar="SPACE",Escape="ESCAPE",Tab="TAB",Insert="INS",Delete="DEL",Home="HOME",End="END",PageUp="PAGE_UP",PageDown="PAGE_DOWN",Enter="RETURN",BackSpace="BACKSPACE",CapsLock="CAPS_LOCK",Up="UP_ARROW",Down="DOWN_ARROW",Left="LEFT_ARROW",Right="RIGHT_ARROW",NumLock="NUM_LOCK",ScrollLock="SCROLL_LOCK",Add="ADD",Subtract="SUBTRACT",Multiply="MULTIPLY",Divide="DIVIDE",Decimal="DECIMAL",Semicolon="OEM_ONE",Equals="OEM_PLUS",Comma="OEM_COMMA",Hyphen="OEM_MINUS",Period="OEM_PERIOD",Slash="OEM_TWO",Tilde="OEM_THREE",LeftBracket="OEM_FOUR",Backslash="OEM_FIVE",RightBracket="OEM_SIX",Apostrophe="OEM_SEVEN"}
    local number=name:match("^NumPad(%d)$")
    if number then return 96+tonumber(number) end
    return Key[aliases[name] or name:upper()]
end
local function wait_for_release(C,S,code,key)
    local held={player_name=C.player_name}
    S.held[code]=held
    local function check(delay)
        ExecuteInGameThreadWithDelay(delay,function()
            if S.held[code]~=held then return end
            local down=C.run(C.id,function()
                return C.player_valid() and C.player_name==held.player_name
                    and S.dispatch[code]~=nil and C.player:IsInputKeyDown(key)
            end)
            if down then check(16) else S.held[code]=false end
        end)
    end
    -- Pinned UE4SS polls GetAsyncKeyState's low bit too: a released capture can
    -- arrive after ApplySettings, while paused UI reports IsInputKeyDown=false.
    -- Allow its polling thread to drain that edge before checking for release.
    -- This expires without an event; never consume the next press to unlock it.
    check(50)
end
local none={}
local function run_actions(C,S,code)
    local actions=S.dispatch[code]
    if not actions or not C.player_valid() or editing_text() then return end
    for _,a in ipairs(actions) do
        if (a.requires_pawn==false or C.pawn_valid()) and (a.allow_ui or not settings.busy()) then C.run(C.id,a.callback) end
    end
end
-- Game thread: handle every press counted since the last pump, in order.
function M.pump(C)
    local S=state(C)
    for code in pairs(S.registered) do
        local count,seen=S.presses[code],S.seen[code]
        if count~=seen then
            S.seen[code]=count
            for press=seen+1,count do
                for _,callback in ipairs(S.keys[code] or none) do C.run(C.id,callback) end
                -- A press counted before the mapping changed never uses the new one.
                if press>S.remapped[code] then run_actions(C,S,code) end
            end
        end
    end
end
-- The only RegisterKeyBind: the callback runs on UE4SS's input thread and
-- must not allocate, call UE4SS or touch UObjects. One pump per VM reads it.
local function listen(C,S,code)
    if S.registered[code] then return end
    S.registered[code]=true
    if not S.pump then
        S.pump=LoopInGameThreadWithDelay(16,function() C.run(C.id,M.pump,C) end)
    end
    local held,presses=S.held,S.presses
    RegisterKeyBind(code,function()
        if not held[code] then presses[code]=presses[code]+1 end
    end)
end
-- A fixed key outside the native controls page; internal (Console's search-box
-- Esc). Runs on the game thread without action checks.
function M.key(C,code,callback)
    local S=state(C)
    S.keys[code]=S.keys[code] or {}
    table.insert(S.keys[code],callback)
    listen(C,S,code)
end
function M.sync(C,applying)
    local S=state(C)
    local previous=S.dispatch
    S.dispatch={}
    for code in pairs(S.registered) do S.remapped[code]=S.presses[code] end
    -- Resolve the current settings afresh; ApplySettings may arrive after travel.
    local native_settings=FindFirstOf("FREnhancedInputUserSettings")
    if not C.instance(native_settings,S.settings_name) then return end
    local profile=native_settings:GetActiveKeyProfile()
    if not C.valid(profile) then return end
    for _,action in ipairs(C.actions) do
        local keys={}
        if profile.PlayerMappedKeys:Contains(FName(action.name)) then
            profile.PlayerMappedKeys:Find(FName(action.name)):get().Mappings:ForEach(function(mapping)
                keys[#keys+1]=mapping:get().CurrentKey.KeyName:ToString()
            end)
        end
        for _,name in ipairs(keys) do
            local code=virtual_key(name)
            if code then
                if applying and not previous[code] and not S.dispatch[code] then
                    wait_for_release(C,S,code,{KeyName=FName(name)})
                end
                S.dispatch[code]=S.dispatch[code] or {}
                table.insert(S.dispatch[code],action)
                listen(C,S,code)
                C.log(C.id,action.name.."="..name.." (native profile)")
            end
        end
    end
end
function M.refresh_labels(C)
    local S=state(C)
    local native_settings=FindFirstOf("FREnhancedInputUserSettings")
    if not C.instance(native_settings,S.settings_name) or not C.instance(S.context,S.context_name) then return end
    local labels={}
    for _,a in ipairs(C.actions) do labels[a.name]=settings.label(a.label,locale.language()) end
    local category=locale.text("Frostrail 模组","Frostrail mods")
    S.context.Mappings:ForEach(function(_,p)
        local action=p:get().Action
        if C.valid(action) then
            local keysettings=action.PlayerMappableKeySettings
            if C.valid(keysettings) then
                local label=labels[keysettings.Name:ToString()]
                if label then keysettings.DisplayName=FText(label); keysettings.DisplayCategory=FText(category) end
            end
        end
    end)
    local profile=native_settings:GetActiveKeyProfile()
    if not C.valid(profile) then return end
    for name,label in pairs(labels) do
        if profile.PlayerMappedKeys:Contains(FName(name)) then
            profile.PlayerMappedKeys:Find(FName(name)):get().Mappings:ForEach(function(p)
                -- Only presentation changes. MappingName, CurrentKey and DefaultKey stay intact.
                local mapping=p:get()
                mapping.DisplayName=FText(label)
                mapping.DisplayCategory=FText(category)
            end)
        end
    end
    -- The controls page keeps copies of profile rows while switching settings tabs.
    for _,data in ipairs(FindAllOf("Data_KeybindingListEntry_C") or {}) do
        local mapping=data.PlayerKeyMapping
        local label=labels[mapping.MappingName:ToString()]
        if label then mapping.DisplayName=FText(label); mapping.DisplayCategory=FText(category) end
    end
    for _,entry in ipairs(FindAllOf("WBP_Element_Settings_Controls_KeybindingListEntry_C") or {}) do
        if C.valid(entry.KeybindingData) then
            local label=labels[entry.KeybindingData.PlayerKeyMapping.MappingName:ToString()]
            if label then
                entry.KeybindingText:SetText(FText(label))
                entry.KeybindingCategoryText:SetText(FText(category))
            end
        end
    end
end
function M.attach(C,pc)
    local S=state(C)
    local native_settings=FindFirstOf("FREnhancedInputUserSettings")
    assert(C.valid(native_settings),"Native input settings unavailable")
    if not C.instance(native_settings,S.settings_name) or not C.instance(S.context,S.context_name) then
        S.settings_name=native_settings:GetFullName()
        local ctx=C.new("/Script/EnhancedInput.InputMappingContext",native_settings,"Frostrail_Input_"..C.native_id)
        for _,a in ipairs(C.actions) do
            local action=C.new("/Script/EnhancedInput.InputAction",ctx,a.name:gsub("%.","_"))
            local keysettings=C.new("/Script/EnhancedInput.PlayerMappableKeySettings",action)
            keysettings.Name=FName(a.name)
            keysettings.DisplayName=FText(settings.label(a.label,locale.language()))
            keysettings.DisplayCategory=FText(locale.text("Frostrail 模组","Frostrail mods"))
            action.PlayerMappableKeySettings=keysettings
            action.bConsumeInput=false
            ctx:MapKey(action,{KeyName=FName(a.key or "None")})
        end
        assert(native_settings:RegisterInputMappingContext(ctx),"Native input context registration failed")
        S.context=ctx
        S.context_name=ctx:GetFullName()
        if not S.hooked then
            S.hooked=true
            C.hook("/Script/EnhancedInput.EnhancedInputUserSettings:ApplySettings",nil,function()
                C.run(C.id,M.sync,C,true)
            end)
        end
    end
    if pc:IsA("/Script/Frostrail.FrostrailPlayerControllerBase") then
        pc:AddInputMapping(S.context,100,{bIgnoreAllPressedKeysUntilRelease=true,bForceImmediately=true,bNotifyUserSettings=true})
    end
    M.refresh_labels(C)
    M.sync(C)
end
return M
