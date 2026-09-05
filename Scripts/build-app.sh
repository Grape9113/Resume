#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/.build/Resume.app"

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Resume" "$app_dir/Contents/MacOS/Resume"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - --entitlements "$project_dir/Resources/Resume.entitlements" "$app_dir"

echo "$app_dir"
