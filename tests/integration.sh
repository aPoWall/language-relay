#!/bin/zsh
set -euo pipefail

layout_root="~/Documents/_code/_tools/layout-pilot"
layout_harness="$layout_root/.build/LiveTextFieldHarness.app/Contents/MacOS/LiveTextFieldHarness"
layout_emitter="$layout_root/.build/ShiftEmitter"
layout_hs="/opt/homebrew/bin/hs"
layout_defaults="/usr/bin/defaults"
layout_result="/private/tmp/layout-pilot-live-result.txt"
layout_stderr="/private/tmp/layout-pilot-live-stderr.txt"
layout_sentinel="LAYOUT_PILOT_CLIPBOARD_SENTINEL"

layout_original_mode="$($layout_defaults read dev.alex.layout-pilot fixMode 2>/dev/null || true)"
layout_original_sound="$($layout_defaults read dev.alex.layout-pilot soundEnabled 2>/dev/null || true)"
layout_original_input="$($layout_hs -c 'return hs.keycodes.currentLayout()')"

$layout_hs -c 'layoutPilotIntegrationClipboard=hs.pasteboard.readAllData(); layoutPilotIntegrationClipboardWasEmpty=(layoutPilotIntegrationClipboard==nil); hs.pasteboard.setContents("LAYOUT_PILOT_CLIPBOARD_SENTINEL")' >/dev/null

layout_cleanup() {
  if [[ -n "$layout_original_mode" ]]; then
    $layout_defaults write dev.alex.layout-pilot fixMode -string "$layout_original_mode"
  else
    $layout_defaults delete dev.alex.layout-pilot fixMode 2>/dev/null || true
  fi
  if [[ -n "$layout_original_sound" ]]; then
    $layout_defaults write dev.alex.layout-pilot soundEnabled -bool "$layout_original_sound"
  else
    $layout_defaults delete dev.alex.layout-pilot soundEnabled 2>/dev/null || true
  fi
  $layout_hs -c 'if layoutPilotIntegrationClipboardWasEmpty then hs.pasteboard.clearContents() elseif layoutPilotIntegrationClipboard then hs.pasteboard.writeAllData(layoutPilotIntegrationClipboard) end; layoutPilotIntegrationClipboard=nil; layoutPilotIntegrationClipboardWasEmpty=nil' >/dev/null || true
  $layout_hs -c "hs.keycodes.setLayout([[${layout_original_input}]])" >/dev/null || true
}
trap layout_cleanup EXIT

$layout_defaults write dev.alex.layout-pilot soundEnabled -bool false

layout_assert_result() {
  local label="$1"
  local expected="$2"
  local actual="$(/bin/cat "$layout_result")"
  if [[ "$actual" != "$expected" ]]; then
    print -u2 "FAIL: $label: '$actual' != '$expected'"
    /bin/cat "$layout_stderr" >&2 || true
    exit 1
  fi
  local clipboard="$($layout_hs -c 'return hs.pasteboard.getContents()')"
  if [[ "$clipboard" != "$layout_sentinel" ]]; then
    print -u2 "FAIL: $label changed the clipboard"
    exit 1
  fi
  print "PASS: $label"
  /bin/sleep 0.8
}

layout_run_direct() {
  local label="$1"
  local expected="$2"
  shift 2
  "$layout_harness" "$@" 2>"$layout_stderr"
  /bin/sleep 0.8
  layout_assert_result "$label" "$expected"
}

$layout_defaults write dev.alex.layout-pilot fixMode -string phrase
layout_run_direct "last phrase" "Привет привет как дела" "Привет ghbdtn rfr ltkf"
layout_run_direct "explicit selection" "привет" --select-all "ghbdtn"

$layout_defaults write dev.alex.layout-pilot fixMode -string lastWord
layout_run_direct "last word" "Привет ghbdtn rfr дела" "Привет ghbdtn rfr ltkf"

$layout_defaults write dev.alex.layout-pilot fixMode -string phrase
layout_run_direct "Russian-PC to U.S." "hello" "руддщ"
if [[ "$($layout_hs -c 'return hs.keycodes.currentLayout()')" != "U.S." ]]; then
  print -u2 "FAIL: converted English text did not select U.S."
  exit 1
fi

$layout_hs -c 'hs.settings.set("layout_pilot_last_status", "waiting-double-shift")' >/dev/null
"$layout_harness" --no-trigger "ghbdtn" 2>"$layout_stderr" &
layout_double_shift_pid=$!
layout_focused=false
for _ in {1..25}; do
  /bin/sleep 0.2
  if [[ "$($layout_hs -c 'local a=hs.application.frontmostApplication(); return a and a:bundleID() or ""')" == "dev.alex.layout-pilot-live-test" ]]; then
    layout_focused=true
    break
  fi
done
if [[ "$layout_focused" != true ]]; then
  wait "$layout_double_shift_pid"
  print -u2 "FAIL: live harness could not become frontmost"
  exit 1
fi
"$layout_emitter"
wait "$layout_double_shift_pid"
/bin/sleep 0.8
layout_assert_result "physical double Shift event path" "привет"

if [[ "$($layout_hs -c 'return hs.settings.get("layout_pilot_last_status")')" != "success-ax" ]]; then
  print -u2 "FAIL: Hammerspoon bridge did not complete through AX"
  exit 1
fi
if [[ "$($layout_hs -c 'return hs.keycodes.currentLayout()')" != "Russian – PC" ]]; then
  print -u2 "FAIL: converted Russian text did not select Russian – PC"
  exit 1
fi

print "PASS: Layout Pilot live integration suite"

