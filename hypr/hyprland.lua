-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

local home = os.getenv("HOME") or ""

package.path = home .. "/.config/?.lua;" ..
    (os.getenv("OMARCHY_PATH") or (home .. "/.local/share/omarchy")) ..
    "/?.lua;" .. package.path

local paths = require("default.hypr.paths")

-- Core Omarchy defaults
require("default.hypr.autostart")
require("default.hypr.bindings.media")
require("default.hypr.bindings.clipboard")
require("default.hypr.bindings.tiling-v2")
require("default.hypr.bindings.utilities")
require("default.hypr.envs")
require("default.hypr.looknfeel")
require("default.hypr.input")
require("default.hypr.windows")

-- Theme override (unchanged logic)
do
  local theme = io.open(paths.config_home .. "/omarchy/current/theme/hyprland.lua", "r")
  if theme then
    theme:close()
    require("omarchy.current.theme.hyprland")
  end
end

-- Your personal configs (formerly `source = ~/.config/hypr/*.conf`)
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
require("hypr.custom.scratchpad")
require("hypr.custom.bindings")
require("hypr.custom.autostart")

-- Toggle config flags dynamically (replaces ~/.local/state/omarchy/toggles/*.conf)
require("default.hypr.toggles")
