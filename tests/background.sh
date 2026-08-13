#!/bin/zsh
set -euo pipefail

layout_root="~/Documents/_code/_tools/layout-pilot"
layout_built="$layout_root/.build/Layout Pilot.app/Contents/MacOS/LayoutPilot"
layout_installed="~/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot"
layout_hs="/opt/homebrew/bin/hs"
layout_agent="gui/$UID/dev.alex.layout-pilot"

"$layout_built" --self-test
"$layout_installed" --self-test

layout_latin_json="$("$layout_installed" --convert-json "ghbdtn")"
[[ "$layout_latin_json" == *'"text":"привет"'* ]]
[[ "$layout_latin_json" == *'"targetID":"com.apple.keylayout.RussianWin"'* ]]

layout_cyrillic_json="$("$layout_installed" --convert-json "руддщ")"
[[ "$layout_cyrillic_json" == *'"text":"hello"'* ]]
[[ "$layout_cyrillic_json" == *'"targetID":"com.apple.keylayout.US"'* ]]

layout_phrase_json="$("$layout_installed" --convert-phrase-json "Привет ghbdtn rfr ltkf")"
[[ "$layout_phrase_json" == *'"text":"Привет привет как дела"'* ]]

/usr/bin/plutil -lint "$layout_root/Info.plist" >/dev/null
/usr/bin/plutil -lint "$layout_root/LaunchAgent.plist" >/dev/null
/usr/bin/codesign --verify --deep --strict "~/Applications/Layout Pilot.app"
/bin/test -f "~/.config/layout-pilot/hammerspoon-bridge"

[[ "$($layout_hs -c 'return hs.settings.get("layout_pilot_bridge_ver")')" == "1.1.0" ]]
[[ "$($layout_hs -c 'return tostring(layoutPilotDoubleShiftTap and layoutPilotDoubleShiftTap:isEnabled())')" == "true" ]]
[[ "$($layout_hs -c 'local value="🙂 first"..string.char(10).."Привет ghbdtn"; local r=layoutPilotQARange(value, 22, true); return r.location.."|"..r.length')" == "9|13" ]]
[[ "$($layout_hs -c 'local value="🙂 first"..string.char(10).."Привет ghbdtn"; local r=layoutPilotQARange(value, 22, false); return r.location.."|"..r.length')" == "16|6" ]]
/usr/bin/diff -u \
  <(/usr/bin/sed -n '/-- layout-pilot:start/,/-- layout-pilot:end/p' ~/.hammerspoon/init.lua) \
  "$layout_root/hammerspoon-layout-pilot.lua"

/bin/launchctl print "$layout_agent" | /usr/bin/grep -q 'state = running'
layout_process_count="$(/usr/bin/pgrep -f '^~/Applications/Layout Pilot.app/Contents/MacOS/LayoutPilot --background$' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
[[ "$layout_process_count" == "1" ]]

if /usr/bin/pgrep -if '/Applications/Caramba Switcher.app/' >/dev/null; then
  print -u2 "FAIL: Caramba Switcher is still running"
  exit 1
fi

layout_caramba_login="$(/usr/bin/osascript -e 'tell application "System Events" to return exists login item "Caramba Switcher"')"
[[ "$layout_caramba_login" == "false" ]]

git -C "$layout_root" diff --check
print "PASS: Layout Pilot background health suite"
