local M={}
function M.language()
    local value=StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary"):GetCurrentLanguage()
    local tag=type(value)=="string" and value or value:ToString()
    return tag:lower():sub(1,2)=="zh" and "zh" or "en"
end
function M.text(zh,en) return M.language()=="zh" and zh or en end
return M
