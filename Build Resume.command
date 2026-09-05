#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
app_path="$($project_dir/Scripts/build-app.sh)"
open "$app_path"
