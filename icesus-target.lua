-- Icesus Target for MudForge, v1.4
-- v1.4 change: round the borders. Canvas has a real
-- rounded-rectangle call, guide § canvas:
-- drawRoundedRect(x, y, w, h, radius, color), with
-- radius kept at or below half the shorter side.
-- The action box from v1.3 is now outer radius 8px,
-- inner radius 6px, so the 2px accent frame stays
-- even around the corners, matching the HTML panels'
-- 8px card radius. The target bars are rounded too,
-- radius 6px, with the fill's radius capped at half
-- its own width so a tiny low-HP fill does not get a
-- radius wider than itself.
-- v1.3 change: the action line gets a border and context.
-- Before, Char.Status activity showed as bare cyan text,
-- e.g. "Using strike", with no frame and no clue who
-- the strike was aimed at. Now, when activity is present,
-- it is drawn inside a bordered box, with:
--   Line 1: "Action: <activity>", e.g. "Action: Using strike"
--   Line 2: "Target: <primary target>", from Char.Status
--     enemy, e.g. "Target: A fairly big and good-looking rat"
--     (truncated to fit, "Something" shown as unidentified).
-- The box is an accent-coloured frame (2px) around a
-- slightly lighter inner background, so the action is
-- visually separated from the target bars above it and
-- from Last kill below it. If there is no primary target,
-- the box is a single line, action only. No skill
-- description is invented: the context is only GMCP
-- fields already in the plugin, activity + enemy.
-- v1.2 changes, from the full MudForge API AI Guide (2026-10-27):
-- 1. Polling now uses tempTimer(2, ..., true), NOT addTimer.
--    Guide §8 / §18.3: addTimer refuses to start while the world
--    is disconnected, returning "" with a warning, and plugins
--    load before the MUD connects, so an addTimer started in
--    init() usually never runs. tempTimer runs whether or not
--    the world is connected, and its delay is in SECONDS.
-- 2. Partial-packet safety, guide §11: an onGMCPUpdate callback
--    receives ONLY the packet that just arrived, not the
--    accumulated state. v1.1 replaced the whole stored status
--    with each packet, so a partial packet with no enemies
--    field would flash "No targets" until the next poll.
--    Now packets are MERGED, field by field, into the plugin's
--    own status table, so a partial packet updates only the
--    fields it carries and leaves the rest alone.
-- 3. The plugin never modifies a GMCP table, guide §11: the
--    tables getGMCPData / onGMCPUpdate hand out are the
--    client's live store. The merged status table is a copy
--    owned by this plugin; GMCP tables are only read, never
--    written to, and the targets list built for drawing is a
--    fresh list each draw, not a reordered GMCP list.
-- 4. Plugin table now has an id, as in the guide's TL;DR
--    skeleton. The id is stable and unique to this plugin.
--
-- v1.1 change: each target is layered, not one long line.
-- v1.0 put name, percent, shape and PRIMARY on a single line,
-- which clipped at the right edge ("... excellent  PRIM").
-- Now each target is three stacked lines:
--   Line 1: name, plus PRIMARY if it is the primary target
--   Line 2: percent and shape, coloured to match the bar
--   Line 3: the bar itself
-- Nothing on a line is long enough to reach the right edge any
-- more. The widget is taller to fit the stacked rows (380px
-- instead of 240px), and names are truncated with room left for
-- the PRIMARY marker when one is present.
--
-- Data, all from GMCP, no text parsing:
--   Char.Status.enemy     - primary target name (or "")
--   Char.Status.enemypct  - primary target HP %, bucketed
--   Char.Status.enemies   - all combat targets, each:
--                           {name, hp, shape}
--   Char.Status.state     - "idle", "combat", or "resting"
--   Char.Status.activity  - e.g. "Using <skillname>", or ""
--   Char.Status.momentum  - lane-0 momentum, or ""
--   Char.EnemyDeath.name  - last enemy that died in combat
--
-- Icesus-specific handling, from help gmcp:
-- 1. enemypct and enemies[].hp are bucketed to match the in-game
--    shape command: 100, 99, 90, 80, 70, 60, 50, 40, 30, 20, 10, 5.
--    The bar width uses that bucket directly. It is not an exact
--    HP number, and this plugin does not pretend otherwise.
-- 2. enemies[].shape is the matching shape word, in the same
--    order as the buckets: "excellent", "good",
--    "slightly hurt", "moderately hurt", "not good",
--    "severely hurt", "bad", "very bad", "extremely bad",
--    "gravely wounded", "almost dead", "dead meat".
--    The shape is shown on its own line, not converted to a
--    fake exact percent.
-- 3. A name of exactly "Something" is invisibility, not a mob
--    name. It is shown as "Something (unidentified)".
-- 4. When enemies is empty but enemy is set, a single row is
--    built from enemy / enemypct, so a lone target still shows
--    even if the full list has not arrived yet.
-- 5. The primary target (Char.Status.enemy) is marked PRIMARY
--    and drawn first, even if it is not first in enemies[].
--    Other targets follow in the order Icesus sends them.
-- 6. Bars are canvas bars, not HTML binds. HTML setBoundValue
--    only sets text, it cannot set a bar width. Canvas
--    drawRect is the MudForge way to draw a bar, as in the
--    docs' health-bar example.
--
-- Polling, same lesson as the status panel (2026-10-27):
-- getGMCPData("Char.Status") is polled every 2 seconds as well
-- as subscribed to, so the bars fill on load even if no change
-- event fires while the data is static.

