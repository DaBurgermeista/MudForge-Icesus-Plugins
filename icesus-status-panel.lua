-- Icesus Status Panel for MudForge, v1.9
-- Built on the default MudForge HTML scaffolding. Text only, no bars:
-- MudForge's built-in bottom bars already show HP, SP, EP, PSP and
-- EXP, so this panel does not duplicate them.
--
-- v1.9 changes (2026-10-27):
-- Rows whose value is "-" are now HIDDEN, not shown as "-".
-- They appear automatically when they gain a real value, and
-- hide again when they go back to "-".
-- How, per the guide §4: setBoundValue cannot hide an element,
-- it only sets text, so each hideable row also carries a
-- style bind, data-mud-bind-style="display:<rowKey>", and the
-- update functions set that key to "none" or "flex" alongside
-- the value. The DOM is never rebuilt, so no timers or
-- listeners are lost, which is the guide's reason to prefer
-- reactive binding over rewriting content.
-- Rows that hide this way:
--   Fury, Vitae - for Kalthor these are always "-", because
--     he has neither resource, so they will simply stay
--     hidden, which is the point.
--   Casting, Effects, Wounds, Cooldowns - hidden while idle /
--     unaffected / unwounded / no cooldowns, and they appear
--     as soon as a spell is casting, an effect lands, a wound
--     is taken, or a cooldown starts.
-- Rows that never hide: header, State, XP / next level,
-- Next advancement, Weight, and the Wealth section. Those
-- always have a meaningful value, even if it is "?" before
-- the first GMCP packet arrives.
-- A value of 0 is NOT "-": a guild resource present and 0
-- means "has it and it is empty", so a Fury/Vitae row with
-- 0 shows, it does not hide.
-- Initial row style is display:none in the markup, so the
-- rows do not flash as "-" on load before the first poll
-- sets them to "none" or "flex".
--
-- v1.8 changes (2026-10-27, from Aaron's screenshot):
-- 1. Target row removed. The Target plugin covers primary
--    target, enemies, bars and last kill, so a Target row
--    here was duplication, same as Room info was in v1.6.
-- 2. Advancement row added, from Char.Status.tna.
--    IMPORTANT: GMCP does NOT carry a total advancement
--    points count. There is no "advancement points total"
--    field in Char.Vitals, Char.Status, Char.Base or
--    Char.Maxstats in the help gmcp file. What GMCP does
--    carry is tna: "Experience cost of next advancement
--    point". So this row shows that cost, labelled
--    "Next advancement", NOT a total. In Aaron's 21:02
--    screenshot the in-game advance command gave 2 points
--    for 554 and 559 XP, total 4, and XP fell 1301 -> 188
--    (1301 - 554 - 559 = 188). That total of 4 comes only
--    from the advance command's text output, not from GMCP,
--    so it cannot be shown here from GMCP alone. A total
--    counter would need to parse that text, which is a
--    separate feature, not a GMCP row.
--
-- v1.7 changes, from the full MudForge API AI Guide (2026-10-27):
-- 1. Polling now uses tempTimer(2, ..., true), NOT addTimer.
--    Guide §8 / §18.3: addTimer refuses to start while the world
--    is disconnected, returning "" with a warning, and plugins
--    load before the MUD connects, so an addTimer started in
--    init() usually never runs. tempTimer runs whether or not
--    the world is connected, and its delay is in SECONDS.
-- 2. Partial-packet safety, guide §11: an onGMCPUpdate callback
--    receives ONLY the packet that just arrived, not the
--    accumulated state, so a field absent from a packet must NOT
--    clear the display. Effects, wounds, casting and
--    cooldowns now only update when their field is actually
--    present in the packet. A packet that explicitly sends
--    an empty effects/wounds/cooldowns list still clears to
--    "-" (and hides the row), as it should. The 2-second poll
--    uses accumulated getGMCPData, where those fields are
--    present as an empty list when they are empty, so the
--    poll still fills "-" correctly on load.
-- 3. Fury / vitae: the poll (accumulated data) treats absent as
--    "cannot have it" and shows "-" (hidden), while a handler
--    packet treats absent as "unknown" and leaves the value
--    alone. That stops a partial Vitals packet flickering
--    Fury to "-".
-- 4. Effects are joined via ipairs, not table.concat on the
--    GMCP list directly. Guide §11: GMCP JSON lists are
--    0-based JavaScript arrays, and ipairs is the correct
--    reader for them; indexing / concatenating from 1 would
--    skip the first effect.
-- 5. Plugin table now has an id, as in the guide's TL;DR
--    skeleton. The id is stable and unique to this plugin.
--
-- v1.6 change: Room info removed entirely. The Room plugin now
-- covers name, area, exits, safe, inn, outside, terrain, coords,
-- paths and ID, so the Status panel no longer duplicates it.
--
-- Icesus-specific corrections kept:
-- 1. fury and vitae: absent means "cannot have it", present and 0
--    means "has it and it is empty". Absent shows as "-" (hidden),
--    0 as "0" (shown).
-- 2. Char.Status omits money, bank and dfavor during combat. Those
--    are only overwritten when the new packet actually has them.
-- 3. Char.Casting gives progress and cps, but no total, so no
--    casting percent is faked here.
-- 4. Polling, not just handlers: the 2026-10-27 debug for Kalthor
--    proved the cache has Char data while handlers/binds did not
--    push it while static, so pollCharData runs every 2 seconds.

plugin = {
  id = "icesus-status-panel",
  name = "Icesus Status Panel",
  version = "1.9.0",
  author = "DaBurgermeista",
  description = "An HTML status panel bound to Icesus GMCP values",
}

local widgetId = nil
local pollTimerId = nil

-- Last known values for fields Icesus omits in combat.
local lastMoney = nil
local lastBank = nil
local lastDfavor = nil

local function joinOrDash(list, sep)
  if list == nil then return "-" end
  -- Build a Lua list via ipairs first. GMCP lists are 0-based
  -- host arrays (guide §11), and ipairs is the correct reader;
  -- table.concat on the host list directly would skip its
  -- first element.
  local parts = {}
  for _, v in ipairs(list) do parts[#parts + 1] = tostring(v) end
  if #parts == 0 then return "-" end
  return table.concat(parts, sep or ", ")
end

-- Set a hideable row's value and its visibility together.
-- value "-" hides the row, any other value shows it.
local function setRow(rowKey, valueKey, value)
  setBoundValue(widgetId, valueKey, value)
  if value == "-" then
    setBoundValue(widgetId, rowKey, "none")
  else
    setBoundValue(widgetId, rowKey, "flex")
  end
end

local function updateVitals(data, fromPoll)
  if widgetId == nil or data == nil then return end
  -- No HP/SP/EP/PSP here on purpose: MudForge's bottom bars
  -- show those. Only guild resources that the bottom bars do not
  -- show are handled here.
  if data.fury ~= nil then
    setRow("furyRow", "fury", tostring(data.fury))
  elseif fromPoll then
    -- Accumulated data, so absent really means "cannot have it".
    setRow("furyRow", "fury", "-")
  end
  if data.vitae ~= nil then
    setRow("vitaeRow", "vitae", tostring(data.vitae))
  elseif fromPoll then
    setRow("vitaeRow", "vitae", "-")
  end
end

local function updateBase(data)
  if widgetId == nil or data == nil then return end
  if data.name ~= nil then setBoundValue(widgetId, "name", data.name) end
  if data.class ~= nil then setBoundValue(widgetId, "class", data.class) end
end

local function updateStatus(data)
  if widgetId == nil or data == nil then return end
  if data.level ~= nil then setBoundValue(widgetId, "level", "Lv " .. tostring(data.level)) end

  if data.state ~= nil then
    local stateText = data.state
    if data.pos ~= nil and data.pos ~= "" then
      stateText = stateText .. " / " .. data.pos
    end
    setBoundValue(widgetId, "state", stateText)
  end

  if data.exp ~= nil and data.tnl ~= nil then
    local xpText = tostring(data.exp) .. " / " .. tostring(data.tnl)
    if data.tnl > 0 then
      xpText = xpText .. " (" .. tostring(math.floor(data.exp / data.tnl * 100)) .. "%)"
    end
    setBoundValue(widgetId, "xp", xpText)
  end

  -- Next advancement point cost, from Char.Status.tna.
  -- This is a COST, not a total. GMCP has no total
  -- advancement points field (see the header note).
  -- Only update when the packet actually carries tna.
  if data.tna ~= nil then
    setBoundValue(widgetId, "tna", tostring(data.tna) .. " XP")
  end

  if data.carry_wt ~= nil and data.max_wt ~= nil then
    local wtText = tostring(data.carry_wt) .. " / " .. tostring(data.max_wt)
    if data.max_wt > 0 then
      wtText = wtText .. " (" .. tostring(math.floor(data.carry_wt / data.max_wt * 100)) .. "%)"
    end
    setBoundValue(widgetId, "weight", wtText)
  end

  -- No Target row in v1.8 on purpose: the Target plugin
  -- covers it. No enemy bind is set here any more.

  if data.effects ~= nil then
    setRow("effectsRow", "effects", joinOrDash(data.effects))
  end

  if data.wounds ~= nil then
    if #data.wounds > 0 then
      local parts = {}
      for _, w in ipairs(data.wounds) do
        parts[#parts + 1] = (w.slot or "?") .. " (" .. (w.severity or "?") .. ")"
      end
      setRow("woundsRow", "wounds", table.concat(parts, ", "))
    else
      setRow("woundsRow", "wounds", "-")
    end
  end

  -- Only overwrite when present. Icesus omits these in combat.
  if data.money ~= nil then
    lastMoney = data.money
    setBoundValue(widgetId, "money", tostring(data.money))
  end
  if data.bank ~= nil then
    lastBank = data.bank
    setBoundValue(widgetId, "bank", tostring(data.bank))
  end
  if data.dfavor ~= nil then
    lastDfavor = data.dfavor
    setBoundValue(widgetId, "dfavor", tostring(data.dfavor))
  end
end

local function updateCasting(data)
  if widgetId == nil or data == nil then return end
  if data.active ~= nil then
    if data.active == 1 and data.spell ~= nil then
      setRow("castingRow", "casting", data.spell)
    else
      setRow("castingRow", "casting", "-")
    end
  end
end

local function updateCooldowns(data)
  if widgetId == nil or data == nil then return end
  if data.cooldowns ~= nil then
    if #data.cooldowns > 0 then
      local parts = {}
      for _, cd in ipairs(data.cooldowns) do
        -- total == 0 means variable duration, so only show remaining.
        parts[#parts + 1] = (cd.name or "?") .. " " .. tostring(cd.remaining or "?") .. "s"
      end
      setRow("cooldownsRow", "cooldowns", table.concat(parts, ", "))
    else
      setRow("cooldownsRow", "cooldowns", "-")
    end
  end
end

local function pollCharData()
  local v = getGMCPData("Char.Vitals")
  if v ~= nil then updateVitals(v, true) end
  local s = getGMCPData("Char.Status")
  if s ~= nil then updateStatus(s) end
  local b = getGMCPData("Char.Base")
  if b ~= nil then updateBase(b) end
  local c = getGMCPData("Char.Casting")
  if c ~= nil then updateCasting(c) end
  local cd = getGMCPData("Char.Cooldowns")
  if cd ~= nil then updateCooldowns(cd) end
end

function init()
  widgetId = createWidget({
    type = "html",
    name = "icesus-status-panel",
    title = "Icesus Status",
    position = { x = 40, y = 120 },
    size = { width = 280, height = 360 },
  })

  -- Set the content ONCE. Elements with data-mud-bind receive values
  -- later via setBoundValue() without replacing the DOM.
  -- Theme matches the Room plugin v1.1: dark gradient card,
  -- accent left border, rounded corners, muted labels, light
  -- values, accent section headers.
  -- Server values are never concatenated into this markup.
  -- They only arrive via setBoundValue, as bound text, which is
  -- the guide's safe path for MUD text in an HTML widget.
  -- Hideable rows start with style="display:none" and carry a
  -- data-mud-bind-style="display:<rowKey>" so setRow can show
  -- or hide them without rebuilding the document.
  setWidgetProperty(widgetId, "content", [[
    <style>
      body {
        font: 13px/1.4 system-ui, sans-serif;
        color: #eee;
        margin: 0;
        background: linear-gradient(90deg, #1e293b, #0f172a);
        border-left: 4px solid #38bdf8;
        border-radius: 8px;
        padding: 10px 14px;
      }
      .head {
        display: flex;
        align-items: center;
        gap: 10px;
        padding-bottom: 6px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .name { font-size: 17px; font-weight: 700; color: #ffffff; }
      .guild { font-size: 13px; font-weight: 600; color: #7dd3fc; }
      .pill {
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.05em;
        background: #334155;
        color: #e2e8f0;
        padding: 2px 7px;
        border-radius: 999px;
        flex-shrink: 0;
      }
      .row { display: flex; justify-content: space-between; gap: 8px; padding: 3px 0; }
      .row span:first-child { color: #94a3b8; }
      .v { font-weight: 600; color: #e2e8f0; text-align: right; }
      .sec {
        margin-top: 8px;
        padding-top: 6px;
        border-top: 1px solid #334155;
        color: #7dd3fc;
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
    </style>
    <div class="head">
      <span class="name" data-mud-bind="name">?</span>
      <span class="guild" data-mud-bind="class">?</span>
      <span class="pill" data-mud-bind="level">?</span>
    </div>
    <div class="row" style="display:none" data-mud-bind-style="display:furyRow"><span>Fury</span><span class="v" data-mud-bind="fury">?</span></div>
    <div class="row" style="display:none" data-mud-bind-style="display:vitaeRow"><span>Vitae</span><span class="v" data-mud-bind="vitae">?</span></div>
    <div class="row"><span>State</span><span class="v" data-mud-bind="state">?</span></div>
    <div class="row"><span>XP / next level</span><span class="v" data-mud-bind="xp">?</span></div>
    <div class="row"><span>Next advancement</span><span class="v" data-mud-bind="tna">?</span></div>
    <div class="row"><span>Weight</span><span class="v" data-mud-bind="weight">?</span></div>
    <div class="row" style="display:none" data-mud-bind-style="display:castingRow"><span>Casting</span><span class="v" data-mud-bind="casting">-</span></div>
    <div class="row" style="display:none" data-mud-bind-style="display:effectsRow"><span>Effects</span><span class="v" data-mud-bind="effects">-</span></div>
    <div class="row" style="display:none" data-mud-bind-style="display:woundsRow"><span>Wounds</span><span class="v" data-mud-bind="wounds">-</span></div>
    <div class="row" style="display:none" data-mud-bind-style="display:cooldownsRow"><span>Cooldowns</span><span class="v" data-mud-bind="cooldowns">-</span></div>
    <div class="sec">Wealth</div>
    <div class="row"><span>Silver</span><span class="v" data-mud-bind="money">?</span></div>
    <div class="row"><span>Bank</span><span class="v" data-mud-bind="bank">?</span></div>
    <div class="row"><span>Divine favors</span><span class="v" data-mud-bind="dfavor">?</span></div>
  ]])

  -- No direct binds for HP/SP/EP/PSP: those are shown by
  -- MudForge's bottom bars, and duplicating them here was
  -- the redundancy removed in v1.3.

  onGMCPUpdate("Char.Vitals", updateVitals)
  onGMCPUpdate("Char.Base", updateBase)
  onGMCPUpdate("Char.Status", updateStatus)
  onGMCPUpdate("Char.Casting", updateCasting)
  onGMCPUpdate("Char.Cooldowns", updateCooldowns)

  -- Polling fallback, every 2 seconds, same as the Icesus heartbeat.
  -- tempTimer, not addTimer: addTimer refuses to start while the
  -- world is disconnected (guide §8 / §18.3), and plugins load
  -- before the MUD connects. tempTimer's delay is in seconds.
  pollTimerId = tempTimer(2, pollCharData, true)
  pollCharData()
end

function cleanup()
  if pollTimerId then killTimer(pollTimerId) end
end
