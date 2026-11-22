#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}

plutil -lint "$project_dir/iScreenMenu/Info.plist"
plutil -lint "$project_dir/iScreenMenuControls/Info.plist"
plutil -lint "$project_dir/iScreenMenuControls/iScreenMenuControls.entitlements"
xmllint --noout "$project_dir/iScreenMenu/iScreenMenu.sdef"
zsh -n "$project_dir/scripts/build.sh"

# The Control Center extension must be embedded and keep its sandbox entitlement.
app="$project_dir/build/iScreen Menu.app"
appex="$app/Contents/PlugIns/iScreenMenuControls.appex"
[[ -d "$appex" ]] || { echo "Control Center extension missing from the app bundle." >&2; exit 1; }
codesign --verify --deep --strict "$app"
codesign -d --entitlements - "$appex" 2>/dev/null | grep -q com.apple.security.app-sandbox \
  || { echo "Control Center extension is not sandboxed." >&2; exit 1; }
zsh -n "$project_dir/scripts/install.sh"
zsh -n "$project_dir/scripts/uninstall.sh"
"$project_dir/scripts/build.sh"

# Scan tracked and untracked (non-ignored) files. git grep exits 1 when
# nothing matches and >1 on error, so a missing tool cannot pass silently.
set +e
git -C "$project_dir" grep --untracked -nIE \
  '(gho_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|/Users/Qiu)' \
  -- ':!scripts/check.sh'
scan_status=$?
set -e

if (( scan_status == 0 )); then
  echo "Potential secret or machine-specific path found." >&2
  exit 1
elif (( scan_status != 1 )); then
  echo "Secret scan failed to run (git grep exit $scan_status)." >&2
  exit 1
fi

echo "Checks passed."
