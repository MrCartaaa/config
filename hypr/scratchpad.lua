-- Custom Scratchpads

Scratch_height = 0.9
Scratch_width = 0.8

-- ================== Alacritty Scratchpad ==================

-- 1. Workspace rule (auto-launch)
hl.workspace_rule({
  workspace = "special:Alacritty-scratchpad",
  on_created_empty = "alacritty --class Alacritty-scratchpad",
})


-- Main window rules for the scratchpad
hl.window_rule({
  match = { class = "^Alacritty-scratchpad$" },
  float = true,
  center = true,
  size = { string.format("monitor_w * %s", Scratch_width), string.format("monitor_h * %s", Scratch_height) },
  opacity = "0.85 override 0.35 override 0.85 override", -- active / inactive
  border_size = 0,
  xray = true,
  dim_around = true,
  no_focus = false
})

-- 4. Toggle bind
hl.bind("SUPER + GRAVE",
  hl.dsp.workspace.toggle_special("Alacritty-scratchpad"),
  { description = "Terminal Scratchpad" }
)

-- ================== Robust Dynamic Resize ==================

local function resize_scratchpad(class)
  local win = hl.get_active_window()
  if not win or win.class ~= class then
    return
  end

  -- Small delay + re-fetch to ensure monitor is correct after move
  local mon = hl.get_active_monitor()
  if mon then
    local width, height
    width = math.floor(mon.width * 0.78)
    height = math.floor(mon.height * 0.72)

    if mon.id == 0 then
      hl.notification.create({ text = mon.id, duration = 3000 })
      -- Laptop (scaled 1.5) — make it larger percentage
      width = width / 1.5

      height = height / 1.5
    end
    hl.dispatch(hl.dsp.window.center())
    hl.dispatch(hl.dsp.window.resize({ x = width, y = height, false }))
  end
end

-- Main triggers
hl.on("window.active", function() resize_scratchpad("Alacritty-scratchpad") end)

-- ================== Editor Scratchpad ==================

-- 1. Workspace rule (auto-launch)
hl.workspace_rule({
  workspace = "special:Nvim-scratchpad",
  on_created_empty = "alacritty --class Nvim-scratchpad -e nvim",
})


-- Main window rules for the scratchpad
hl.window_rule({
  match = { class = "^Nvim-scratchpad$" },
  float = true,
  center = true,
  size = { string.format("monitor_w * %s", Scratch_width), string.format("monitor_h * %s", Scratch_height) },
  opacity = "0.85 override 0.35 override 0.85 override", -- active / inactive
  border_size = 0,
  xray = true,
  dim_around = true,
})

-- 4. Toggle bind
hl.bind("SUPER + E",
  hl.dsp.workspace.toggle_special("Nvim-scratchpad"),
  { description = "Editor Scratchpad" }
)

hl.on("window.active", function() resize_scratchpad("Nvim-scratchpad") end)


-- ================== Agents Scratchpad ==================

-- 1. Workspace rule (auto-launch)
hl.workspace_rule({
  workspace = "special:Query-scratchpad",
  on_created_empty = "brave --app=https://chatgpt.com/ --class Query-scratchpad",
})


-- Main window rules for the scratchpad
hl.window_rule({
  match = { class = "^Query-scratchpad$" },
  float = true,
  center = true,
  size = { string.format("monitor_w * %s", Scratch_width), string.format("monitor_h * %s", Scratch_height) },
  opacity = "0.85 override 0.35 override 0.85 override", -- active / inactive
  border_size = 0,
  xray = true,
  dim_around = true,
  group = ""
})

-- 4. Toggle bind
hl.bind("SUPER + Q",
  hl.dsp.workspace.toggle_special("Query-scratchpad"),
  { description = "Agent / Query Scratchpad" }
)

hl.on("window.active", function() resize_scratchpad("Query-scratchpad") end)
