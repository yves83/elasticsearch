#!/bin/bash
# Run this from inside darktrace_exports/

CWD=$(dirname "$(realpath "$0")")
EXPORT_FOLDER="darktrace_exports"
BASE_DIR="$CWD/$EXPORT_FOLDER"  # Change if needed, or run from inside it

echo "Compress JSON files"
find "$BASE_DIR" -type f ! -name "*.gz" -exec xz {} \;
echo "All done!"
