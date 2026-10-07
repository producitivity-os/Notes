#!/bin/zsh
set -euo pipefail

configuration="${1:-Debug}"
action="${2:-build}"
tools_directory="$(cd "$(dirname "$0")" && pwd)"
notes_directory="$(cd "$tools_directory/.." && pwd)"
host_architecture="$(uname -m)"

case "$configuration" in
  Debug)
    derived_data="$notes_directory/.build/xcode"
    ;;
  Release)
    derived_data="$notes_directory/.build/xcode-release"
    ;;
  *)
    echo "Unsupported configuration: $configuration" >&2
    exit 2
    ;;
esac

cd "$notes_directory"
xcodegen generate
xcodebuild \
  -quiet \
  -project Notes.xcodeproj \
  -scheme Notes \
  -destination "platform=macOS,arch=$host_architecture" \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  clean \
  "$action"
