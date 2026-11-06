-- =============================================
-- Custom Scratchpads
-- =============================================

Scratch_height = 0.9
Scratch_width  = 0.8

-- ================== Foot Scratchpad ==================

hl.workspace_rule({
  workspace = "special:foot-scratchpad",
  on_created_empty = "sh -c 'footclient --app-id=foot-scratchpad tmux new-session -A -s main || foot --app-id=foot-scratchpad tmux new-session -A -s main'",
})

hl.window_rule({
  match       = { class = "^foot-scratchpad$" },
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

-- The keysym is lowercase "grave". "GRAVE" does not match, so Omarchy's
-- Quake console on SUPER+grave was the bind that ran. ~ + Super toggles
-- the tmux terminal scratchpad.
hl.unbind("SUPER + grave")
hl.unbind("SUPER + GRAVE")
hl.bind("SUPER + grave", hl.dsp.workspace.toggle_special("foot-scratchpad"),
  { description = "Tmux terminal" }
)

-- ================== Nvim Scratchpad ==================

hl.workspace_rule({
  workspace = "special:Nvim-scratchpad",
  on_created_empty = "sh -c 'footclient --app-id=Nvim-scratchpad nvim || foot --app-id=Nvim-scratchpad nvim'",
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

-- ================== Obsidian Scratchpad ==================

hl.workspace_rule({
  workspace = "special:Obsidian-scratchpad",
  on_created_empty = "uwsm-app -- obsidian",
})

hl.window_rule({
  match       = { class = "^md%.obsidian%.Obsidian$" },
  workspace   = "special:Obsidian-scratchpad",
  float       = true,
  size        = {
    string.format("monitor_w * %s", Scratch_width),
    string.format("monitor_h * %s", Scratch_height)
  },
  move        = {
    string.format("monitor_w * %s", (1 - Scratch_width) / 2),
    string.format("monitor_h * %s", (1 - Scratch_height) / 2)
  },
  opacity     = "0.85 override 0.35 override 0.85 override",
  border_size = 0,
  xray        = true,
  rounding    = 14,
  dim_around  = true,
})

hl.bind("SUPER + N", hl.dsp.workspace.toggle_special("Obsidian-scratchpad"),
  { description = "Obsidian Scratchpad" }
)

-- ================== Obsidian Quick Note Scratchpad ==================
-- Always creates a new timestamped note in vault/quick-notes.
-- Super+Shift+N was Editor (omarchy-launch-editor). Super+E is the editor pad.

local Quicknote_ws = "quicknote-scratchpad"
local Quicknote_script = (os.getenv("HOME") or "") .. "/.config/hypr/custom/quick-note.sh"
local Quicknote_pending_until = 0
local Quicknote_addresses = {}

local function is_obsidian(win)
  return win and string.match(win.class or "", "^md%.obsidian%.Obsidian$")
end

local function is_quick_note(win)
  return win and win.address and Quicknote_addresses[win.address]
end

local function count_obsidian_windows()
  local n = 0
  for _, win in ipairs(hl.get_windows() or {}) do
    if is_obsidian(win) then
      n = n + 1
    end
  end
  return n
end

local function style_quick_note(win)
  if not win then return end
  hl.dispatch(hl.dsp.window.move({
    workspace = "special:" .. Quicknote_ws,
    window = win,
  }))
  if not win.floating then
    hl.dispatch(hl.dsp.window.float({ action = "set", window = win }))
  end
  hl.dispatch(hl.dsp.window.center({ window = win }))
end

local function mark_quick_note(win)
  if not win or not win.address then return end
  Quicknote_addresses[win.address] = true
  style_quick_note(win)
end

local function claim_quick_note(win)
  if not is_obsidian(win) then return end
  if is_quick_note(win) then
    style_quick_note(win)
    return
  end
  if os.time() > Quicknote_pending_until then return end
  -- Main vault window is the first Obsidian client; the pop-out is the next one.
  if count_obsidian_windows() >= 2 then
    mark_quick_note(win)
    Quicknote_pending_until = 0
  end
end

local function close_quick_notes()
  for _, win in ipairs(hl.get_windows() or {}) do
    if is_quick_note(win) then
      hl.dispatch(hl.dsp.window.close({ window = win }))
    end
  end
end

local function quicknote_visible()
  local ws = hl.get_workspace("special:" .. Quicknote_ws)
  return ws and ws.visible
end

hl.window_rule({
  match = {
    class = "^md%.obsidian%.Obsidian$",
    title = "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}",
  },
  workspace   = "special:quicknote-scratchpad",
  float       = true,
  size        = {
    string.format("monitor_w * %s", Scratch_width),
    string.format("monitor_h * %s", Scratch_height)
  },
  move        = {
    string.format("monitor_w * %s", (1 - Scratch_width) / 2),
    string.format("monitor_h * %s", (1 - Scratch_height) / 2)
  },
  opacity     = "0.85 override 0.35 override 0.85 override",
  border_size = 0,
  xray        = true,
  rounding    = 14,
  dim_around  = true,
})

hl.on("window.open", claim_quick_note)
hl.on("window.title", claim_quick_note)

hl.on("window.close", function(win)
  if not is_quick_note(win) then return end
  Quicknote_addresses[win.address] = nil
  hl.exec_cmd(Quicknote_script .. " --discard")
end)

hl.unbind("SUPER + SHIFT + N")
hl.bind("SUPER + SHIFT + N", function()
  if quicknote_visible() then
    close_quick_notes()
    if quicknote_visible() then
      hl.dispatch(hl.dsp.workspace.toggle_special(Quicknote_ws))
    end
    return
  end

  close_quick_notes()
  Quicknote_pending_until = os.time() + 8
  hl.exec_cmd(Quicknote_script)
end, { description = "Quick note" })

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

-- SUPER+Q was also Close window. Keep the query scratchpad only.
hl.unbind("SUPER + Q")
hl.bind(
  "SUPER + Q",
  hl.dsp.workspace.toggle_special(Scratch_name),
  { description = "Multi-WebApp Query Scratchpad" }
)

-- ================== News Scratchpad ==================

local News_name = "News-scratchpad"

local news_webapps = {
  {
    name  = "Ground News",
    cmd   = "omarchy-launch-webapp https://ground.news",
    class = "ground.news"
  },
  {
    name  = "Financial Post",
    cmd   = "omarchy-launch-webapp https://financialpost.com/",
    class = "financialpost.com"
  },
  {
    name  = "National Post",
    cmd   = "omarchy-launch-webapp https://nationalpost.com/",
    class = "nationalpost.com"
  },
}

local news_cmds = {}

for _, app in ipairs(news_webapps) do
  table.insert(news_cmds, app.cmd)
end

hl.workspace_rule({
  workspace = "special:" .. News_name,
  on_created_empty = table.concat(news_cmds, " & ")
})

for _, app in ipairs(news_webapps) do
  hl.window_rule({
    match       = { class = "^brave-" .. app.class .. "__-Default$" },
    workspace   = "special:" .. News_name,
    float       = true,
    size        = {
      string.format("monitor_w * %s", Scratch_width),
      string.format("monitor_h * %s", Scratch_height)
    },
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
  "SUPER + H",
  hl.dsp.workspace.toggle_special(News_name),
  { description = "News Scratchpad" }
)

-- ================== Thunderbird Compose Scratchpad ==================

local Compose_ws = "compose-scratchpad"

local function is_compose_window(win)
  if not win then return false end
  if not string.match(win.class or "", "^org%.mozilla%.Thunderbird$") then
    return false
  end
  return string.match(win.title or "", "^Write:")
end

local function style_compose_window(win)
  if not win then return end
  hl.dispatch(hl.dsp.window.move({
    workspace = "special:" .. Compose_ws,
    window = win,
  }))
  if not win.floating then
    hl.dispatch(hl.dsp.window.float({ action = "set", window = win }))
  end
  hl.dispatch(hl.dsp.window.center({ window = win }))
end

local function compose_windows()
  local wins = {}
  for _, win in ipairs(hl.get_windows() or {}) do
    if is_compose_window(win) then
      table.insert(wins, win)
    end
  end
  return wins
end

local function compose_visible()
  local ws = hl.get_workspace("special:" .. Compose_ws)
  return ws and ws.visible
end

-- Title match is best-effort: static rules see initialTitle, which may
-- still be "Mozilla Thunderbird". window.title below catches the Write: rename.
hl.window_rule({
  match = {
    class = "^org%.mozilla%.Thunderbird$",
    title = "^Write:",
  },
  workspace   = "special:compose-scratchpad",
  float       = true,
  size        = {
    string.format("monitor_w * %s", Scratch_width),
    string.format("monitor_h * %s", Scratch_height)
  },
  move        = {
    string.format("monitor_w * %s", (1 - Scratch_width) / 2),
    string.format("monitor_h * %s", (1 - Scratch_height) / 2)
  },
  opacity     = "0.85 override 0.35 override 0.85 override",
  border_size = 0,
  xray        = true,
  rounding    = 14,
  dim_around  = true,
})

hl.on("window.open", function(win)
  if is_compose_window(win) then
    style_compose_window(win)
  end
end)

hl.on("window.title", function(win)
  if is_compose_window(win) then
    style_compose_window(win)
  end
end)

hl.unbind("SUPER + SHIFT + M")
hl.bind("SUPER + SHIFT + M", function()
  if compose_visible() then
    hl.dispatch(hl.dsp.workspace.toggle_special(Compose_ws))
    return
  end

  if #compose_windows() == 0 then
    hl.exec_cmd("uwsm-app -- thunderbird -compose")
  end
  hl.dispatch(hl.dsp.workspace.toggle_special(Compose_ws))
end, { description = "Compose email" })

-- ================== Resize Helper ==================
-- window.resize during mapWindow aborts Hyprland (CSpace::resizeTarget).
-- Query/news pads are sized by window_rule; defer the rest until mapped.

local resize_classes = {
  ["foot-scratchpad"] = true,
  ["Nvim-scratchpad"] = true,
  ["md.obsidian.Obsidian"] = true,
}

local resize_pending = false

local function apply_scratchpad_resize()
  resize_pending = false
  local win = hl.get_active_window()
  if not win or not win.mapped or not win.floating then
    return
  end
  if not resize_classes[win.class or ""] and not is_compose_window(win) then
    return
  end

  local mon = hl.get_active_monitor()
  if not mon then return end

  local width  = math.floor(mon.width * 0.78)
  local height = math.floor(mon.height * 0.72)
  if mon.id == 0 then
    width  = width / 1.5
    height = height / 1.5
  end

  hl.dispatch(hl.dsp.window.center({ window = win }))
  hl.dispatch(hl.dsp.window.resize({ x = width, y = height, window = win }))
end

local resize_timer = hl.timer(apply_scratchpad_resize, { timeout = 50, type = "oneshot" })
resize_timer:set_enabled(false)

hl.on("window.active", function()
  if resize_pending then return end
  local win = hl.get_active_window()
  if not win then return end
  if not resize_classes[win.class or ""] and not is_compose_window(win) then
    return
  end
  resize_pending = true
  resize_timer:set_enabled(true)
end)

-- =============================================
-- Prevent non-scratchpad apps from spawning
-- inside special workspaces
-- =============================================

local special_workspace_rules = {
  ["special:foot-scratchpad"] = {
    "^foot%-scratchpad$",
  },

  ["special:Nvim-scratchpad"] = {
    "^Nvim%-scratchpad$",
  },

  ["special:Obsidian-scratchpad"] = {
    "^md%.obsidian%.Obsidian$",
  },

  ["special:quicknote-scratchpad"] = {
    "^md%.obsidian%.Obsidian$",
  },

  ["special:compose-scratchpad"] = {
    "^org%.mozilla%.Thunderbird$",
  },

  ["special:Query-scratchpad"] = (function()
    local pats = {}
    for _, app in ipairs(webapps) do
      pats[#pats + 1] = "^brave%-" .. app.class:gsub("([^%w])", "%%%1") .. "__%-Default$"
    end
    return pats
  end)(),

  ["special:News-scratchpad"] = (function()
    local pats = {}
    for _, app in ipairs(news_webapps) do
      pats[#pats + 1] = "^brave%-" .. app.class:gsub("([^%w])", "%%%1") .. "__%-Default$"
    end
    return pats
  end)(),
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
