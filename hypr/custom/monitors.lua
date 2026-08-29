-- Personal monitor layout. Stock hypr/monitors.lua stays at Omarchy defaults.
-- Laptop left at 1.6; HDMI right at 1x. Logical laptop width is 1920/1.6 = 1200.

local omarchy_gdk_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

hl.monitor({
  output = "eDP-1",
  mode = "preferred",
  position = "0x0",
  scale = 1.6,
})

hl.monitor({
  output = "HDMI-A-1",
  mode = "preferred",
  position = "1200x0",
  scale = 1,
})
