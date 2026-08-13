-- layout-pilot:start
-- Double Shift fixes selected text or the last wrong-layout phrase. The native
-- Layout Pilot binary owns real U.S. / Russian – PC mapping; Hammerspoon is the
-- already-trusted input bridge, so the app itself needs no new Accessibility grant.
local layoutPilotBinary = "~/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot"
local layoutPilotBusy = false
local layoutPilotTask = nil
local layoutPilotLastShiftTap = 0
local layoutPilotCleanShiftDown = false

local function layoutPilotRestorePasteboard(snapshot)
  if snapshot then hs.pasteboard.writeAllData(snapshot) end
end

local function layoutPilotSelectedText(focused)
  local ok, value = pcall(function()
    return focused and focused:attributeValue("AXSelectedText") or nil
  end)
  if ok and type(value) == "string" and value:match("%S") then return value end
  return nil
end

local function layoutPilotSoundEnabled()
  local out = hs.execute("/usr/bin/defaults read dev.alex.layout-pilot soundEnabled 2>/dev/null") or ""
  return not out:match("^0%s*$")
end

local function layoutPilotPhraseMode()
  local out = hs.execute("/usr/bin/defaults read dev.alex.layout-pilot fixMode 2>/dev/null") or ""
  return not out:match("lastWord")
end

local function layoutPilotUTF16Length(text)
  local units = 0
  for _, codepoint in utf8.codes(text) do
    units = units + (codepoint > 0xFFFF and 2 or 1)
  end
  return units
end

local function layoutPilotByteOffsetForUTF16(text, wantedUnits)
  if wantedUnits <= 0 then return 1 end
  local units = 0
  for byteOffset, codepoint in utf8.codes(text) do
    if units >= wantedUnits then return byteOffset end
    units = units + (codepoint > 0xFFFF and 2 or 1)
  end
  return #text + 1
end

