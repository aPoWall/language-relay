-- Language Relay bridge watchdog, offscreen unit test (wave 11 § B, AIM-APPS-RULES rule 50).
--
--   lua tests/bridge-watchdog.lua
--
-- The bridge is loaded into a stub Hammerspoon, so nothing on the machine is touched: no event tap, no
-- accessibility read, no window, no reload of the owner's Hammerspoon configuration. The test drives the busy
-- flag through the QA hook and checks the two paths that used to leave it raised.

local root = arg[0]:match("^(.*)/tests/[^/]+$") or "."

local settings = {}
local timeNow = 1000
local tapEnabled = false
local secureInput = false
local raiseOnFocusedElement = false

local function element(value)
  return {
    attributeValue = function(_, key)
      if raiseOnFocusedElement then error("AXError -25204") end
      if key == "AXFocusedUIElement" then return element(value) end
      return nil
    end,
    isAttributeSettable = function() return false end,
    setAttributeValue = function() return true end,
  }
end

hs = {
  execute = function() return "" end,
  accessibilityState = function() return true end,
  settings = {
    get = function(key) return settings[key] end,
    set = function(key, value) settings[key] = value end,
  },
  timer = {
    secondsSinceEpoch = function() return timeNow end,
    doAfter = function() return {} end,
    doEvery = function() return {} end,
  },
  eventtap = {
    isSecureInputEnabled = function() return secureInput end,
    new = function()
      return {
        start = function(self) tapEnabled = true; return self end,
        stop = function(self) tapEnabled = false; return self end,
        isEnabled = function() return tapEnabled end,
      }
    end,
    event = {
      types = {flagsChanged = 1, keyDown = 2, leftMouseDown = 3, rightMouseDown = 4},
      properties = {eventSourceUserData = 1, keyboardEventAutorepeat = 2},
      newKeyEvent = function() return {setProperty = function() end, post = function() end} end,
    },
  },
  application = {
    applicationsForBundleID = function() return {} end,
    frontmostApplication = function() return {bundleID = function() return "com.apple.TextEdit" end} end,
  },
  axuielement = {systemWideElement = function() return element("ghbdtn") end},
  keycodes = {currentLayout = function() return "U.S." end, setLayout = function() return true end},
  sound = {getByFile = function() return nil end},
  json = {decode = function() return nil end},
  task = {new = function() return {start = function() return false end, terminate = function() end} end},
  pasteboard = {
    changeCount = function() return 0 end,
    clearContents = function() end,
    getContents = function() return "" end,
    readAllData = function() return {} end,
    setContents = function() end,
    writeAllData = function() end,
  },
}

dofile(root .. "/hammerspoon-layout-pilot.lua")

local failures = 0
local function check(name, actual, expected)
  if actual == expected then
    print(string.format("  ok   %s", name))
  else
    failures = failures + 1
    print(string.format("  FAIL %s: expected %s, got %s", name, tostring(expected), tostring(actual)))
  end
end

print("bridge watchdog · " .. tostring(layoutPilotStatus().version))

-- 1. the reading itself
local status = layoutPilotStatus()
check("tap is reported", status.tap, true)
check("busy starts down", status.busy, false)
check("secure input is reported", status.secureInput, false)
check("last status is reported", type(status.lastStatus), "string")
check("settings travel with the status", status.settings.capitalizationMode, "preserve")
check("the lifetime is five seconds", status.busyTimeout, 5)

-- 2. a flag younger than its lifetime is left alone, a gesture is still refused
check("fresh flag raised", layoutPilotQABusy("raise", 2), "true|false|2")
check("fresh flag holds the gesture", layoutPilotFix("shift"), false)
check("fresh flag survives the gesture", layoutPilotQABusy(), "true|false|2")

-- 3. a flag older than its lifetime is released and the next gesture runs
check("stale flag is seen", layoutPilotQABusy("raise", 9), "true|true|9")
check("status does not repair by itself", layoutPilotStatus().busyStale, true)
layoutPilotFix("shift")
check("the gesture released the flag", layoutPilotQABusy(), "false|false|0")
check("the release is written down", settings.layout_pilot_last_status, "started-shift")

-- 4. the path without a reset: the accessibility read raises inside the repair
raiseOnFocusedElement = true
check("a raising repair returns false", layoutPilotFix("shift"), false)
check("a raising repair still resets the flag", layoutPilotQABusy(), "false|false|0")
check("the error is written down", settings.layout_pilot_last_status, "fix-error")
raiseOnFocusedElement = false

-- 5. a released flag is written down as busy-timeout when nothing else follows
layoutPilotQABusy("raise", 30)
check("release reports that it fired", layoutPilotQABusy("release"), "true")
check("busy-timeout is the status", settings.layout_pilot_last_status, "busy-timeout")
check("a second release finds nothing", layoutPilotQABusy("release"), "false")

-- 6. restart drops the flag with the tap
layoutPilotQABusy("raise", 1)
layoutPilotRestart()
check("restart clears the flag", layoutPilotQABusy(), "false|false|0")
check("restart brings the tap back", layoutPilotStatus().tap, true)

-- 7. one line for the app, seven fields in a fixed order
local line = {}
for part in layoutPilotStatusLine():gmatch("[^|]+") do line[#line + 1] = part end
check("the status line has seven fields", #line, 7)
check("the line starts with the bridge version", line[1], layoutPilotStatus().version)
check("the line carries the tap", line[2], "true")

-- 8. the flag has one writer: no raw assignment outside the setter
local source = io.open(root .. "/hammerspoon-layout-pilot.lua"):read("a")
local writers = 0
for _ in source:gmatch("layoutPilotBusy = ") do writers = writers + 1 end
check("one writer for the flag", writers, 2) -- the initial `false` and the setter

if failures > 0 then
  print(string.format("FAIL: %d checks", failures))
  os.exit(1)
end
print("PASS: Language Relay bridge watchdog")
