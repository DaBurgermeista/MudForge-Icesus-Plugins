-- Icesus Room Line for MudForge, v1.0
-- A separate floating overlay variant, NOT a replacement
-- for icesus-room.lua v1.7. Load this to try the overlay
-- idea, and disable the old Room plugin while you test
-- it, or you will see two room bars. Polling both is
-- harmless (read-only), it is just duplicate display.
--
-- Why this exists (2026-10-27): the center-column Room
-- card kept its tile height no matter how small the
-- text got, because MudForge's docked layout owns tile
-- height, not code. A floating widget is different: its
-- height is its height. This bar is 900 x 56 in code,
-- two rows only, no title bar, so when floated it is
-- actually slim, instead of a tall tile with blank space.
--
-- Placement:
--   1. Load this plugin, disable icesus-room v1.7.
--   2. Shift + drop the Room Line widget out of its
--      tile to float it.
--   3. Drag it to the bottom of the terminal, just
--      above MudForge's built-in bottom bars, and drag
--      its width to match the terminal.
--   4. If the hidden title bar makes grabbing it hard,
--      hover the top edge for the cog, turn the title
--      bar back on, place it, then turn it off again.
-- Trade-off, stated plainly: it floats over the
-- terminal, so it covers the bottom line or two of
-- terminal text where it sits. That is the price of
-- a height the layout cannot inflate.
--
-- Layout, two rows, wide-bar style:
--   Row 1: SAFE/NOT SAFE pill + room name + area.
--   Row 2: exits (yellow, compass-ordered) + detail
--     (muted: indoors/outdoors, inn, terrain, coords,
--     paths, ID). Both rows are nowrap with ellipsis,
--     so in a wide terminal-width bar nothing is cut,
--     and in a narrow bar the right-hand end truncates
--     first, exits before detail in row 2.
-- This is the Mudlet bottom-room-line idea: a bar,
-- not a card, and it does not try to flow in a narrow
-- column like v1.7 does. If you want the narrow-column
-- card back, reload icesus-room.lua v1.7.
--
-- GMCP handling is identical to icesus-room.lua:
-- tempTimer polling every 2 seconds (not addTimer,
-- guide §8 / §18.3, plugins load before connecting),
-- partial-packet guards for safe and detail (guide
-- §11), coords read via ipairs (0-based host lists),
-- destination 0 / nil shown as " (?)", id="" rooms
-- shown as unmappable, inn only when true, server
-- values only via setBoundValue, never concatenated
-- into markup.

plugin = {
  id = "icesus-room-line",
  name = "Icesus Room Line",
  version = "1.0.0",
  author = "DaBurgermeista",
  description = "A floating two-row room overlay bar, for the bottom of the terminal, above the bottom bars",
}

local widgetId = nil
local pollTimerId = nil

local exitOrder = {
  north = 1, northeast = 2, east = 3, southeast = 4,
  south = 5, southwest = 6, west = 7, northwest = 8,
  up = 9, down = 10, ["in"] = 11, out = 12,
}

