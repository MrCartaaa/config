-- Personal monitor layout. Stock hypr/monitors.lua stays at Omarchy defaults.

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

hl.monitor({
  output = "eDP-1",
  mode = "preferred",
  position = "0x0",
  scale = "1.5",
})

hl.monitor({
  output = "HDMI-A-1",
  mode = "preferred",
  position = "1280x0",
  scale = omarchy_monitor_scale,
})
