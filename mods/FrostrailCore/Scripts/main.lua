local C=require("Frostrail.runtime").create({action_prefix="FrostrailMods",settings=false})
local panel=require("Frostrail.panel")
local host={title="Frostrail 模组设置"}
function host:setup()
    C.settings.set_busy(false)
    C.action("Settings",{zh="模组设置",en="Mod settings"},"F8",function() panel.toggle(C) end,{allow_ui=true,requires_pawn=false})
end
function host:init() panel.install_menu(C) end
return C.start(host)
