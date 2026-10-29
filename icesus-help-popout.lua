-- Icesus Help Popout for MudForge, v1.1
-- A help file in a popout window, instead of the terminal.
--
-- How to use it:
--   Load this plugin, then type a help command in the
--   terminal exactly as before, e.g.:
--     help skill concentrated attack
--     help newbie
--   The help output does NOT scroll the terminal. It
--   is captured, the terminal lines are gagged, and
--   when the output ends a floating Help window pops
--   up with the full text. Close it with its Close
--   button or the widget's X, and type another help
--   command to replace it with a new topic.
--   Disable this plugin to go back to terminal help.
--
-- Bug fixed in v1.1 (2026-10-27, reported by Aaron):
--   v1.0 only triggered on lines starting "Help on ".
--   "help newbie" does NOT start that way. Its output
--   starts with a centred "Welcome to Icesus" banner,
--   then the body, then the prompt. v1.0 never fired,
--   so the whole file went to the terminal, uncaught.
--   v1.1 fixes this by arming on the COMMAND, not on
--   the header. See "How capture works" below.
--
-- How capture works, v1.1:
--   1. Arming. Two top-level hooks, both defined at
--      the top level of this file (guide §2: hooks
--      are looked up once when the plugin starts,
--      and must not be defined inside init()):
--        onCommand(sessionId, command) -- before
--          alias processing, typed commands only.
--        onSend(sessionId, text) -- text about to
--          be sent to the MUD, after aliases, so a
--          user alias that expands to "help ..." also
--          arms it.
--      Either hook, seeing a command that is "help"
--      or starts "help ", sets armed = true and
--      armedTopic = the topic after "help" (e.g.
--      "newbie", "skill concentrated attack").
--      Neither hook discards or blocks the command:
--      both return nil, so "help ..." still goes to
--      the MUD exactly as typed. They only set a
--      flag; they never touch the widget, because
--      a hook can run before init() has created it.
--   2. Capture. One catch-all trigger, regex ".*",
--      name "HELP_CAPTURE". It fires on every server
--      line, including blank lines (regex ".*" matches
--      ""), which matters because help files use
--      blank lines as paragraph breaks. The callback
--      is cheap when it is not capturing: if it is
--      not armed, not capturing, and the line is not
--      a "Help on " header, it returns nil at once
--      and the line displays normally.
--      A capture starts in either of two ways:
--        a) A "Help on " header line, even if the
--           command was not armed (alias, macro, or
--           another plugin sent it). Title comes
--           from the header, as in v1.0.
--        b) An armed flag: the first server line
--           after a help command, whatever it is
--           ("Welcome to Icesus", a blank line, a
--           list, anything). Title comes from the
--           armed topic, e.g. "newbie".
--      Every captured line after that is appended
--      and gagged (callback returns false, guide §7),
--      including blank lines, which are kept as
--      paragraph breaks in the <pre> text.
--   3. End. Icesus sends its prompt right after help
--      output, e.g. "HP:100% SP:100% EP:100% XP:3506
--      Next:3233 >". When a captured line matches
--      that prompt shape, it is NOT appended and
--      NOT gagged: the popout is filled and shown,
--      and the prompt displays in the terminal as
--      normal. If the prompt shape ever changes and
--      is not recognised, a 3-second silence timer,
--      restarted on every captured line, finalises
--      the popout instead, so a missed prompt cannot
--      lose the help text.
--   4. Arming expiry. If a help command is typed
--      but no help output ever arrives, the armed
--      flag would otherwise capture the next
--      unrelated server line. So arming also starts
--      a 5-second timer: if no capture starts in
--      that time, armed is cleared. A prompt line
--      while armed also clears armed, without
--      starting a capture.
--
-- Limitations, stated plainly:
--   - A help command sent by another plugin via
--     send(), not typed and not via an alias, does
--     not go through onCommand/onSend. "Help on "
--     topics are still caught by (a) above; a
--     non-"Help on " topic sent that way is not.
--     Type the help command yourself for those.
--   - Stacked commands ("help newbie; look") are
--     not separated: everything up to the final
--     prompt after the stack would be captured as
--     one popout. Do not stack a help command.
--   - Paged help (a "--More--" style pause mid-file)
--     is not specially handled in v1.1. The timer
--     will finalise the first page after 3 seconds
--     of silence; a later page would then go to
--     the terminal, not the popout. Report it if
--     you hit a paged help file and it matters.
--   - A "no help found" error after a help command
--     is captured as a popout too, because it is
--     the output of a help command. That is
--     consistent, if a little heavy for a one-line
--     error; the prompt still shows in the terminal.
--
-- Why the popout is HTML, not canvas:
--   Help text is multi-line plain text with indents
--   (e.g. the Affiliated stats block, the newbie
--   banner). An HTML widget with a single <pre>
--   element, bound via data-mud-bind, shows it with
--   its line breaks and indents intact, and scrolls
--   if it is longer than the window. Server text is
--   never concatenated into markup: it only arrives
--   via setBoundValue, as bound text, which is the
--   safe route in guide §4 / §6. The widget content
--   is set once in init(); only the title and text
--   binds are updated on each help file.
--
-- Popout behaviour:
--   The widget is created hidden, and only shown
--   when a help file is captured. Showing uses
--   showWidget(widgetId, true), forced, because a
--   help command is an explicit user action, and
--   because a plain showWidget refuses to re-open
--   a widget the player previously closed with X
--   (guide §4). It is also raised to the top layer
--   (zIndex 49) on each capture, so it pops over
--   the terminal instead of hiding behind it.
--   The Close button in the popout hides it again
--   via the widget "action" event (data-mud-action).
--   It is a floating widget, not a docked tile:
--   drag it where you like, resize it, and it
--   stays there until you move it. If you dock it,
--   the layout owns its size again, as with any
--   MudForge widget.

