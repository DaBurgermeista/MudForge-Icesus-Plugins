-- Icesus GMCP Debug for MudForge, v1.1
-- v1.1 change, from the full MudForge API AI Guide: the 10-second
-- one-shot poll now uses tempTimer(10, ...) instead of
-- addTimer(10000, ...). addTimer refuses to start while the
-- world is disconnected (guide §8 / §18.3); tempTimer runs
-- either way, and its delay is in seconds. Plugin table also
-- gains an id, as in the guide's TL;DR skeleton.
-- Temporary diagnostic plugin. Disable or remove it once you know
-- which of these is true, because the Char handlers will print
-- every heartbeat (about every 2 seconds) while it is on.
--
-- What it tells you:
-- 1. If "[GMCP update] Char.Vitals" prints, MudForge IS delivering
--    Char packets and the problem is in the status panel, not delivery.
-- 2. If only Room.Info prints, MudForge is not delivering Char packets
--    to plugins at all, even though the server is sending Room.Info.
-- 3. /gmcpdump tells you whether MudForge has Char data cached even
--    if the update handlers never fire. If the cache has it but
--    handlers do not fire, polling (see the status panel v1.1)
--    will work around it.

plugin = {
  id = "icesus-gmcp-debug",
  name = "Icesus GMCP Debug",
  version = "1.1.0",
  author = "DaBurgermeista",
  description = "Diagnostic: log GMCP updates and dump cached GMCP data",
}

local function dumpPackage(name)
  local data = getGMCPData(name)
  if data == nil then
    print("[GMCP dump] " .. name .. " = nil (not cached)")
    return
  end
  print("[GMCP dump] " .. name .. " = " .. type(data))
  if type(data) == "table" then
    if tprint then
      tprint(data)
    else
      for k, v in pairs(data) do
        print("  " .. tostring(k) .. " = " .. tostring(v))
      end
    end
  else
    print("  value = " .. tostring(data))
  end
end

local function dumpAll()
  print("[GMCP dump] ---- getAllGMCPData ----")
  local all = getAllGMCPData()
  if all == nil then
    print("[GMCP dump] getAllGMCPData() = nil")
  elseif type(all) == "table" then
    local count = 0
    for k, _v in pairs(all) do
      count = count + 1
      print("[GMCP dump] cached package: " .. tostring(k))
    end
    if count == 0 then print("[GMCP dump] cached packages: none") end
  else
    print("[GMCP dump] getAllGMCPData() = " .. tostring(all))
  end
  print("[GMCP dump] ---- individual packages ----")
  dumpPackage("Char.Vitals")
  dumpPackage("Char.Status")
  dumpPackage("Char.Base")
  dumpPackage("Char.Maxstats")
  dumpPackage("Char.Cooldowns")
  dumpPackage("Room.Info")
  print("[GMCP dump] ---- end ----")
end

function init()
  print("[GMCP debug] Loaded. Type /gmcpdump for a cached-data dump.")

  registerCommand("gmcpdump", function()
    dumpAll()
  end, "Dump cached GMCP data for Icesus")

  onGMCPUpdate("Char.Vitals", function(data)
    if data == nil then
      print("[GMCP update] Char.Vitals = nil")
    else
      print("[GMCP update] Char.Vitals hp=" .. tostring(data.hp)
        .. " maxhp=" .. tostring(data.maxhp)
        .. " mana=" .. tostring(data.mana)
        .. " moves=" .. tostring(data.moves)
        .. " psp=" .. tostring(data.psp))
    end
  end)

  onGMCPUpdate("Char.Status", function(data)
    if data == nil then
      print("[GMCP update] Char.Status = nil")
    else
      print("[GMCP update] Char.Status level=" .. tostring(data.level)
        .. " state=" .. tostring(data.state)
        .. " enemy=" .. tostring(data.enemy))
    end
  end)

  onGMCPUpdate("Char.Base", function(data)
    if data == nil then
      print("[GMCP update] Char.Base = nil")
    else
      print("[GMCP update] Char.Base name=" .. tostring(data.name)
        .. " class=" .. tostring(data.class))
    end
  end)

  onGMCPUpdate("Room.Info", function(data)
    if data == nil then
      print("[GMCP update] Room.Info = nil")
    else
      print("[GMCP update] Room.Info name=" .. tostring(data.name))
    end
  end)

  -- One summary poll after 10 seconds, in case handlers never fire
  -- but the cache does fill. Use /gmcpdump for repeats after that.
  -- tempTimer, not addTimer: see the header note.
  tempTimer(10, function()
    print("[GMCP poll] 10-second cache check:")
    local v = getGMCPData("Char.Vitals")
    print("[GMCP poll] Char.Vitals cached: " .. tostring(v ~= nil)
      .. " hp=" .. tostring(v and v.hp))
    local s = getGMCPData("Char.Status")
    print("[GMCP poll] Char.Status cached: " .. tostring(s ~= nil)
      .. " level=" .. tostring(s and s.level))
    local b = getGMCPData("Char.Base")
    print("[GMCP poll] Char.Base cached: " .. tostring(b ~= nil)
      .. " name=" .. tostring(b and b.name))
    local r = getGMCPData("Room.Info")
    print("[GMCP poll] Room.Info cached: " .. tostring(r ~= nil)
      .. " name=" .. tostring(r and r.name))
  end)
end

function cleanup()
end
