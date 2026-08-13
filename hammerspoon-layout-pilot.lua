-- layout-pilot:start
-- Layout Pilot bridge v2.0
--
-- Double Shift or a clean Option tap fixes selected text / the last phrase
-- typed in the wrong layout. The bridge never creates a selection. It first
-- attempts an invisible AXValue replacement and falls back to buffered
-- backspaces + a clipboard-preserving paste for web/Electron fields.
-- Typed text stays in memory only and is never logged or persisted.

local layoutPilotBinary = "~/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot"
local layoutPilotMarker = 1280329266 -- "LPV2"
local layoutPilotBusy = false
local layoutPilotTask = nil
local layoutPilotBuffer = ""
local layoutPilotBufferApp = nil
local layoutPilotSyntheticUntil = 0
local layoutPilotEventTypes = hs.eventtap.event.types
local layoutPilotEventProperties = hs.eventtap.event.properties
local layoutPilotTapState = {
  shift = {down = false, clean = false, lastTap = 0},
  option = {down = false, clean = false, lastTap = 0},
}
local layoutPilotSettings = {
  phraseMode = true,
  soundEnabled = true,
  shiftEnabled = true,
  optionEnabled = true,
}

local function layoutPilotReadDefault(key, fallback)
  local out = hs.execute("/usr/bin/defaults read dev.alex.layout-pilot " .. key .. " 2>/dev/null") or ""
  out = out:gsub("%s+$", "")
  if out == "1" or out == "true" then return true end
  if out == "0" or out == "false" then return false end
  return fallback
end

function layoutPilotReloadSettings()
  local mode = hs.execute("/usr/bin/defaults read dev.alex.layout-pilot fixMode 2>/dev/null") or ""
  layoutPilotSettings.phraseMode = not mode:match("lastWord")
  layoutPilotSettings.soundEnabled = layoutPilotReadDefault("soundEnabled", true)
  layoutPilotSettings.shiftEnabled = layoutPilotReadDefault("shiftEnabled", true)
  layoutPilotSettings.optionEnabled = layoutPilotReadDefault("optionEnabled", true)
  return true
end

layoutPilotReloadSettings()

local function layoutPilotUTF16Length(text)
  local units = 0
  for _, codepoint in utf8.codes(text or "") do
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
    local withoutTrailing = prefix:gsub("%s+$", "")
    startByte = withoutTrailing:find("%S+$")
  end

  if not startByte then return nil end
  local location = layoutPilotUTF16Length(value:sub(1, startByte - 1))
  local length = caretUnits - location
  if length <= 0 then return nil end
  return {location = location, length = length}
end

local function layoutPilotStringForRange(value, range)
  if type(value) ~= "string" or type(range) ~= "table" then return nil end
  local startByte = layoutPilotByteOffsetForUTF16(value, range.location)
  local endByte = layoutPilotByteOffsetForUTF16(value, range.location + range.length)
  return value:sub(startByte, endByte - 1)
end

local function layoutPilotReplaceRange(value, range, replacement)
  if type(value) ~= "string" or type(range) ~= "table" or type(replacement) ~= "string" then return nil end
  local startByte = layoutPilotByteOffsetForUTF16(value, range.location)
  local endByte = layoutPilotByteOffsetForUTF16(value, range.location + range.length)
  local nextValue = value:sub(1, startByte - 1) .. replacement .. value:sub(endByte)
  return nextValue, range.location + layoutPilotUTF16Length(replacement)
end

local function layoutPilotTrimBuffer()
  local count = utf8.len(layoutPilotBuffer) or 0
  if count <= 256 then return end
  local offset = utf8.offset(layoutPilotBuffer, count - 255)
  if offset then layoutPilotBuffer = layoutPilotBuffer:sub(offset) end
end

local function layoutPilotClearBuffer()
  layoutPilotBuffer = ""
  layoutPilotBufferApp = nil
end

local function layoutPilotBackspaceBuffer()
  if layoutPilotBuffer == "" then return end
  local offset = utf8.offset(layoutPilotBuffer, -1)
  if offset then layoutPilotBuffer = layoutPilotBuffer:sub(1, offset - 1) end
end

