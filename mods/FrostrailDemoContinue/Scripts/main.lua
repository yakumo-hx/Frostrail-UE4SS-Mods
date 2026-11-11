-- Resolve the class-owned CDO once on the game thread; keep no UObject cache.
ExecuteInGameThreadWithDelay(2000, function()
    local ok, err = pcall(function()
        local settings = StaticFindObject("/Script/Frostrail.Default__FrostrailSettings")
        assert(settings:IsValid(), "FrostrailSettings is not available")
        local previous = settings.bIsDemoBuild
        settings.bIsDemoBuild = false
        print("[FrostrailDemoContinue] bIsDemoBuild: " .. tostring(previous)
            .. " -> " .. tostring(settings.bIsDemoBuild) .. "\n")
    end)
    if not ok then
        print("[FrostrailDemoContinue] ERROR: " .. tostring(err) .. "\n")
    end
end)
