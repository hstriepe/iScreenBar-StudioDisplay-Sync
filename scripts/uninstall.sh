#!/bin/zsh
set -euo pipefail

account_name=$(id -un)
account_uid=$(id -u)
user_home_dir=$(dscl . -read "/Users/$account_name" NFSHomeDirectory | awk '{print $2}')
installed_app="$user_home_dir/Applications/iScreen Menu.app"
label="org.windholm.iScreenMenu"
launch_agent="$user_home_dir/Library/LaunchAgents/$label.plist"
legacy_label="local.qiu.iScreenBarStudioSync"
legacy_launch_agent="$user_home_dir/Library/LaunchAgents/$legacy_label.plist"
trash_dir="$user_home_dir/.Trash"
timestamp=$(date +%Y%m%d-%H%M%S)

launchctl bootout "gui/$account_uid/$label" 2>/dev/null || true
launchctl bootout "gui/$account_uid/$legacy_label" 2>/dev/null || true
mkdir -p "$trash_dir"

if [[ -e "$installed_app" ]]; then
  mv "$installed_app" "$trash_dir/iScreen Menu-$timestamp.app"
fi
if [[ -e "$launch_agent" ]]; then
  mv "$launch_agent" "$trash_dir/$label-$timestamp.plist"
fi
if [[ -e "$legacy_launch_agent" ]]; then
  mv "$legacy_launch_agent" "$trash_dir/$legacy_label-$timestamp.plist"
fi

echo "Stopped and moved installed files to Trash. The log file was preserved."
