-- Lock without the Omarchy terminal screensaver.
-- Idle lock itself stays on Omarchy's idle.lock (currently 300s).
-- `omarchy-launch-screensaver` exits when screensaver-off is set.

hl.on("hyprland.start", function()
  hl.exec_cmd("omarchy-toggle screensaver-off on")
end)

local function is_screensaver(win)
  return win and string.match(win.class or "", "^org%.omarchy%.screensaver$")
end

local function dismiss_screensaver(win)
  if not is_screensaver(win) then return end
  hl.dispatch(hl.dsp.window.close({ window = win }))
end

hl.window_rule({
  match          = { class = "^org%.omarchy%.screensaver$" },
  no_initial_focus = true,
  no_focus       = true,
})

hl.on("window.open_early", dismiss_screensaver)
hl.on("window.open", dismiss_screensaver)
