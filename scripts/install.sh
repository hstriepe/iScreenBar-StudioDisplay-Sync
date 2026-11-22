#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
account_name=$(id -un)
account_uid=$(id -u)
user_home_dir=$(dscl . -read "/Users/$account_name" NFSHomeDirectory | awk '{print $2}')
source_app="$project_dir/build/iScreen Menu.app"
installed_app="$user_home_dir/Applications/iScreen Menu.app"
launch_agents_dir="$user_home_dir/Library/LaunchAgents"
label="org.windholm.iScreenMenu"
launch_agent="$launch_agents_dir/$label.plist"
# Agent label used before the bundle ID change; removed on install.
legacy_label="local.qiu.iScreenBarStudioSync"
legacy_launch_agent="$launch_agents_dir/$legacy_label.plist"
logs_dir="$user_home_dir/Library/Logs"
log_file="$logs_dir/iScreenMenu.log"

"$script_dir/build.sh"

launchctl bootout "gui/$account_uid/$label" 2>/dev/null || true
launchctl bootout "gui/$account_uid/$legacy_label" 2>/dev/null || true
rm -f "$legacy_launch_agent"
mkdir -p "$user_home_dir/Applications" "$launch_agents_dir" "$logs_dir"
ditto "$source_app" "$installed_app"

escaped_executable=${installed_app//&/&amp;}
escaped_log=${log_file//&/&amp;}

{
  print '<?xml version="1.0" encoding="UTF-8"?>'
  print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  print '<plist version="1.0"><dict>'
  print "<key>Label</key><string>$label</string>"
  print '<key>ProgramArguments</key><array>'
  print "<string>$escaped_executable/Contents/MacOS/iScreenMenu</string>"
  print '</array>'
  print '<key>RunAtLoad</key><true/>'
  print '<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>'
  print "<key>StandardOutPath</key><string>$escaped_log</string>"
  print "<key>StandardErrorPath</key><string>$escaped_log</string>"
  print '</dict></plist>'
} > "$launch_agent"

plutil -lint "$launch_agent"
launchctl bootstrap "gui/$account_uid" "$launch_agent"

echo "iScreen Menu 已安装并启动，请从菜单栏打开。"
echo "Log: $log_file"
