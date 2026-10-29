Icesus MudForge plugins - current set, 2026-10-28
=====================================================

Active plugins (load these in MudForge):
- icesus-status-panel.lua   - Status Panel v1.9
- icesus-room.lua           - Room v1.7
- icesus-target.lua         - Target v1.4
- icesus-help-popout.lua    - Help Popout v1.1
- icesus-room-line.lua      - Room Line v1.0 (TRIAL, separate file)
- icesus-gmcp-debug.lua     - GMCP Debug v1.1 (diagnostic only)

Do NOT load both Room plugins at once:
- Room Line v1.0 is a trial replacement for Room v1.7.
  Disable Room v1.7 while testing Room Line, or you get duplicate bars.
  Room Line is meant to float at the bottom of the terminal, just above
  MudForge's built-in bottom bars.

Reload required:
- Help Popout v1.1 must be reloaded after import, because its
  onCommand/onSend hooks are only looked up at plugin start.
  Then test with: help newbie
  Expect a popout titled "Help: newbie", with only the prompt left
  in the terminal. This fix was still untested as of 2026-10-27.

Not included:
- icesus-vitals.lua - early, deprecated, superseded by the Status Panel.
  Ask for it if you specifically want the old file for reference.

These are plain .lua plugin files, so moving to Omarchy Linux does not
change them. Import them into MudForge the same way on the new machine.
