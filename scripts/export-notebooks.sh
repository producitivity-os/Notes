#!/usr/bin/env bash

set -euo pipefail

notes_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_directory="$(cd -- "$notes_directory/../../.." && pwd)"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: ./export-notebooks.sh [database.sqlite3] [destination-folder]"
  echo
  echo "Defaults:"
  echo "  database:    $workspace_directory/.data/productivity-os.sqlite3"
  echo "  destination: ${HOME}/Documents/Notebooks"
  exit 0
fi

database_path="${1:-$workspace_directory/.data/productivity-os.sqlite3}"
destination_path="${2:-${HOME}/Documents/Notebooks}"
build_directory="$notes_directory/.build/notebook-exporter"
exporter="$build_directory/Build/Products/Release/notebook-exporter"

if [[ ! -f "$database_path" ]]; then
  echo "Database not found: $database_path" >&2
  echo "Pass its path as the first argument. Run with --help for usage." >&2
  exit 66
fi

mkdir -p "$destination_path"
cd "$notes_directory"

echo "Building the notebook exporter…"
xcodegen generate --spec project.yml
xcodebuild \
  -quiet \
  -project Notes.xcodeproj \
  -scheme NotebookExporter \
  -configuration Release \
  -derivedDataPath "$build_directory" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Exporting notebooks…"
"$exporter" "$database_path" "$destination_path"
