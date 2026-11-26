#!/bin/bash
# ============================================================
# List Elasticsearch Snapshot Information
# Usage:
#   ./list-es-snapshots.sh dates
#   ./list-es-snapshots.sh names <date>
#   ./list-es-snapshots.sh files <date>
# ============================================================

set -euo pipefail

# ---------- Configuration ----------
SNAPSHOT_DIR="/nfshare/frozen_snap"          # <-- change this
# -----------------------------------

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"

show_help() {
  cat << EOF
Usage: $0 <command> [date]

Commands:
  dates                     List all unique snapshot dates (leading YYYY.MM.DD)
  names <date>              List snapshot names for the given date
  files <date>              List snapshot names + related indices/ folders for the given date

Examples:
  $0 dates
  $0 names 2026.09.09
  $0 files 2026.09.09
EOF
}

# ---------- Validation ----------
if [[ $# -eq 0 ]]; then
  show_help
  exit 0
fi

COMMAND="$1"
shift || true

if [[ ! -d "$SNAPSHOT_DIR" ]]; then
  echo "Error: Snapshot directory not found: $SNAPSHOT_DIR"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: 'jq' is required but not installed."
  exit 1
fi

cd "$SNAPSHOT_DIR"

# Find latest index file
INDEX_FILE=$(ls -1 index-[0-9]* 2>/dev/null | sort -V | tail -1)
if [[ ! -f "$INDEX_FILE" ]]; then
  echo "Error: Could not find index-* file"
  exit 1
fi

# ============================================================
# 1. List unique dates
# ============================================================
if [[ "$COMMAND" == "dates" ]]; then
  echo "Unique snapshot dates (from index file: $INDEX_FILE)"
  echo "--------------------------------------------------"

  jq -r '.snapshots[].name' "$INDEX_FILE" \
    | grep -oE '[0-9]{4}\.[0-9]{2}\.[0-9]{2}-darktrace-ilm' \
    | cut -d\- -f1 \
    | sort -u

  exit 0
fi

# ============================================================
# Common: require a date for the other commands
# ============================================================
if [[ $# -lt 1 ]]; then
  echo "Error: Date is required for command '$COMMAND'"
  echo
  show_help
  exit 1
fi

DATE="$1"

if [[ ! "$DATE" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
  echo "Error: Date must be in format YYYY.MM.DD (e.g. 2026.09.09)"
  exit 1
fi

# ============================================================
# 2. List snapshot names for a given date
# ============================================================
if [[ "$COMMAND" == "names" ]]; then
  echo "Snapshots for date: $DATE"
  echo "Index file: $INDEX_FILE"
  echo "--------------------------------------------------"

  jq -r --arg date "$DATE" '
    .snapshots[]
    | select(.name | contains($date + "-darktrace-ilm"))
    | .name
  ' "$INDEX_FILE"

  exit 0
fi

# ============================================================
# 3. List snapshot names + related indices/ folders
# ============================================================
if [[ "$COMMAND" == "files" ]]; then
  echo "Snapshots and related files/folders for date: $DATE"
  echo "Index file: $INDEX_FILE"
  echo "=================================================="

  # Get matching snapshots as compact JSON
  MATCHING=$(jq -c --arg date "$DATE" '
    .snapshots[]
    | select(.name | contains($date + "-darktrace-ilm"))
  ' "$INDEX_FILE")

  if [[ -z "$MATCHING" ]]; then
    echo "No snapshots found for date $DATE"
    exit 0
  fi

  echo "$MATCHING" | while read -r snap_json; do
    NAME=$(echo "$snap_json" | jq -r '.name')
    UUID=$(echo "$snap_json" | jq -r '.uuid')

    echo
    echo "Snapshot : $NAME"
    echo "UUID     : $UUID"
    echo "Related indices/ folders:"

    # Print the index folder names
    echo "$snap_json" | jq -r '.index_metadata_lookup | keys[]' | while read -r idx_id; do
      echo "  - indices/${idx_id}/"
    done

    # Also show the meta and snap files
    echo "Related data files:"
    echo "  - meta-${UUID}.dat"
    echo "  - snap-${UUID}.dat"
    echo "--------------------------------------------------"
  done

  exit 0
fi

# ---------- Unknown command ----------
echo "Error: Unknown command '$COMMAND'"
echo
show_help
exit 1
