#!/bin/zsh
set -euo pipefail

layout_root="$(cd "$(dirname "$0")/.." && pwd)"
layout_built="$layout_root/.build/Type Relay.app/Contents/MacOS/LayoutPilot"
layout_installed="$HOME/Applications/Type Relay.app/Contents/MacOS/LayoutPilot"
layout_hs="/opt/homebrew/bin/hs"
layout_agent="gui/$UID/dev.alex.layout-pilot"

"$layout_built" --self-test
"$layout_installed" --self-test
"$layout_built" --ui-self-test
"$layout_installed" --ui-self-test

layout_latin_json="$("$layout_installed" --convert-json "ghbdtn")"
[[ "$layout_latin_json" == *'"text":"привет"'* ]]
[[ "$layout_latin_json" == *'"targetID":"com.apple.keylayout.RussianWin"'* ]]

layout_cyrillic_json="$("$layout_installed" --convert-json "руддщ")"
[[ "$layout_cyrillic_json" == *'"text":"hello"'* ]]
[[ "$layout_cyrillic_json" == *'"targetID":"com.apple.keylayout.US"'* ]]

layout_phrase_json="$("$layout_installed" --convert-phrase-json "Привет ghbdtn rfr ltkf")"
[[ "$layout_phrase_json" == *'"text":"Привет привет как дела"'* ]]

layout_sentence_json="$("$layout_installed" --convert-json "ghbdtn" --capitalization sentence)"
[[ "$layout_sentence_json" == *'"text":"Привет"'* ]]

layout_uppercase_json="$("$layout_installed" --convert-json "ghbdtn" --capitalization uppercase)"
[[ "$layout_uppercase_json" == *'"text":"ПРИВЕТ"'* ]]

layout_lowercase_json="$("$layout_installed" --convert-json "GHBDTN" --capitalization lowercase)"
[[ "$layout_lowercase_json" == *'"text":"привет"'* ]]

/usr/bin/plutil -lint "$layout_root/Info.plist" >/dev/null
/usr/bin/plutil -lint "$layout_root/LaunchAgent.plist" >/dev/null
/usr/bin/codesign --verify --deep --strict "$HOME/Applications/Type Relay.app"
/bin/test -s "$layout_root/assets/LayoutPilot.icns"
/bin/test -s "$HOME/Applications/Type Relay.app/Contents/Resources/LayoutPilot.icns"
/bin/test -f "$HOME/.config/type-relay/hammerspoon-bridge"
[[ "$(find "$HOME/Applications/Type Relay.app/Contents/Resources/Sounds" -type f -name '*.aiff' | wc -l | tr -d ' ')" == "4" ]]

[[ "$($layout_hs -c 'return hs.settings.get("layout_pilot_bridge_ver")')" == "2.2.0" ]]
[[ "$($layout_hs -c 'return tostring(layoutPilotInputTap and layoutPilotInputTap:isEnabled())')" == "true" ]]
[[ "$($layout_hs -c 'local value="🙂 first"..string.char(10).."Привет ghbdtn"; local r=layoutPilotQARange(value, 22, true); return r.location.."|"..r.length')" == "9|13" ]]
[[ "$($layout_hs -c 'local value="🙂 first"..string.char(10).."Привет ghbdtn"; local r=layoutPilotQARange(value, 22, false); return r.location.."|"..r.length')" == "16|6" ]]
[[ "$($layout_hs -c 'local value="🙂 first"..string.char(10).."Привет ghbdtn"; local v,c=layoutPilotQAReplace(value,16,6,"привет"); return v.."|"..c')" == $'🙂 first\nПривет привет|22' ]]
[[ "$($layout_hs -c 'return tostring(layoutPilotQATrigger("shift",1)).."|"..tostring(layoutPilotQATrigger("shift",2)).."|"..tostring(layoutPilotQATrigger("option",1))')" == "0|1|1" ]]
[[ "$($layout_hs -c 'return layoutPilotQABufferCandidate("Привет ghbdtn  ",false)')" == "ghbdtn  " ]]
[[ "$($layout_hs -c 'return layoutPilotQAFallbackDecision("ghbdtn","","","привет",false)')" == "paste" ]]
[[ "$($layout_hs -c 'return layoutPilotQAFallbackDecision("ghbdtn","ghbdtn","","привет",false)')" == "abort-delete" ]]
[[ "$($layout_hs -c 'return layoutPilotQAFallbackDecision("ghbdtn","привет","","привет",false)')" == "done" ]]
[[ "$($layout_hs -c 'return string.format("%.3f|%.3f",layoutPilotQADeletionDelay(1),layoutPilotQADeletionDelay(100))')" == "0.040|0.235" ]]
[[ "$($layout_hs -c 'return layoutPilotQASettings()')" == "pulse|preserve|balanced|true" ]]
[[ "$($layout_hs -c 'return tostring(layoutPilotQAOptionSequence("clean")).."|"..tostring(layoutPilotQAOptionSequence("with-key")).."|"..tostring(layoutPilotQAOptionSequence("with-command"))')" == "true|false|false" ]]
rg -q 'clean Option tap' "$layout_root/hammerspoon-layout-pilot.lua"
rg -q 'layoutPilotInputTap:stop' "$layout_root/hammerspoon-layout-pilot.lua"
! rg -q 'selecting-line|selected-by-pilot|AXSelectedTextRange", directRange' "$layout_root/hammerspoon-layout-pilot.lua"
rg -q 'type-relay/hammerspoon.lua' "$HOME/.hammerspoon/init.lua"

/bin/launchctl print "$layout_agent" | /usr/bin/grep -q 'state = running'
layout_process_count="$(/usr/bin/pgrep -f "^$HOME/Applications/Type Relay.app/Contents/MacOS/LayoutPilot --background$" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
[[ "$layout_process_count" == "1" ]]

layout_stderr="$HOME/Library/Logs/layout-pilot/layout-pilot.err.log"
[[ ! -s "$layout_stderr" ]]

if /usr/bin/pgrep -if '/Applications/Caramba Switcher.app/' >/dev/null; then
  print -u2 "FAIL: Caramba Switcher is still running"
  exit 1
fi

layout_caramba_login="$(/usr/bin/osascript -e 'tell application "System Events" to return exists login item "Caramba Switcher"')"
[[ "$layout_caramba_login" == "false" ]]

git -C "$layout_root" diff --check
print "PASS: Type Relay background health suite"