plugin = {
  id = "icesus-target",
  name = "Icesus Target",
  version = "1.4.0",
  author = "DaBurgermeista",
  description = "Canvas target bars for fighting enemies, from Icesus Char.Status",
}

local widget = nil
local pollTimerId = nil
local state = {
  status = nil,
  lastKill = nil,
}

local function pctColor(p)
  if p > 50 then return "#00c853" end
  if p > 25 then return "#ffab00" end
  return "#ff1744"
end

local function displayName(name)
  if name == nil or name == "" then return "?" end
  if name == "Something" then return "Something (unidentified)" end
  return name
end

local function truncate(text, maxLen)
  if text == nil then return "" end
  if #text <= maxLen then return text end
  return string.sub(text, 1, maxLen - 3) .. "..."
end

-- Merge a GMCP packet into the plugin's own status table.
-- Never assign the GMCP table itself, and never write into it:
-- guide §11 says those tables are the client's live store.
local function mergeStatus(data)
  if data == nil then return end
  if state.status == nil then state.status = {} end
  for k, v in pairs(data) do state.status[k] = v end
end

local function draw()
  if widget == nil then return end
  setActiveWidget(widget)
  local w = getCanvasWidth()
  local h = getCanvasHeight()
  clear("#0f172a")
  -- Accent left border, matching the HTML panels.
  drawRect(0, 0, 4, h, "#38bdf8")

  local s = state.status
  if s == nil then
    drawText("Waiting for Char.Status...", 14, 28, "#cdd6f4")
    return
  end

  -- Build the target list: primary first, then the rest.
  -- This is a fresh list owned by this draw; the GMCP enemies
  -- list itself is never reordered or modified.
  local targets = {}
  local primaryName = s.enemy or ""
  if s.enemies ~= nil and #s.enemies > 0 then
    for _, e in ipairs(s.enemies) do
      targets[#targets + 1] = e
    end
    -- Move primary to the front if it is not already there.
    if primaryName ~= "" then
      for i, e in ipairs(targets) do
        if e.name == primaryName and i ~= 1 then
          table.remove(targets, i)
          table.insert(targets, 1, e)
          break
        end
      end
    end
  elseif primaryName ~= "" then
    targets[1] = { name = primaryName, hp = s.enemypct or 0, shape = "" }
  end

  local y = 10
  local header = "Targets"
  if s.state == "combat" then
    header = "In combat"
  elseif s.state ~= nil and s.state ~= "" then
    header = "Targets - " .. s.state
  end
  drawText(header, 14, y + 16, "#ffffff")
  y = y + 28

  if #targets == 0 then
    drawText("No targets", 14, y + 16, "#94a3b8")
    y = y + 28
  else
    local maxShown = 5
    local shown = math.min(#targets, maxShown)
    for i = 1, shown do
      local e = targets[i]
      local hp = e.hp or 0
      if hp < 0 then hp = 0 end
      if hp > 100 then hp = 100 end
      local isPrimary = (e.name == primaryName and primaryName ~= "")
      -- Leave room for "  PRIMARY" on the name line when present,
      -- so the name line itself never reaches the right edge.
      local maxNameLen = 36
      if isPrimary then maxNameLen = 28 end
      local nameLine = truncate(displayName(e.name), maxNameLen)
      if isPrimary then nameLine = nameLine .. "  PRIMARY" end
      drawText(nameLine, 14, y + 13, "#e2e8f0")
      y = y + 16
      -- Percent and shape on their own line, coloured like the bar.
      local infoLine = tostring(hp) .. "%"
      if e.shape ~= nil and e.shape ~= "" then
        infoLine = infoLine .. "  " .. e.shape
      end
      drawText(infoLine, 14, y + 13, pctColor(hp))
      y = y + 16
      -- Bar on its own line, rounded, v1.4.
      local barX = 14
      local barW = w - barX - 14
      drawRoundedRect(barX, y, barW, 14, 6, "#333333")
      if hp > 0 then
        local fillColor = pctColor(hp)
        if e.shape == "dead meat" then fillColor = "#64748b" end
        local fillW = math.floor(barW * hp / 100)
        if fillW > 0 then
          drawRoundedRect(barX, y, fillW, 14, math.min(6, math.floor(fillW / 2)), fillColor)
        end
      end
      y = y + 22
    end
    if #targets > maxShown then
      drawText("and " .. tostring(#targets - maxShown) .. " more", 14, y + 14, "#94a3b8")
      y = y + 22
    end
  end

  -- Footer: momentum / action box / last kill, only when present.
  y = y + 4
  if s.momentum ~= nil and s.momentum ~= "" then
    drawText("Momentum: " .. truncate(s.momentum, 28), 14, y + 14, "#facc15")
    y = y + 20
  end
  -- Action box, v1.3: bordered, with context. Canvas has no
  -- stroke-only rectangle, so the border is an accent-filled
  -- outer rect with a lighter inner rect on top, leaving a
  -- 2px frame. Inner text is truncated to 34 chars to fit
  -- the box padding (box width is widget width - 28, minus
  -- 10px padding each side).
  if s.activity ~= nil and s.activity ~= "" then
    local actionLine = "Action: " .. s.activity
    local targetLine = nil
    if primaryName ~= "" then
      targetLine = "Target: " .. displayName(primaryName)
    end
    local boxH = 32
    if targetLine ~= nil then boxH = 52 end
    local boxX = 14
    local boxW = w - boxX - 14
    drawRoundedRect(boxX, y, boxW, boxH, 8, "#38bdf8")
    drawRoundedRect(boxX + 2, y + 2, boxW - 4, boxH - 4, 6, "#1e293b")
    drawText(truncate(actionLine, 34), boxX + 10, y + 16, "#7dd3fc")
    if targetLine ~= nil then
      drawText(truncate(targetLine, 34), boxX + 10, y + 36, "#e2e8f0")
    end
    y = y + boxH + 8
  end
  if state.lastKill ~= nil then
    drawText("Last kill: " .. truncate(displayName(state.lastKill), 28), 14, y + 14, "#94a3b8")
  end
end

local function updateStatus(data)
  mergeStatus(data)
  draw()
end

local function pollStatus()
  local s = getGMCPData("Char.Status")
  if s ~= nil then mergeStatus(s) end
  draw()
end

function init()
  widget = createWidget({
    type = "canvas",
    name = "icesus-target",
    title = "Target",
    position = { x = 340, y = 120 },
    size = { width = 320, height = 380 },
  })

  registerWidgetEvent(widget, "resize", function() draw() end)

  onGMCPUpdate("Char.Status", updateStatus)

  onGMCPUpdate("Char.EnemyDeath", function(data)
    if data ~= nil and data.name ~= nil then
      state.lastKill = data.name
      draw()
    end
  end)

  -- Polling fallback, every 2 seconds, same as the Icesus heartbeat.
  -- tempTimer, not addTimer: addTimer refuses to start while
  -- disconnected (guide §8 / §18.3), and plugins load before
  -- the MUD connects. tempTimer's delay is in seconds.
  pollTimerId = tempTimer(2, pollStatus, true)
  pollStatus()
end

function cleanup()
  if pollTimerId then killTimer(pollTimerId) end
end