local function sortedExits(exits)
  local dirs = {}
  for dir, _dest in pairs(exits) do dirs[#dirs + 1] = dir end
  table.sort(dirs, function(a, b)
    local oa = exitOrder[a] or 99
    local ob = exitOrder[b] or 99
    if oa ~= ob then return oa < ob end
    return a < b
  end)
  return dirs
end

local function sortedKeys(t)
  local keys = {}
  if t ~= nil then
    for k, _v in pairs(t) do keys[#keys + 1] = k end
  end
  table.sort(keys)
  return keys
end

local function updateRoom(data)
  if widgetId == nil or data == nil then return end

  if data.name ~= nil then setBoundValue(widgetId, "roomname", data.name) end
  if data.area ~= nil then setBoundValue(widgetId, "roomarea", data.area) end

  if data.safe ~= nil then
    if data.safe == 1 then
      setBoundValue(widgetId, "safebadge", "SAFE")
    else
      setBoundValue(widgetId, "safebadge", "NOT SAFE")
    end
  end

  if data.id ~= nil and data.id == "" then
    setBoundValue(widgetId, "exits", "Unmappable room - no exits recorded (maze / void)")
  elseif data.exits ~= nil then
    local dirs = sortedExits(data.exits)
    if #dirs == 0 then
      setBoundValue(widgetId, "exits", "none")
    else
      local parts = {}
      for _, dir in ipairs(dirs) do
        local dest = data.exits[dir]
        if dest == 0 or dest == nil then
          parts[#parts + 1] = dir .. " (?)"
        else
          parts[#parts + 1] = dir
        end
      end
      setBoundValue(widgetId, "exits", table.concat(parts, ", "))
    end
  end

  local hasDetail = data.outside ~= nil or data.inn ~= nil
    or data.terrain ~= nil or data.coords ~= nil
    or data.paths ~= nil or data.id ~= nil
  if hasDetail then
    local extra = {}
    if data.outside ~= nil then
      if data.outside == 1 then
        extra[#extra + 1] = "Outdoors"
      else
        extra[#extra + 1] = "Indoors"
      end
    end
    if data.inn == 1 then
      extra[#extra + 1] = "Inn"
    end
    if data.terrain ~= nil and data.terrain ~= "" then
      extra[#extra + 1] = "Terrain: " .. data.terrain
    end
    if data.coords ~= nil then
      local coordParts = {}
      for _, v in ipairs(data.coords) do coordParts[#coordParts + 1] = tostring(v) end
      if #coordParts >= 2 then
        extra[#extra + 1] = "Coords: " .. table.concat(coordParts, ", ")
      end
    end
    if data.paths ~= nil then
      local pathDirs = sortedKeys(data.paths)
      if #pathDirs > 0 then
        local pathParts = {}
        for _, dir in ipairs(pathDirs) do
          pathParts[#pathParts + 1] = dir .. " (" .. tostring(data.paths[dir]) .. ")"
        end
        extra[#extra + 1] = "Paths: " .. table.concat(pathParts, ", ")
      end
    end
    if data.id ~= nil and data.id ~= "" then
      extra[#extra + 1] = "ID: " .. data.id
    end
    setBoundValue(widgetId, "roomextra", table.concat(extra, "  ·  "))
  end
end

local function pollRoom()
  local r = getGMCPData("Room.Info")
  if r ~= nil then updateRoom(r) end
end

function init()
  widgetId = createWidget({
    type = "html",
    name = "icesus-room-line",
    title = "Room Line",
    position = { x = 10, y = 700 },
    size = { width = 900, height = 56 },
  })

  setWidgetAppearance(widgetId, {
    showTitleBar = false,
    autoHideSettingsCog = true,
  })

  setWidgetProperty(widgetId, "content", [[
    <style>
      body {
        font: 13px/1.3 system-ui, sans-serif;
        color: #eee;
        margin: 0;
        background: linear-gradient(90deg, #1e293b, #0f172a);
        border-left: 4px solid #38bdf8;
        border-radius: 8px;
        padding: 4px 10px;
      }
      .row1, .row2 {
        display: flex;
        align-items: center;
        gap: 8px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .badge {
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.05em;
        background: #334155;
        color: #e2e8f0;
        padding: 2px 7px;
        border-radius: 999px;
        flex-shrink: 0;
      }
      .name {
        font-size: 14px;
        font-weight: 700;
        color: #ffffff;
        flex-shrink: 0;
      }
      .area {
        font-size: 13px;
        font-weight: 600;
        color: #7dd3fc;
        flex-shrink: 0;
      }
      .row2 { padding-top: 1px; font-size: 12px; }
      .row2 .label { color: #94a3b8; flex-shrink: 0; }
      .row2 .list { color: #facc15; font-weight: 600; flex-shrink: 0; }
      .row2 .sep { color: #94a3b8; flex-shrink: 0; }
      .row2 .extra { color: #94a3b8; font-size: 10px; }
    </style>
    <div class="row1">
      <span class="badge" data-mud-bind="safebadge"></span>
      <span class="name" data-mud-bind="roomname">?</span>
      <span class="area" data-mud-bind="roomarea">?</span>
    </div>
    <div class="row2">
      <span class="label">Exits:</span>
      <span class="list" data-mud-bind="exits">?</span>
      <span class="sep">·</span>
      <span class="extra" data-mud-bind="roomextra">?</span>
    </div>
  ]])

  onGMCPUpdate("Room.Info", updateRoom)

  pollTimerId = tempTimer(2, pollRoom, true)
  pollRoom()
end

function cleanup()
  if pollTimerId then killTimer(pollTimerId) end
end
