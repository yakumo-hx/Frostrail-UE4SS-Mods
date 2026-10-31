local M={}
local settings=require("Frostrail.settings")
local function state(C)
    C.input_state=C.input_state or {registered={},dispatch={},held={}}
    return C.input_state
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
        ExecuteWithDelay(delay,function() ExecuteInGameThread(function()
            if S.held[code]~=held then return end
            local down=C.run(C.id,function()
                return C.player_valid() and C.player_name==held.player_name
                    and S.dispatch[code]~=nil and C.player:IsInputKeyDown(key)
            end)
            if down then check(16) else S.held[code]=nil end
        end) end)
    end
    -- Pinned UE4SS polls GetAsyncKeyState's low bit too: a released capture can
    -- arrive after ApplySettings, while paused UI reports IsInputKeyDown=false.
    -- Allow its polling thread to drain that edge before checking for release.
    -- This expires without an event; never consume the next press to unlock it.
    check(50)
end
function M.sync(C,applying)
    local S=state(C)
    local previous=S.dispatch
    S.dispatch={}
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
                if not S.registered[code] then
                    S.registered[code]=true
                    RegisterKeyBind(code,function()
                        if S.held[code] then return end
                        -- Do not route an already queued press through a newer mapping.
                        local actions=S.dispatch[code]
                        if not actions then return end
                        ExecuteInGameThread(function()
                            if S.dispatch[code]~=actions or not C.player_valid() or editing_text() then return end
                            for _,a in ipairs(actions) do
                                if (a.requires_pawn==false or C.pawn_valid()) and (a.allow_ui or not settings.busy()) then C.run(C.id,a.callback) end
                            end
                        end)
                    end)
                end
                C.log(C.id,action.name.."="..name.." (native profile)")
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
            keysettings.DisplayName=FText(a.label)
            keysettings.DisplayCategory=FText("Frostrail 模组")
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
    M.sync(C)
end
return M
