-- =============================================
-- Custom Scratchpads
-- =============================================

Scratch_height = 0.9
Scratch_width  = 0.8

-- ================== Alacritty Scratchpad ==================

hl.workspace_rule({
  workspace = "special:Alacritty-scratchpad",
  on_created_empty = "alacritty --class Alacritty-scratchpad",
})

hl.window_rule({
  match       = { class = "^Alacritty-scratchpad$" },
  float       = true,
  center      = true,
  size        = { string.format("monitor_w * %s", Scratch_width), string.format("monitor_h * %s", Scratch_height) },
  opacity     = "0.85 override 0.35 override 0.85 override",
  border_size = 0,
  xray        = true,
  dim_around  = true,
  rounding    = 14,
  no_focus    = false
})

hl.bind("SUPER + GRAVE", hl.dsp.workspace.toggle_special("Alacritty-scratchpad"),
  { description = "Terminal Scratchpad" }
)

-- ================== Nvim Scratchpad ==================

hl.workspace_rule({
  workspace = "special:Nvim-scratchpad",
  on_created_empty = "alacritty --class Nvim-scratchpad -e nvim",
})

hl.window_rule({
  match       = { class = "^Nvim-scratchpad$" },
  float       = true,
  center      = true,
  size        = { string.format("monitor_w * %s", Scratch_width), string.format("monitor_h * %s", Scratch_height) },
  opacity     = "0.85 override 0.35 override 0.85 override",
  border_size = 0,
  xray        = true,
  rounding    = 14,
  dim_around  = true,
})

hl.bind("SUPER + E", hl.dsp.workspace.toggle_special("Nvim-scratchpad"),
  { description = "Editor Scratchpad" }
)

-- ================== Multi-WebApp Query Scratchpad ==================

local Scratch_name = "Query-scratchpad"

local webapps = {
  {
    name  = "ChatGPT",
    cmd   = "omarchy-launch-webapp https://chatgpt.com",
    class = "chatgpt.com"
  },
  {
    name  = "Grok",
    cmd   = "omarchy-launch-webapp https://grok.com",
    class = "grok.com"
  },
  {
    name = "local",
    cmd = "omarchy-launch-webapp http://192.168.2.15:8080",
    class = "192.168.2.15"
  },
  {
    name = "perplexity",
    cmd = "omarchy-launch-webapp https://perplexity.ai",
    class = "perplexity.ai"
  }
}

local cmds = {}

for _, app in ipairs(webapps) do
  table.insert(cmds, app.cmd)
end

hl.workspace_rule({
  workspace = "special:" .. Scratch_name,
  on_created_empty = table.concat(cmds, " & ")
})

for _, app in ipairs(webapps) do
  hl.window_rule({
    match       = { class = "^brave-" .. app.class .. "__-Default$" },

    workspace   = "special:" .. Scratch_name,

    float       = true,

    size        = {
      string.format("monitor_w * %s", Scratch_width),
      string.format("monitor_h * %s", Scratch_height)
    },

    -- IMPORTANT:
    -- same exact coordinates for all windows
    move        = {
      string.format("monitor_w * %s", (1 - Scratch_width) / 2),
      string.format("monitor_h * %s", (1 - Scratch_height) / 2)
    },

    opacity     = "0.85 override 0.35 override 0.85 override",
    border_size = 0,
    rounding    = 14,
    xray        = true,
    dim_around  = true,
  })
end

hl.bind(
  "SUPER + Q",
  hl.dsp.workspace.toggle_special(Scratch_name),
  { description = "Multi-WebApp Query Scratchpad" }
)

-- ================== Resize Helper ==================

local function resize_scratchpad(class)
  local win = hl.get_active_window()
  if not win then return end

  local is_query = string.find(win.class or "", "^brave%-.*__.*%-Default$")
  if win.class ~= class and not is_query then
    return
  end

  local mon = hl.get_active_monitor()
  if mon then
    local width  = math.floor(mon.width * 0.78)
    local height = math.floor(mon.height * 0.72)

    if mon.id == 0 then
      width  = width / 1.5
      height = height / 1.5
    end

    hl.dispatch(hl.dsp.window.center())
    hl.dispatch(hl.dsp.window.resize({ x = width, y = height }))
    if is_query then
      local ws_windows = hl.get_workspace_windows(hl.get_active_window().workspace) or {}
      for _, w in ipairs(ws_windows) do
        hl.dispatch(hl.dsp.window.center({ window = w }))
        hl.dispatch(hl.dsp.window.resize({ x = width, y = height, window = w }))
      end
    end
  end
end

-- Consolidated window.active hook
hl.on("window.active", function()
  resize_scratchpad("Alacritty-scratchpad")
  resize_scratchpad("Nvim-scratchpad")
end)

-- =============================================
-- Prevent non-scratchpad apps from spawning
-- inside special workspaces
-- =============================================

local special_workspace_rules = {
  ["special:Alacritty-scratchpad"] = {
    "^Alacritty%-scratchpad$",
  },

  ["special:Nvim-scratchpad"] = {
    "^Nvim%-scratchpad$",
  },

  ["special:Query-scratchpad"] = {
    "^brave%-chatgpt%.com__%-Default$",
    "^brave%-grok%.com__%-Default$",
    "^brave%-192%.168%.2%.15__%-Default$",
    "^brave%-perplexity%.ai__%-Default$",
  },
}

local last_workspace = "1"

hl.on("window.active", function(ws)
  if not ws then return end

  if not ws.workspace then return end
  if not string.match(ws.workspace.name or "", "^special:") then
    last_workspace = ws.workspace.name
  end
end)


local function class_allowed_for_workspace(workspace, class)
  local allowed = special_workspace_rules[workspace]

  if not allowed then
    return true
  end

  for _, pattern in ipairs(allowed) do
    if string.match(class or "", pattern) then
      return true
    end
  end

  return false
end

hl.on("window.open", function(win)
  if not win then
    return
  end

  local workspace =
      win.workspace and win.workspace.name or ""

  local class =
      win.class or ""

  -- only care about special workspaces
  if not string.match(workspace, "^special:") then
    return
  end

  -- allow approved windows
  if class_allowed_for_workspace(workspace, class) then
    return
  end

  -- eject everything else
  hl.dispatch(
    hl.dsp.window.move({ workspace = last_workspace, address = win.address })
  )
end)
