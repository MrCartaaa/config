-- Personal monitor layout. Stock hypr/monitors.lua stays at Omarchy defaults.
-- Acer in the center at 1x; laptop to its right at 1.6.
-- Logical Acer width is 1920, so the laptop starts at x=1920.

local omarchy_gdk_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

hl.monitor({
  output = "HDMI-A-1",
  mode = "preferred",
  position = "0x0",
  scale = 1,
})

hl.monitor({
  output = "eDP-1",
  mode = "preferred",
  position = "1920x0",
  scale = 1.6,
})
