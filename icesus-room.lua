-- Icesus Room for MudForge, v1.7
-- v1.7 change: reformatted to flow in a narrow column.
-- Aaron moved the Room widget to the center column
-- (2026-10-27), where it is only about 320px wide, and
-- the old layout clipped: the header was one nowrap row,
-- so the area was cut to "Ra", and exits/detail were
-- nowrap with ellipsis, so long lists were cut off.
-- New layout, for narrow and wide alike:
--   Line 1: SAFE/NOT SAFE pill + room name. The name
--     flexes and wraps inside its remaining width, it
--     no longer pushes the area off the right edge.
--   Line 2: area on its own line, accent colour, like a
--     subtitle. It is never truncated now.
--   Line 3: exits, wrapping to a second line if needed,
--     instead of ellipsis cutting exits off.
--   Line 4: detail, wrapping instead of ellipsis.
-- Widget size is now 340px wide / 130px tall in code,
-- to match a center-column placement and the wrapped
-- lines. The v1.6 runtime height override to 64px is
-- removed, because wrapped content needs more than
-- 64px in a narrow column, and forcing 64px would have
-- made it scroll instead of flow. While docked, the
-- tile height is still the layout's, not the code's.
-- A room bar to sit below the terminal and above MudForge's
-- bottom bars, mirroring Mudlet's bottom room line.
-- Text only, no bars.
--
-- v1.2 changes, from the full MudForge API AI Guide (2026-10-27):
-- 1. Polling now uses tempTimer(2, ..., true), NOT addTimer.
--    Guide §8 / §18.3: addTimer refuses to start while the world
--    is disconnected, returning "" with a warning, and plugins
--    load before the MUD connects, so an addTimer started in
--    init() usually never runs. tempTimer runs whether or not
--    the world is connected, and its delay is in SECONDS.
-- 2. Partial-packet safety, guide §11: an onGMCPUpdate callback
--    receives ONLY the packet that just arrived. Safe is now
--    only updated when the packet actually carries it, instead
--    of defaulting a packet with no safe field to NOT SAFE.
--    The detail line is only rebuilt when the packet carries
--    at least one detail field, so a partial packet with only
--    a name/area does not wipe the detail line. A full move
--    packet carries detail fields, so it still rebuilds
--    correctly, including omitting coords when the new room
--    is indoors and the packet omits them.
-- 3. Coords are read via ipairs, not coords[1]/[2]/[3].
--    Guide §11: GMCP JSON lists are 0-based JavaScript arrays,
--    and ipairs is the correct reader. Indexing from 1 would
--    have shown y, z, 0 instead of x, y, z for outworld rooms.
-- 4. A destination that arrives as nil is now shown as " (?)"
--    like a destination of 0, not as a known destination.
-- 5. Plugin table now has an id, as in the guide's TL;DR
--    skeleton. The id is stable and unique to this plugin.
--
-- v1.1 visual redesign (2026-10-27, after the first screenshot):
-- - Room name is large and bold, area is in accent colour, not
--   one flat line of the same colour and weight.
-- - Safe is a small pill in the header, not a "Safe: No" item
--   buried in the detail line.
-- - Inn is only shown when the room actually is an inn. A
--   "Inn: -" for every non-inn room was noise.
-- - Exits are in compass order (north, northeast, east,
--   southeast, south, southwest, west, northwest, up, down,
--   in, out, then anything else alphabetically), not
--   alphabetical, so they read like the game's own exit list.
-- - Detail line uses middle dots, muted colour, and a smaller
--   font, so it does not compete with the name and exits.
-- - Card styling: dark gradient background, accent left border,
--   rounded corners, tighter padding, so it reads as one bar
--   instead of three loose lines on a flat background.
--
-- Fields shown, all from Room.Info (version 2):
--   name, area, exits, id, coords, safe, inn, outside,
--   terrain, paths
--
-- Icesus-specific handling, from help gmcp:
-- 1. exits is an object: direction -> destination room id
--    (8-char hash), or 0 if the destination is hidden (shrouded)
--    or not statically known (dynamic / scripted exit).
--    A direction with destination 0 is shown with a " (?)"
--    marker, so it is not mistaken for a known destination.
--    Hidden exits and locked doors are omitted entirely by the
--    server, so they simply do not appear here.
-- 2. Mapper-hostile rooms (death pipeline, chronomancer void
--    rifts, query_gmcp_no_map rooms) ship with id="" and
--    exits={} and no coords. Those are shown as "Unmappable
--    room" instead of an empty exits list. The name and area
--    still show, exactly as Icesus's own location bar does.
-- 3. coords is [x, y, z] and is only sent for outworld rooms.
--    It is omitted indoors, so it is omitted here too when absent.
-- 4. terrain is only sent when it is one of the named terrains
--    (road, path, water, swamp, mountain, plains, forest, ice,
--    badlands, ashlands) or, on the world map, a raw landmark
--    character like "?" for a mine entrance. Indoor rooms, other
--    planes and mapper-hostile rooms omit it.
-- 5. paths is outworld only and omitted when none. It maps
--    direction -> "road" or "path".
-- 6. safe / inn / outside are 1/0. A nil/null (as seen for inn
--    on one non-inn room in the 2026-10-27 dump) is treated as
--    "not an inn" and omitted, rather than shown as "-".
-- 7. What is NOT here, on purpose: room description text, items
--    and NPCs in the room. Room.Info does not carry those, they
--    only exist in the main terminal output.
--
-- Polling, same lesson as the status panel (2026-10-27):
-- getGMCPData("Room.Info") is polled every 2 seconds as well as
-- subscribed to, so the bar fills on load even if no move event
-- fires while it is open.