plugin = {
  id = "icesus-help-popout",
  name = "Icesus Help Popout",
  version = "1.1.0",
  author = "DaBurgermeista",
  description = "Shows Icesus help files in a floating popout window instead of the terminal",
}

local widgetId = nil
local helpTimerId = nil
local armedTimerId = nil
local capturing = false
local armed = false
local armedTopic = ""
local helpTitle = ""
local helpLines = {}

local function killHelpTimer()
  if helpTimerId ~= nil then
    killTimer(helpTimerId)
    helpTimerId = nil
  end
end

local function killArmedTimer()
  if armedTimerId ~= nil then
    killTimer(armedTimerId)
    armedTimerId = nil
  end
end

local function showHelp()
  if widgetId == nil then return end
  killHelpTimer()
  killArmedTimer()
  capturing = false
  armed = false
  setBoundValue(widgetId, "helptitle", helpTitle)
  setBoundValue(widgetId, "helptext", table.concat(helpLines, "\n"))
  setWidgetProperty(widgetId, "title", "Help: " .. helpTitle)
  setWidgetZOrder(widgetId, 49)
  showWidget(widgetId, true)
end

local function finalizeHelp()
  if not capturing then return end
  showHelp()
end

local function startHelpTimer()
  killHelpTimer()
  helpTimerId = tempTimer(3, finalizeHelp, false)
end

local function armHelp(topic)
  armed = true
  armedTopic = topic
  killArmedTimer()
  armedTimerId = tempTimer(5, function()
    armed = false
    armedTimerId = nil
  end, false)
end

local function parseHelpCommand(text)
  if text == nil then return nil end
  local cmd = text:gsub("^%s+", ""):gsub("%s+$", "")
  local lower = cmd:lower()
  if lower == "help" then return "help" end
  local topic = cmd:match("^%S+%s+(.-)%s*$")
  if lower:match("^help%s") and topic ~= nil and topic ~= "" then
    return topic
  end
  return nil
end

-- Top-level hooks, guide §2. These must be defined
-- here, not inside init(), or they are never looked
-- up. They only set flags; they never touch the
-- widget, which may not exist yet when they run.
-- Both return nil: the help command still goes to
-- the MUD, unchanged.
function onCommand(_sessionId, command)
  local topic = parseHelpCommand(command)
  if topic ~= nil then armHelp(topic) end
  return nil
end

function onSend(_sessionId, text)
  local topic = parseHelpCommand(text)
  if topic ~= nil then armHelp(topic) end
  return nil
end

