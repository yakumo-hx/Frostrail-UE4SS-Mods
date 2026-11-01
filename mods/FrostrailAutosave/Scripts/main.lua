local C=require("Frostrail.runtime").create()
local open,err=package.loadlib(C.dir.."/native/autosave.dll","luaopen_frostrail_autosave")
local ok,native=false,nil
if open then ok,native=pcall(open) end
if not ok or type(native)~="function" then
    local status=open and ok
        and "游戏或 UE4SS 版本已更新，自动保存已停用，等待 Mod 更新 / Unsupported game or UE4SS build; Autosave disabled until the mod is updated."
        or "自动保存 DLL 加载失败，自动保存已停用 / Autosave DLL failed to load; Autosave disabled: "..tostring(err or native)
    C.log(C.id,"ERROR "..status)
    -- No runtime startup, timer or exit hook on incompatible images.
    return {disabled=true,status=status}
end
local M=dofile(C.dir.."/module.lua")
M.native=native
return C.start(M)
