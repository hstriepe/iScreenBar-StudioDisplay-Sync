#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}

plutil -lint "$project_dir/Info.plist"
zsh -n "$project_dir/scripts/build.sh"
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