local function isPromptLine(line)
  return line:match("^HP:%d+%% SP:%d+%% EP:%d+%% XP:%d+ Next:%d+ >%s*$") ~= nil
end

local function helpCallback(_captures, line)
  -- Prompt while armed but not yet capturing: the
  -- help output never arrived. Clear armed, show
  -- the prompt normally, do not start a capture.
  if armed and not capturing and isPromptLine(line) then
    armed = false
    killArmedTimer()
    return nil
  end

  -- Start by header, even if not armed.
  if line:match("^Help on ") then
    capturing = true
    armed = false
    killArmedTimer()
    helpLines = {}
    local topic = line:match("^Help on%s+(.-):%s*$")
    if topic == nil or topic == "" then
      topic = line:match("^Help on%s+(.-)%s*$") or line
    end
    helpTitle = topic
    helpLines[#helpLines + 1] = line
    startHelpTimer()
    return false
  end

  -- Start by arming: first server line after a help
  -- command, whatever it is. This is the v1.1 fix
  -- for "help newbie" and any other topic without
  -- a "Help on " header.
  if armed and not capturing then
    capturing = true
    armed = false
    killArmedTimer()
    helpLines = {}
    helpTitle = armedTopic
    helpLines[#helpLines + 1] = line
    startHelpTimer()
    return false
  end

  -- Not capturing, not armed, not a header: leave
  -- the line completely alone.
  if not capturing then return nil end

  -- Prompt ends a capture: do not append it, do
  -- not gag it, show the popout.
  if isPromptLine(line) then
    finalizeHelp()
    return nil
  end

  -- Ordinary help line, including blank lines ("").
  -- Blank lines are paragraph breaks, so they are
  -- kept, not skipped.
  helpLines[#helpLines + 1] = line
  startHelpTimer()
  return false
end

function init()
  widgetId = createWidget({
    type = "html",
    name = "icesus-help",
    title = "Help",
    position = { x = 250, y = 120 },
    size = { width = 600, height = 500 },
  })

  setWidgetProperty(widgetId, "content", [[
    <style>
      body {
        font: 13px/1.5 system-ui, sans-serif;
        color: #eee;
        margin: 0;
        background: linear-gradient(180deg, #1e293b, #0f172a);
        border-left: 4px solid #38bdf8;
        border-radius: 8px;
        padding: 12px 16px;
        overflow: auto;
      }
      .head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding-bottom: 8px;
        border-bottom: 1px solid #334155;
      }
      .title {
        font-size: 16px;
        font-weight: 700;
        color: #ffffff;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .close {
        font-size: 12px;
        font-weight: 700;
        color: #e2e8f0;
        background: #334155;
        border: 0;
        border-radius: 999px;
        padding: 4px 12px;
        cursor: pointer;
        flex-shrink: 0;
      }
      pre {
        font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        color: #e2e8f0;
        margin: 12px 0 0 0;
        white-space: pre-wrap;
        word-wrap: break-word;
      }
      .hint {
        font-size: 11px;
        color: #94a3b8;
        margin-top: 12px;
        border-top: 1px solid #334155;
        padding-top: 8px;
      }
    </style>
    <div class="head">
      <span class="title" data-mud-bind="helptitle">Help</span>
      <button class="close" data-mud-action="close">Close</button>
    </div>
    <pre data-mud-bind="helptext">Type a help command, e.g. help skill concentrated attack, and the help file will appear here instead of the terminal.</pre>
    <div class="hint">Type another help command to replace this file. Close with Close or the widget X.</div>
  ]])

  registerWidgetEvent(widgetId, "action", function(event)
    if event ~= nil and event.action == "close" then
      hideWidget(widgetId)
    end
  end)

  hideWidget(widgetId)

  -- Catch-all trigger, v1.1. Regex ".*" fires on
  -- every server line, including blank lines, so
  -- the callback, not the pattern, decides whether
  -- a line is help. No fireLength / gate is needed:
  -- the pattern itself matches every line, and the
  -- callback returns nil at once when it is not
  -- capturing, so normal play is untouched.
  addTrigger(".*", helpCallback, {
    type = "regex",
    name = "HELP_CAPTURE",
  })
end

function cleanup()
  killHelpTimer()
  killArmedTimer()
end
