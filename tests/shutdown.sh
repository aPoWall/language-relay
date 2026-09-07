#!/bin/zsh
set -euo pipefail

layout_fail() {
  print -u2 "FAIL: shutdown suite at line $1"
}
trap 'layout_fail $LINENO' ERR

layout_root="$(cd "$(dirname "$0")/.." && pwd)"
layout_installed="$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay"
layout_hs_bin="/opt/homebrew/bin/hs"
layout_hs="layout_hs_eval"
layout_agent="gui/$UID/dev.alex.layout-pilot"

layout_hs_eval() {
  local flag="${1:-}"
  local script="${2:-}"
  local out
  if [[ "$flag" != "-c" ]]; then
    "$layout_hs_bin" "$@"
    return
  fi
  for _ in {1..6}; do
    if out="$("$layout_hs_bin" -c "$script" 2>/tmp/language-relay-hs-ipc.err)"; then
      print -r -- "$out"
      return 0
    fi
    /bin/sleep 0.15
  done
  "$layout_hs_bin" -c "$script"
}

/bin/test -x "$layout_installed"
"$layout_root/install-runtime.sh" install >/tmp/language-relay-shutdown-preinstall.log
[[ "$($layout_hs -c 'return tostring(layoutPilotInputTap and layoutPilotInputTap:isEnabled())')" == "true" ]]

node "$layout_root/bin/language-relay.mjs" quit
/bin/sleep 0.45

[[ "$($layout_hs -c 'return tostring(layoutPilotInputTap and layoutPilotInputTap:isEnabled())')" == "false" ]]
[[ "$($layout_hs -c 'return tostring(hs.settings.get("layout_pilot_disabled_by_user") == true)')" == "true" ]]

layout_process_count="$((/usr/bin/pgrep -f "^$HOME/Applications/Language Relay.app/Contents/MacOS/LanguageRelay --background$" || true) | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
[[ "$layout_process_count" == "0" ]]

"$layout_root/install-runtime.sh" install >/tmp/language-relay-shutdown-reinstall.log

[[ "$($layout_hs -c 'return tostring(hs.settings.get("layout_pilot_disabled_by_user") == true)')" == "false" ]]
[[ "$($layout_hs -c 'return tostring(layoutPilotInputTap and layoutPilotInputTap:isEnabled())')" == "true" ]]
/bin/launchctl print "$layout_agent" | /usr/bin/grep -q 'state = running'
"$layout_installed" --self-test >/dev/null

print "PASS: Language Relay shutdown stops bridge and install restarts it"