local function layoutPilotBufferCandidate(phraseMode)
  if not layoutPilotBuffer:match("%S") then return nil end
  if phraseMode then return layoutPilotBuffer end
  local withoutTrailing = layoutPilotBuffer:gsub("%s+$", "")
  local word = withoutTrailing:match("%S+$")
  if not word then return nil end
  local trailing = layoutPilotBuffer:sub(#withoutTrailing + 1)
  return word .. trailing
end

local function layoutPilotSelectedText(focused)
  local ok, value = pcall(function()
    return focused and focused:attributeValue("AXSelectedText") or nil
  end)
  if ok and type(value) == "string" and value:match("%S") then return value end
  return nil
end

local function layoutPilotFocusedContext(phraseMode)
  local front = hs.application.frontmostApplication()
  local bundleID = front and front:bundleID() or nil
  local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  local value = focused and focused:attributeValue("AXValue") or nil
  local caret = focused and focused:attributeValue("AXSelectedTextRange") or nil
  local selected = layoutPilotSelectedText(focused)
  local range = nil
  local candidate = nil
  local manualSelection = false

  if selected then
    candidate = selected
    manualSelection = true
    if type(caret) == "table" and type(caret.location) == "number" and (caret.length or 0) > 0 then
      range = {location = caret.location, length = caret.length}
    end
  elseif type(value) == "string" and type(caret) == "table" and type(caret.location) == "number" then
    range = layoutPilotRangeForValue(value, caret.location + (caret.length or 0), phraseMode)
    candidate = range and layoutPilotStringForRange(value, range) or nil
  end

  if type(candidate) ~= "string" or not candidate:match("%S") then
    candidate = layoutPilotBufferCandidate(phraseMode)
    range = nil
    value = nil
  end

  return {
    app = front,
    bundleID = bundleID,
    focused = focused,
    value = value,
    range = range,
    candidate = candidate,
    manualSelection = manualSelection,
    phraseMode = phraseMode and not manualSelection,
  }
end

local function layoutPilotSameTarget(context)
  local front = hs.application.frontmostApplication()
  if context.bundleID and (not front or front:bundleID() ~= context.bundleID) then return false end
  if context.focused then
    local current = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
    if current ~= context.focused then return false end
  end
  if context.value and context.focused:attributeValue("AXValue") ~= context.value then return false end
  return true
end

local function layoutPilotSetTargetLayout(targetID)
  local target = targetID == "com.apple.keylayout.RussianWin" and "Russian – PC" or "U.S."
  local changed = hs.keycodes.setLayout(target)
  hs.settings.set("layout_pilot_last_layout", target .. "|set=" .. tostring(changed))
end

local function layoutPilotPlaySuccessSound()
  if not layoutPilotSettings.soundEnabled then return end
  local sound = hs.sound.getByName("Tink")
  if sound then sound:play() end
end

local function layoutPilotFinish(success, detail, targetID, verified)
  hs.settings.set("layout_pilot_last_status", detail or (success and "success" or "failed"))
  if success and targetID then layoutPilotSetTargetLayout(targetID) end
  if success then
    layoutPilotClearBuffer()
    if verified then layoutPilotPlaySuccessSound() end
  end
  layoutPilotBusy = false
end

local function layoutPilotPostMarkedKey(modifiers, key, isDown)
  local event = hs.eventtap.event.newKeyEvent(modifiers or {}, key, isDown)
  if event and layoutPilotEventProperties.eventSourceUserData then
    event:setProperty(layoutPilotEventProperties.eventSourceUserData, layoutPilotMarker)
  end
  if event then event:post() end
end

local function layoutPilotFallbackApply(context, replacement, targetID, expectedValue)
  if not layoutPilotSameTarget(context) then
    layoutPilotFinish(false, "stale-target")
    return
  end

  local deleteCount = context.manualSelection and 0 or (utf8.len(context.candidate or "") or 0)
  if deleteCount > 512 then
    layoutPilotFinish(false, "candidate-too-long")
    return
  end

  local snapshot = hs.pasteboard.readAllData()
  layoutPilotSyntheticUntil = hs.timer.secondsSinceEpoch() + 0.75
  for _ = 1, deleteCount do
    layoutPilotPostMarkedKey({}, "delete", true)
    layoutPilotPostMarkedKey({}, "delete", false)
  end

  hs.timer.doAfter(0.015, function()
    hs.pasteboard.setContents(replacement)
    local pasteboardChange = hs.pasteboard.changeCount()
    layoutPilotPostMarkedKey({"cmd"}, "v", true)
    layoutPilotPostMarkedKey({"cmd"}, "v", false)

    hs.timer.doAfter(0.12, function()
      local verified = false
      if expectedValue and context.focused then
        local ok, current = pcall(function() return context.focused:attributeValue("AXValue") end)
        verified = ok and current == expectedValue
      end
      layoutPilotFinish(true, verified and "success-events-verified" or "success-events", targetID, verified)
    end)

    hs.timer.doAfter(0.45, function()
      if hs.pasteboard.changeCount() == pasteboardChange and snapshot then
        hs.pasteboard.writeAllData(snapshot)
      end
    end)
  end)
end

local function layoutPilotApplyConversion(context, payload)
  if not layoutPilotSameTarget(context) then
    layoutPilotFinish(false, "stale-target")
    return
  end

  local expectedValue, expectedCaret
  if context.value and context.range then
    expectedValue, expectedCaret = layoutPilotReplaceRange(context.value, context.range, payload.text)
  end

  if expectedValue and context.focused then
    local settable = false
    pcall(function() settable = context.focused:isAttributeSettable("AXValue") == true end)
    if settable then
      pcall(function() context.focused:setAttributeValue("AXValue", expectedValue) end)
      local ok, readback = pcall(function() return context.focused:attributeValue("AXValue") end)
      if ok and readback == expectedValue then
        pcall(function()
          context.focused:setAttributeValue("AXSelectedTextRange", {location = expectedCaret, length = 0})
        end)
        layoutPilotFinish(true, "success-ax-verified", payload.targetID, true)
        return
      end
    end
  end

  layoutPilotFallbackApply(context, payload.text, payload.targetID, expectedValue)
end

local function layoutPilotConvert(context)
  local flag = context.phraseMode and "--convert-phrase-json" or "--convert-json"
  hs.settings.set("layout_pilot_last_status", "converting")
  layoutPilotTask = hs.task.new(layoutPilotBinary, function(code, stdout, stderr)
    layoutPilotTask = nil
    if code ~= 0 then
      layoutPilotFinish(false, "task-exit-" .. tostring(code))
      return
    end

    local ok, payload = pcall(hs.json.decode, stdout)
    if not ok or type(payload) ~= "table" or type(payload.text) ~= "string" then
      layoutPilotFinish(false, "json-failed")
      return
    end
    layoutPilotApplyConversion(context, payload)
  end, {flag, context.candidate})

  if not layoutPilotTask or not layoutPilotTask:start() then
    layoutPilotTask = nil
    layoutPilotFinish(false, "task-start-failed")
  end
end

local function layoutPilotToggleLayoutOnly()
  local current = hs.keycodes.currentLayout()
  local target = current == "Russian – PC" and "U.S." or "Russian – PC"
  local changed = hs.keycodes.setLayout(target)
  hs.settings.set("layout_pilot_last_status", changed and "layout-switched" or "layout-switch-failed")
end

function layoutPilotFix(trigger)
  if layoutPilotBusy or hs.eventtap.isSecureInputEnabled() then return false end
  layoutPilotBusy = true
  hs.settings.set("layout_pilot_last_status", "started-" .. tostring(trigger or "manual"))

  local context = layoutPilotFocusedContext(layoutPilotSettings.phraseMode)
  if type(context.candidate) ~= "string" or not context.candidate:match("%S") then
    layoutPilotBusy = false
    if trigger == "option" then layoutPilotToggleLayoutOnly() end
    return false
  end

  local count = utf8.len(context.candidate) or 0
  if count == 0 or count > 512 then
    layoutPilotFinish(false, "candidate-too-long")
    return false
  end

  layoutPilotConvert(context)
  return true
end

local function layoutPilotCompleteTap(state, requiredTaps, now)
  if requiredTaps == 1 then
    state.lastTap = 0
    return true
  end
  if state.lastTap > 0 and now - state.lastTap <= 0.38 then
    state.lastTap = 0
    return true
  end
  state.lastTap = now
  return false
end

local function layoutPilotHandleModifier(name, isDown, onlyModifier, requiredTaps, now)
  local state = layoutPilotTapState[name]
  if onlyModifier and isDown and not state.down then
    state.down = true
    state.clean = true
    return false
  end
  if not isDown and state.down then
    local clean = state.clean
    state.down = false
    state.clean = false
    if clean then return layoutPilotCompleteTap(state, requiredTaps, now) end
    state.lastTap = 0
    return false
  end
  if state.down and not onlyModifier then state.clean = false end
  return false
end

local function layoutPilotResetModifierTaps()
  for _, state in pairs(layoutPilotTapState) do
    state.down = false
    state.clean = false
    state.lastTap = 0
  end
end

local function layoutPilotHandleTypedKey(event)
  if hs.timer.secondsSinceEpoch() < layoutPilotSyntheticUntil then return end
  if hs.eventtap.isSecureInputEnabled() then layoutPilotClearBuffer(); return end

  local front = hs.application.frontmostApplication()
  local bundleID = front and front:bundleID() or nil
  if layoutPilotBufferApp and bundleID ~= layoutPilotBufferApp then layoutPilotClearBuffer() end
  layoutPilotBufferApp = bundleID

  local flags = event:getFlags()
  local keyCode = event:getKeyCode()
  if flags.cmd or flags.ctrl then layoutPilotClearBuffer(); return end
  if keyCode == 36 or keyCode == 48 or keyCode == 53 or keyCode == 76 then
    layoutPilotClearBuffer()
    return
  end
  if keyCode == 51 then layoutPilotBackspaceBuffer(); return end
  if keyCode == 123 or keyCode == 124 or keyCode == 125 or keyCode == 126 or keyCode == 115 or keyCode == 119 then
    layoutPilotClearBuffer()
    return
  end

  local ok, characters = pcall(function() return event:getCharacters() end)
  if not ok or type(characters) ~= "string" or characters == "" then return end
  if characters:find("[%z\1-\31\127]") then return end
  layoutPilotBuffer = layoutPilotBuffer .. characters
  layoutPilotTrimBuffer()
end

layoutPilotInputTap = hs.eventtap.new(
  {
    layoutPilotEventTypes.flagsChanged,
    layoutPilotEventTypes.keyDown,
    layoutPilotEventTypes.leftMouseDown,
    layoutPilotEventTypes.rightMouseDown,
  },
  function(event)
    local marker = layoutPilotEventProperties.eventSourceUserData
      and event:getProperty(layoutPilotEventProperties.eventSourceUserData) or 0
    if marker == layoutPilotMarker then return false end

    local eventType = event:getType()
    if eventType == layoutPilotEventTypes.leftMouseDown or eventType == layoutPilotEventTypes.rightMouseDown then
      layoutPilotClearBuffer()
      layoutPilotResetModifierTaps()
      return false
    end
    if eventType == layoutPilotEventTypes.keyDown then
      for _, state in pairs(layoutPilotTapState) do
        state.clean = false
        state.lastTap = 0
      end
      layoutPilotHandleTypedKey(event)
      return false
    end

    local flags = event:getFlags()
    local now = hs.timer.secondsSinceEpoch()
    local onlyShift = flags.shift == true and not flags.cmd and not flags.alt and not flags.ctrl and not flags.fn
    local onlyOption = flags.alt == true and not flags.cmd and not flags.shift and not flags.ctrl and not flags.fn
    local fireShift = layoutPilotHandleModifier("shift", flags.shift == true, onlyShift, 2, now)
    local fireOption = layoutPilotHandleModifier("option", flags.alt == true, onlyOption, 1, now)

    if fireShift and layoutPilotSettings.shiftEnabled then
      hs.timer.doAfter(0.035, function() layoutPilotFix("shift") end)
    elseif fireOption and layoutPilotSettings.optionEnabled then
      hs.timer.doAfter(0.035, function() layoutPilotFix("option") end)
    end
    return false
  end
):start()

function layoutPilotQARange(value, caretUnits, phraseMode)
  return layoutPilotRangeForValue(value, caretUnits, phraseMode)
end

function layoutPilotQAReplace(value, location, length, replacement)
  return layoutPilotReplaceRange(value, {location = location, length = length}, replacement)
end

function layoutPilotQATrigger(modifier, taps)
  local state = {down = false, clean = false, lastTap = 0}
  local required = modifier == "option" and 1 or 2
  local fired = 0
  for index = 1, taps do
    if layoutPilotCompleteTap(state, required, 1 + index * 0.1) then fired = fired + 1 end
  end
  return fired
end

function layoutPilotQABufferCandidate(value, phraseMode)
  local previous = layoutPilotBuffer
  layoutPilotBuffer = value
  local candidate = layoutPilotBufferCandidate(phraseMode)
  layoutPilotBuffer = previous
  return candidate
end

hs.settings.set("layout_pilot_bridge_ver", "2.0.0")
hs.settings.set("layout_pilot_last_status", hs.settings.get("layout_pilot_last_status") or "ready")
-- layout-pilot:end
