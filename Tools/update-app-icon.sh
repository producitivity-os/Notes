#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: just update-icon /path/to/icon.png" >&2
  exit 2
fi

source_image="${1:A}"
tools_directory="$(cd "$(dirname "$0")" && pwd)"
notes_directory="$(cd "$tools_directory/.." && pwd)"
resources_directory="$notes_directory/Resources"
source_copy="$resources_directory/Icon-iOS-Default-1024@1x.png"
iconset_directory="$resources_directory/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$source_image" ]]; then
  echo "Icon image not found: $source_image" >&2
  exit 2
fi

width="$(sips -g pixelWidth "$source_image" | awk '/pixelWidth/ {print $2}')"
height="$(sips -g pixelHeight "$source_image" | awk '/pixelHeight/ {print $2}')"
if [[ "$width" != "1024" || "$height" != "1024" ]]; then
  echo "Icon Composer image must be 1024×1024 pixels." >&2
  exit 2
fi

mkdir -p "$iconset_directory"
if [[ "$source_image" != "${source_copy:A}" ]]; then
  cp "$source_image" "$source_copy"
fi

for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$source_copy" --out "$iconset_directory/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -s format png -z "$doubled" "$doubled" "$source_copy" --out "$iconset_directory/icon_${size}x${size}@2x.png" >/dev/null
done

echo "Updated AppIcon from $source_image"
