#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
build_dir="$project_dir/build"
derived_dir="$build_dir/DerivedData"
configuration=${CONFIGURATION:-Release}
product="$derived_dir/Build/Products/$configuration/iScreen Menu.app"
app_dir="$build_dir/iScreen Menu.app"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required (Command Line Tools alone are not enough)." >&2
  echo "Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 1
fi

xcodebuild \
  -project "$project_dir/iScreenMenu.xcodeproj" \
  -scheme "iScreen Menu" \
  -configuration "$configuration" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_dir" \
  -quiet \
  build

rm -rf "$app_dir"
ditto "$product" "$app_dir"

echo "Built: $app_dir"