plugin = {
  id = "icesus-room",
  name = "Icesus Room",
  version = "1.7.0",
  author = "DaBurgermeista",
  description = "A room bar showing all Icesus Room.Info fields, for below the terminal and above the bottom bars",
}

local widgetId = nil
local pollTimerId = nil

-- Compass order, then up/down/in/out, then anything else.
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

  -- Only update safe when the packet carries it. A packet with
  -- no safe field must not default to NOT SAFE.
  if data.safe ~= nil then
    if data.safe == 1 then
      setBoundValue(widgetId, "safebadge", "SAFE")
    else
      setBoundValue(widgetId, "safebadge", "NOT SAFE")
    end
  end

  -- Exits, or the unmappable-room note.
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

  -- Detail line: no Safe duplicate (it is the pill above), no
  -- Inn unless the room actually is one. Only rebuild it when
  -- the packet carries at least one detail field, so a partial
  -- packet with only a name/area does not wipe it.
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
      -- GMCP lists are 0-based host arrays (guide §11).
      -- ipairs is the correct reader; coords[1]/[2]/[3]
      -- would have shown y, z, 0 instead of x, y, z.
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
    name = "icesus-room",
    title = "Room",
    position = { x = 10, y = 600 },
    size = { width = 340, height = 130 },
  })

  -- Hide the title bar, v1.5. setWidgetAppearance replaces
  -- the player's own choice for these fields, unlike a
  -- creation-time appearance default, so this actually
  -- applies to the already-placed widget on reload.
  setWidgetAppearance(widgetId, {
    showTitleBar = false,
    autoHideSettingsCog = true,
  })

  -- Set the content ONCE. Elements with data-mud-bind receive
  -- values later via setBoundValue() without replacing the DOM.
  -- Narrow-column layout since v1.7: the room name and area
  -- flow instead of truncating, and exits/detail wrap.
  -- Server values are never concatenated into this markup;
  -- they only arrive via setBoundValue, as bound text.
  setWidgetProperty(widgetId, "content", [[
    <style>
      body {
        font: 13px/1.25 system-ui, sans-serif;
        color: #eee;
        margin: 0;
        background: linear-gradient(90deg, #1e293b, #0f172a);
        border-left: 4px solid #38bdf8;
        border-radius: 8px;
        padding: 4px 10px;
      }
      .head {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 8px;
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
        font-size: 15px;
        font-weight: 700;
        color: #ffffff;
        flex: 1 1 auto;
        min-width: 0;
      }
      .area {
        font-size: 13px;
        font-weight: 600;
        color: #7dd3fc;
        flex-basis: 100%;
      }
      .exits {
        padding-top: 2px;
        font-size: 12px;
        line-height: 1.4;
      }
      .exits .label { color: #94a3b8; margin-right: 6px; }
      .exits .list { color: #facc15; font-weight: 600; }
      .extra {
        padding-top: 2px;
        font-size: 10px;
        color: #94a3b8;
        line-height: 1.4;
      }
    </style>
    <div class="head">
      <span class="badge" data-mud-bind="safebadge"></span>
      <span class="name" data-mud-bind="roomname">?</span>
      <span class="area" data-mud-bind="roomarea">?</span>
    </div>
    <div class="exits"><span class="label">Exits:</span><span class="list" data-mud-bind="exits">?</span></div>
    <div class="extra"><span data-mud-bind="roomextra">?</span></div>
  ]])

  onGMCPUpdate("Room.Info", updateRoom)

  -- Polling fallback, every 2 seconds. This is what fills the
  -- bar on load if no move event fires while it is open. It
  -- sends nothing to the game, it only reads local cached
  -- GMCP data. tempTimer, not addTimer: addTimer refuses to
  -- start while disconnected (guide §8 / §18.3), and plugins
  -- load before the MUD connects.
  pollTimerId = tempTimer(2, pollRoom, true)
  pollRoom()
end

function cleanup()
  if pollTimerId then killTimer(pollTimerId) end
end
