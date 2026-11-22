#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
account_name=$(id -un)
account_uid=$(id -u)
user_home_dir=$(dscl . -read "/Users/$account_name" NFSHomeDirectory | awk '{print $2}')
source_app="$project_dir/build/iScreenBar Menu.app"
installed_app="$user_home_dir/Applications/iScreenBar Menu.app"
launch_agents_dir="$user_home_dir/Library/LaunchAgents"
label="org.windholm.iScreenBarMenu"
launch_agent="$launch_agents_dir/$label.plist"
# Agent labels used before the bundle ID change and before the rename to iScreenBar Menu; removed on install.
legacy_labels=(local.qiu.iScreenBarStudioSync org.windholm.iScreenMenu)
# App installed under its old name (0.4 and earlier); moved to the Trash on install.
legacy_app="$user_home_dir/Applications/iScreen Menu.app"
logs_dir="$user_home_dir/Library/Logs"
log_file="$logs_dir/iScreenBarMenu.log"

"$script_dir/build.sh"

launchctl bootout "gui/$account_uid/$label" 2>/dev/null || true
for legacy_label in $legacy_labels; do
  launchctl bootout "gui/$account_uid/$legacy_label" 2>/dev/null || true
  rm -f "$launch_agents_dir/$legacy_label.plist"
done
if [[ -e "$legacy_app" ]]; then
  mkdir -p "$user_home_dir/.Trash"
  mv "$legacy_app" "$user_home_dir/.Trash/iScreen Menu-$(date +%Y%m%d-%H%M%S).app"
fi
mkdir -p "$user_home_dir/Applications" "$launch_agents_dir" "$logs_dir"
ditto "$source_app" "$installed_app"
# Register with Launch Services so Shortcuts and Control Center find the
# App Intents and the Control Center extension.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed_app"

escaped_executable=${installed_app//&/&amp;}
escaped_log=${log_file//&/&amp;}

{
  print '<?xml version="1.0" encoding="UTF-8"?>'
  print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  print '<plist version="1.0"><dict>'
  print "<key>Label</key><string>$label</string>"
  print '<key>ProgramArguments</key><array>'
  print "<string>$escaped_executable/Contents/MacOS/iScreenBarMenu</string>"
  print '</array>'
  print '<key>RunAtLoad</key><true/>'
  print '<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>'
  print "<key>StandardOutPath</key><string>$escaped_log</string>"
  print "<key>StandardErrorPath</key><string>$escaped_log</string>"
  print '</dict></plist>'
} > "$launch_agent"

plutil -lint "$launch_agent"
launchctl bootstrap "gui/$account_uid" "$launch_agent"

echo "iScreenBar Menu is installed and running. Open it from the menu bar."
echo "Log: $log_file"
