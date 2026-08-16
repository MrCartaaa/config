-- ============================================================================
-- Custom overrides / additions
-- ============================================================================

-- Terminal / tmux
hl.bind("SUPER + RETURN",
  hl.dsp.exec_cmd("ghostty"),
  { description = "Ghostty Terminal" })

hl.bind("SUPER + ALT + RETURN",
  hl.dsp.exec_cmd([[uwsm-app -- xdg-terminal-exec --dir="$(omarchy-cmd-terminal-cwd)" tmux new]]),
  { description = "Tmux" })

-- Browser
hl.bind("SUPER + SHIFT + B",
  hl.dsp.exec_cmd("omarchy-launch-browser"),
  { description = "Browser" })

hl.bind("SUPER + SHIFT + ALT + B",
  hl.dsp.exec_cmd("omarchy-launch-browser --private"),
  { description = "Browser (private)" })

-- Applications
hl.bind("SUPER + SHIFT + D",
  hl.dsp.exec_cmd("omarchy-launch-tui lazydocker"),
  { description = "Docker" })

hl.bind("SUPER + SHIFT + S",
  hl.dsp.exec_cmd([[omarchy-launch-or-focus ^spotify$ "uwsm-app -- spotify"]]),
  { description = "Spotify" })

hl.bind("SUPER + SHIFT + C",
  hl.dsp.exec_cmd([[omarchy-launch-or-focus ^signal$ "uwsm-app -- signal-desktop"]]),
  { description = "Signal" })

hl.bind("SUPER + SHIFT + O",
  hl.dsp.exec_cmd([[omarchy-launch-or-focus ^obsidian$ "uwsm-app -- obsidian"]]),
  { description = "Obsidian" })

hl.bind("SUPER + SHIFT + F",
  hl.dsp.exec_cmd([[uwsm-app -- nautilus --new-window "$(omarchy-cmd-terminal-cwd)"]])
)
-- File manager (cwd), exec, uwsm-app -- nautilus --new-window "$(omarchy-cmd-terminal-cwd)"

-- Web apps
hl.bind("SUPER + SHIFT + G",
  hl.dsp.exec_cmd([[omarchy-launch-webapp "https://github.com/"]]),
  { description = "GitHub" })

hl.bind("SUPER + BACKSLASH",
  hl.dsp.exec_cmd([[omarchy-launch-webapp "https://drive.proton.me"]]),
  { description = "Cloud" })

hl.bind("SUPER + SHIFT + SLASH",
  hl.dsp.exec_cmd([[omarchy-launch-webapp "https://pass.proton.me"]]),
  { description = "Passwords" })

hl.bind("SUPER + SHIFT + BACKSLASH",
  hl.dsp.exec_cmd([[omarchy-launch-webapp "https://us1.storj.io/projects"]]),
  { description = "Storj" })

hl.bind("SUPER + SHIFT + X",
  hl.dsp.exec_cmd([[omarchy-launch-webapp "https://x.com/"]]),
  { description = "X" })

hl.bind("SUPER + SHIFT + ALT + X",
  hl.dsp.exec_cmd([[omarchy-launch-webapp "https://x.com/compose/post"]]),
  { description = "X Post" })

hl.bind("SUPER + SHIFT + M",
  hl.dsp.exec_cmd([[omarchy-launch-webapp "https://mail.proton.me"]]),
  { description = "Email" })

-- ============================================================================
-- Resize submap
-- ============================================================================

hl.bind("SUPER + R", hl.dsp.submap("resize"))

hl.define_submap("resize", function()
  hl.bind("H",
    hl.dsp.window.resize({ x = -20, y = 0, relative = true }),
    { repeating = true })

  hl.bind("L",
    hl.dsp.window.resize({ x = 20, y = 0, relative = true }),
    { repeating = true })

  hl.bind("K",
    hl.dsp.window.resize({ x = 0, y = -20, relative = true }),
    { repeating = true })

  hl.bind("J",
    hl.dsp.window.resize({ x = 0, y = 20, relative = true }),
    { repeating = true })

  hl.bind("ESCAPE", hl.dsp.submap("reset"))
end)

-- =========================
-- keybinds (correct Hyprland Lua 0.55+)
-- =========================

hl.bind("XF86AudioRaiseVolume",
  hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"))

hl.bind("XF86AudioLowerVolume",
  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))

hl.bind("XF86AudioMute",
  hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))

hl.bind("XF86AudioPrev",
  hl.dsp.exec_cmd("playerctl previous"))

hl.bind("XF86AudioPlay",
  hl.dsp.exec_cmd("playerctl play-pause"))

hl.bind("XF86AudioNext",
  hl.dsp.exec_cmd("playerctl next"))

hl.bind("XF86MonBrightnessUp",
  hl.dsp.exec_cmd("brightnessctl set +10%"))

hl.bind("XF86MonBrightnessDown",
  hl.dsp.exec_cmd("brightnessctl set 10%-"))