local function layoutPilotRangeForValue(value, caretUnits, phraseMode)
  if type(value) ~= "string" or type(caretUnits) ~= "number" then return nil end
  local caretByte = layoutPilotByteOffsetForUTF16(value, caretUnits)
  local prefix = value:sub(1, caretByte - 1)
  local startByte
  if phraseMode then
    local lastNewline = prefix:match(".*()\n")
    startByte = lastNewline and (lastNewline + 1) or 1
  else
    startByte = prefix:find("%S+$") or (#prefix + 1)
  end

  local location = layoutPilotUTF16Length(value:sub(1, startByte - 1))
  local length = caretUnits - location
  if length <= 0 then return nil end
  return {location = location, length = length}
end

local function layoutPilotSelectionRange(focused, phraseMode)
  if not focused then return nil end
  local value = focused:attributeValue("AXValue")
  local caret = focused:attributeValue("AXSelectedTextRange")
  if type(caret) ~= "table" or type(caret.location) ~= "number" then return nil end
  return layoutPilotRangeForValue(value, caret.location + (caret.length or 0), phraseMode)
end

function layoutPilotQARange(value, caretUnits, phraseMode)
  return layoutPilotRangeForValue(value, caretUnits, phraseMode)
end

local function layoutPilotFinish(snapshot, success, detail)
  if success then hs.settings.set("layout_pilot_last_status", detail or "success") end
  hs.timer.doAfter(success and 0.45 or 0.05, function()
    layoutPilotRestorePasteboard(snapshot)
    layoutPilotBusy = false
  end)
end

local function layoutPilotConvert(text, phraseMode, snapshot, selectedByPilot, targetElement)
  hs.settings.set("layout_pilot_last_status", "converting")
  local flag = phraseMode and "--convert-phrase-json" or "--convert-json"
  layoutPilotTask = hs.task.new(layoutPilotBinary, function(code, stdout, stderr)
    layoutPilotTask = nil
    if code ~= 0 then
      hs.settings.set("layout_pilot_last_status", "task-exit-" .. tostring(code))
      if selectedByPilot then hs.eventtap.keyStroke({}, "right", 0) end
      layoutPilotFinish(snapshot, false)
      return
    end

    local ok, payload = pcall(hs.json.decode, stdout)
    if not ok or type(payload) ~= "table" or type(payload.text) ~= "string" then
      hs.settings.set("layout_pilot_last_status", "json-failed")
      if selectedByPilot then hs.eventtap.keyStroke({}, "right", 0) end
      layoutPilotFinish(snapshot, false)
      return
    end

    local axOK, axResult = pcall(function()
      return targetElement and targetElement:setAttributeValue("AXSelectedText", payload.text) or false
    end)
    local usedAX = axOK and axResult ~= false and axResult ~= nil
    if not usedAX then
      hs.pasteboard.setContents(payload.text)
      hs.eventtap.keyStroke({"cmd"}, "v", 0)
    end
    local targetLayout = payload.targetID == "com.apple.keylayout.RussianWin" and "Russian – PC" or "U.S."
    local layoutSet = hs.keycodes.setLayout(targetLayout)
    hs.settings.set(
      "layout_pilot_last_layout",
      targetLayout .. "|set=" .. tostring(layoutSet) .. "|current=" .. tostring(hs.keycodes.currentLayout())
    )
    if layoutPilotSoundEnabled() then
      local sound = hs.sound.getByName("Tink")
      if sound then sound:play() end
    end
    layoutPilotFinish(snapshot, true, usedAX and "success-ax" or "success-paste")
  end, {flag, text})

  if not layoutPilotTask or not layoutPilotTask:start() then
    layoutPilotTask = nil
    hs.settings.set("layout_pilot_last_status", "task-start-failed")
    if selectedByPilot then hs.eventtap.keyStroke({}, "right", 0) end
    layoutPilotFinish(snapshot, false)
  end
end

function layoutPilotFix()
  if layoutPilotBusy then return end
  layoutPilotBusy = true
  hs.settings.set("layout_pilot_last_status", "started")
  local front = hs.application.frontmostApplication()
  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  local focusedRange = focused and focused:attributeValue("AXSelectedTextRange") or nil
  hs.settings.set(
    "layout_pilot_last_target",
    (front and (front:name() .. "|" .. (front:bundleID() or "")) or "none")
      .. "|" .. (focused and (focused:attributeValue("AXRole") or "no-role") or "no-focus")
      .. "|range=" .. hs.inspect(focusedRange)
      .. "|secure=" .. tostring(hs.eventtap.isSecureInputEnabled())
  )
  local snapshot = hs.pasteboard.readAllData()
  local selected = layoutPilotSelectedText(focused)
  if selected then
    hs.settings.set("layout_pilot_last_status", "selected-text")
    layoutPilotConvert(selected, false, snapshot, false, focused)
    return
  end

  local phraseMode = layoutPilotPhraseMode()
  local directRange = layoutPilotSelectionRange(focused, phraseMode)
  local directSelectionOK = false
  if directRange then
    local ok, result = pcall(function()
      return focused:setAttributeValue("AXSelectedTextRange", directRange)
    end)
    directSelectionOK = ok and result ~= false and result ~= nil
  end
  if directSelectionOK then
    hs.settings.set("layout_pilot_last_status", phraseMode and "selecting-line-ax" or "selecting-word-ax")
  else
    hs.eventtap.keyStroke(phraseMode and {"cmd", "shift"} or {"alt", "shift"}, "left", 0)
    hs.settings.set("layout_pilot_last_status", phraseMode and "selecting-line-keys" or "selecting-word-keys")
  end
  hs.timer.doAfter(0.10, function()
    local afterSelect = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
    local afterText = afterSelect and afterSelect:attributeValue("AXSelectedText") or nil
    local afterRange = afterSelect and afterSelect:attributeValue("AXSelectedTextRange") or nil
    hs.settings.set("layout_pilot_last_selection", "length=" .. tostring(type(afterText) == "string" and #afterText or -1) .. "|range=" .. hs.inspect(afterRange))
    if type(afterText) == "string" and afterText:match("%S") then
      hs.settings.set("layout_pilot_last_status", "selected-by-pilot")
      layoutPilotConvert(afterText, phraseMode, snapshot, true, afterSelect)
      return
    end

    hs.pasteboard.clearContents()
    hs.eventtap.keyStroke({"cmd"}, "c", 0)
    hs.timer.doAfter(0.14, function()
      local line = hs.pasteboard.getContents()
      if not line or not line:match("%S") then
        hs.settings.set("layout_pilot_last_status", "copy-empty")
        hs.eventtap.keyStroke({}, "right", 0)
        layoutPilotFinish(snapshot, false)
        return
      end
      hs.settings.set("layout_pilot_last_status", "copied-line")
      layoutPilotConvert(line, phraseMode, snapshot, true, afterSelect)
    end)
  end)
end

local layoutPilotEventTypes = hs.eventtap.event.types
layoutPilotDoubleShiftTap = hs.eventtap.new(
  {layoutPilotEventTypes.flagsChanged, layoutPilotEventTypes.keyDown},
  function(event)
    if event:getType() == layoutPilotEventTypes.keyDown then
      layoutPilotCleanShiftDown = false
      layoutPilotLastShiftTap = 0
      return false
    end

    local flags = event:getFlags()
    local shiftDown = flags.shift == true
    local onlyShift = shiftDown and not flags.cmd and not flags.alt and not flags.ctrl and not flags.fn

    if onlyShift and not layoutPilotCleanShiftDown then
      layoutPilotCleanShiftDown = true
      return false
    end
    if not shiftDown and layoutPilotCleanShiftDown then
      layoutPilotCleanShiftDown = false
      local now = hs.timer.secondsSinceEpoch()
      if layoutPilotLastShiftTap > 0 and now - layoutPilotLastShiftTap <= 0.38 then
        layoutPilotLastShiftTap = 0
        hs.timer.doAfter(0.06, layoutPilotFix)
      else
        layoutPilotLastShiftTap = now
      end
      return false
    end

    if not onlyShift then
      layoutPilotCleanShiftDown = false
      layoutPilotLastShiftTap = 0
    end
    return false
  end
):start()

hs.settings.set("layout_pilot_bridge_ver", "1.1.0")
-- layout-pilot:end
