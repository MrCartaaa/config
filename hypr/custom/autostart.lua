-- Extra autostart processes.
hl.on("hyprland.start", function()
  hl.exec_cmd("systemctl --user start foot-server.socket foot-server.service")
  hl.dsp.workspace.toggle_special("foot-scratchpad")

  -- Workspace 1: default browser; 2: Thunderbird; 6: Spotify.
  -- uwsm-app / systemd-run fork, so also pin these classes below.
  hl.exec_cmd("omarchy-launch-browser", { workspace = "1" })
  hl.exec_cmd("uwsm-app -- thunderbird", { workspace = "2 silent" })
  hl.exec_cmd("uwsm-app -- spotify", { workspace = "6 silent" })
  hl.dispatch(hl.dsp.focus({ workspace = "1" }))
end)

-- Keep those apps on their login workspaces even if exec rules miss the fork.
local default_browser = "brave-browser-nightly"
local desktop = io.popen("xdg-settings get default-web-browser 2>/dev/null")
if desktop then
  local name = desktop:read("*l")
  desktop:close()
  if name and name ~= "" then
    default_browser = name:gsub("%.desktop$", "")
  end
end

o.window(default_browser, { workspace = "1 silent" })
-- Main Thunderbird stays on workspace 2; Write: compose windows go to the compose scratchpad.
o.window(
  { class = "org.mozilla.Thunderbird", title = "negative:^Write:" },
  { workspace = "2 silent" }
)
o.window("Spotify", { workspace = "6 silent" })
