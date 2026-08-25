#!/bin/zsh
set -euo pipefail

action="${1:-install}"
project_root="${0:A:h}"
app_name="Language Relay.app"
label="dev.alex.layout-pilot"
built_app="$project_root/.build/$app_name"
installed_app="$HOME/Applications/$app_name"
agent_source="$project_root/LaunchAgent.plist"
agent_dest="$HOME/Library/LaunchAgents/$label.plist"
bridge_source="$project_root/hammerspoon-layout-pilot.lua"
bridge_dir="$HOME/.config/language-relay"
bridge_dest="$bridge_dir/hammerspoon.lua"
bridge_marker="$bridge_dir/hammerspoon-bridge"
rollback_root="$HOME/Library/Application Support/Language Relay/Rollback"
launch_target="gui/$UID/$label"
stage_root=""
snapshot=""
restore_on_error=false

cleanup() {
  local exit_code=$?
  if [[ "$restore_on_error" == true && -n "$snapshot" ]]; then
    restore_snapshot "$snapshot" || true
  fi
  [[ -z "$stage_root" ]] || /bin/rm -rf "$stage_root"
  exit $exit_code
}
trap cleanup EXIT

flagged() {
  [[ -f "$1/$2" ]]
}

restore_snapshot() {
  local source="$1"
  /bin/launchctl bootout "$launch_target" 2>/dev/null || true
  /bin/rm -rf "$installed_app"
  /bin/rm -f "$agent_dest" "$bridge_dest" "$bridge_marker"
  if flagged "$source" had-app; then /usr/bin/ditto "$source/$app_name" "$installed_app"; fi
  if flagged "$source" had-agent; then /usr/bin/ditto "$source/$label.plist" "$agent_dest"; fi
  if flagged "$source" had-bridge; then /usr/bin/ditto "$source/hammerspoon.lua" "$bridge_dest"; fi
  if flagged "$source" had-marker; then /usr/bin/touch "$bridge_marker"; fi
	  if flagged "$source" had-agent; then
	    /bin/launchctl bootstrap "gui/$UID" "$agent_dest"
	    /bin/launchctl enable "$launch_target"
	    /bin/launchctl kickstart -k "$launch_target"
	  fi
	}

stage_install() {
  [[ -d "$built_app" ]] || { print -u2 "missing built app: $built_app"; return 1; }
  stage_root="$(/usr/bin/mktemp -d /tmp/language-relay-install.XXXXXX)"
  /usr/bin/ditto "$built_app" "$stage_root/$app_name"
  /usr/bin/codesign --verify --deep --strict "$stage_root/$app_name"
  /usr/bin/sed "s|__HOME__|$HOME|g" "$agent_source" > "$stage_root/$label.plist"
  /usr/bin/plutil -lint "$stage_root/$label.plist" >/dev/null
  /usr/bin/ditto "$bridge_source" "$stage_root/hammerspoon.lua"
}

case "$action" in
  preflight)
    stage_install
    print "PASS: install staging, signature, LaunchAgent, and bridge"
    ;;
  install)
    stage_install
    snapshot="$rollback_root/$(/bin/date -u +%Y%m%dT%H%M%SZ)"
    /bin/mkdir -p "$snapshot" "$HOME/Applications" "$HOME/Library/LaunchAgents" \
      "$HOME/Library/Logs/layout-pilot" "$bridge_dir"
    if [[ -d "$installed_app" ]]; then
      /usr/bin/touch "$snapshot/had-app"
      /usr/bin/ditto "$installed_app" "$snapshot/$app_name"
    fi
    if [[ -f "$agent_dest" ]]; then
      /usr/bin/touch "$snapshot/had-agent"
      /usr/bin/ditto "$agent_dest" "$snapshot/$label.plist"
    fi
    if [[ -f "$bridge_dest" ]]; then
      /usr/bin/touch "$snapshot/had-bridge"
      /usr/bin/ditto "$bridge_dest" "$snapshot/hammerspoon.lua"
    fi
    [[ ! -f "$bridge_marker" ]] || /usr/bin/touch "$snapshot/had-marker"

    restore_on_error=true
    /bin/launchctl bootout "$launch_target" 2>/dev/null || true
    /bin/rm -rf "$installed_app"
    /usr/bin/ditto "$stage_root/$app_name" "$installed_app"
    /usr/bin/ditto "$stage_root/$label.plist" "$agent_dest"
    /usr/bin/ditto "$stage_root/hammerspoon.lua" "$bridge_dest"
    /usr/bin/touch "$bridge_marker"
	    /usr/bin/touch "$HOME/Library/Logs/layout-pilot/layout-pilot.out.log" \
	      "$HOME/Library/Logs/layout-pilot/layout-pilot.err.log"
	    /bin/launchctl bootstrap "gui/$UID" "$agent_dest"
	    /bin/launchctl enable "$launch_target"
	    /bin/launchctl kickstart -k "$launch_target"
	    restore_on_error=false
	    "$installed_app/Contents/MacOS/LanguageRelay" --setup
	    print "installed; rollback snapshot: $snapshot"
	    ;;
  rollback)
    snapshots=("$rollback_root"/*(N/om))
    (( ${#snapshots} > 0 )) || { print -u2 "no rollback snapshot found"; exit 1; }
    snapshot="${snapshots[1]}"
    restore_snapshot "$snapshot"
    print "restored: $snapshot"
    ;;
  *)
    print -u2 "usage: $0 install|preflight|rollback"
    exit 2
    ;;
esac
