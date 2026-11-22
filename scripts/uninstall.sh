#!/bin/zsh
set -euo pipefail

account_name=$(id -un)
account_uid=$(id -u)
user_home_dir=$(dscl . -read "/Users/$account_name" NFSHomeDirectory | awk '{print $2}')
installed_app="$user_home_dir/Applications/iScreenBar Menu.app"
label="org.windholm.iScreenBarMenu"
launch_agent="$user_home_dir/Library/LaunchAgents/$label.plist"
# Labels and app name used before the bundle ID change and before the rename to iScreenBar Menu.
legacy_labels=(local.qiu.iScreenBarStudioSync org.windholm.iScreenMenu)
legacy_app="$user_home_dir/Applications/iScreen Menu.app"
trash_dir="$user_home_dir/.Trash"
timestamp=$(date +%Y%m%d-%H%M%S)

launchctl bootout "gui/$account_uid/$label" 2>/dev/null || true
for legacy_label in $legacy_labels; do
  launchctl bootout "gui/$account_uid/$legacy_label" 2>/dev/null || true
done
mkdir -p "$trash_dir"

if [[ -e "$installed_app" ]]; then
  mv "$installed_app" "$trash_dir/iScreenBar Menu-$timestamp.app"
fi
if [[ -e "$legacy_app" ]]; then
  mv "$legacy_app" "$trash_dir/iScreen Menu-$timestamp.app"
fi
if [[ -e "$launch_agent" ]]; then
  mv "$launch_agent" "$trash_dir/$label-$timestamp.plist"
fi
for legacy_label in $legacy_labels; do
  legacy_launch_agent="$user_home_dir/Library/LaunchAgents/$legacy_label.plist"
  if [[ -e "$legacy_launch_agent" ]]; then
    mv "$legacy_launch_agent" "$trash_dir/$legacy_label-$timestamp.plist"
  fi
done

echo "Stopped and moved installed files to Trash. The log file was preserved."
