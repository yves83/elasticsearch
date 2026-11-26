#!/bin/bash
# ============================================================
# Elasticsearch Snapshot Backup by Date
# One archive per snapshot + clean naming
# Usage: ./backup-es-snap-by-date.sh 2026.09.09
# ============================================================

set -euo pipefail

# ---------- Configuration ----------
SNAPSHOT_DIR="/nfshare/frozen_snap"          # <-- change this
ARCHIVE_DIR="/nfshare/AzBackup"               # <-- change this
# -----------------------------------

DATE="$(date +%Y.%m.%d)"                     # default = today
AUTO="Y"				     				 # When AUTO=N, the script will prompt for confirmation before generaate archive file
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "$LOG_DIR" "$ARCHIVE_DIR"


# ---------- Logging ----------
LOG_FILE="${LOG_DIR}/backup-${DATE}.log"

log() {
  local level="$1"
  shift
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

cleanup_old_logs() {
  rm -f $SCRIPT_DIR/run/tmp*
  find "$LOG_DIR" -name "backup-*.log" -type f -mtime +30 -delete
}

# ---------- Date handling ----------

if [[ "$#" -eq 1 ]]; then
  DATE="$1"
  log "INFO" "Backup Snapshot Date : $DATE"

elif [[ "$#" -eq 2 ]]; then
  DATE="$1"
  log "INFO" "Backup Snapshot Date : $DATE"

  # Validate 2nd parameters
  if [[ "$2" == "manual" ]]; then
    AUTO="N"
    log "INFO" "Manual mode on"
  fi
else
  log "INFO" "Date is not defined. Using current date: $DATE"
  log "INFO" "Usage: $0 <date> [manual]"
  log "INFO" "Example: $0 ${DATE}"
  exit 1
fi

# Validate date format (YYYY.MM.DD)
if [[ ! "$DATE" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
  log "ERROR" "Date must be in format YYYY.MM.DD (e.g. 2026.09.09)"
  exit 1
fi

if [[ ! -d "$SNAPSHOT_DIR" ]]; then
  log "ERROR" "Snapshot directory not found: $SNAPSHOT_DIR"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  log "ERROR" "'jq' is required but not installed."
  exit 1
fi

cleanup_old_logs
log "INFO" "===== Starting backup for date: $DATE ====="

cd "$SNAPSHOT_DIR"

# ------------------------------------------------------------
# 1. Find the latest index-* file
# ------------------------------------------------------------
INDEX_FILE=$(ls -1 index-[0-9]* 2>/dev/null | sort -V | tail -1)

if [[ ! -f "$INDEX_FILE" ]]; then
  log "ERROR" "Could not find index file"
  exit 1
fi
log "INFO" "Using index file: $INDEX_FILE"

# ------------------------------------------------------------
# 2. Extract matching snapshots (safe pattern)
#    Must start with "YYYY.MM.DD-darktrace" AND contain "darktrace-ilm"
# ------------------------------------------------------------
MATCHING_SNAPSHOTS=$(jq -c --arg date "$DATE" '
  .snapshots[]
  | select(
      (.name | contains($date + "-darktrace-ilm"))
    )
' "$INDEX_FILE")

if [[ -z "$MATCHING_SNAPSHOTS" ]]; then
  log "WARN" "No snapshots found matching pattern: ${DATE}-darktrace-ilm*"
  exit 1
fi

log "INFO" "Found matching snapshot(s):"
echo "$MATCHING_SNAPSHOTS" | jq -r '.name' | while read -r n; do
  log "INFO" "  - $n"
done

# ------------------------------------------------------------
# 3. Process & archive EACH snapshot separately
# ------------------------------------------------------------
SUCCESS_COUNT=0
FAIL_COUNT=0

while IFS= read -r snap_json; do
  UUID=$(echo "$snap_json" | jq -r '.uuid')
  NAME=$(echo "$snap_json" | jq -r '.name')

  log "INFO" "--------------------------------------------------"
  log "INFO" "Processing snapshot: $NAME"
  log "INFO" "UUID: $UUID"

  # Create clean archive name
  CLUSTER_AND_DATE=$(echo "$NAME" | sed -E 's/^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-darktrace-(.*[0-9]{4}\.[0-9]{2}\.[0-9]{2}).*/\1/')

  if [[ -z "$CLUSTER_AND_DATE" || "$CLUSTER_AND_DATE" == "$NAME" ]]; then
    CLUSTER_AND_DATE=$(echo "$NAME" | cut -d'-' -f3,4)
  fi

  MANUAL_MODE_FILELIST="$SCRIPT_DIR/run/tmp_darktrace-${CLUSTER_AND_DATE}"
  ARCHIVE_NAME="darktrace-${CLUSTER_AND_DATE}.tar.gz"
  ARCHIVE_PATH="${ARCHIVE_DIR}/${ARCHIVE_NAME}"

  log "INFO" "Archive will be: $ARCHIVE_NAME"

  FILE_LIST=$(mktemp)
  trap 'rm -f "$FILE_LIST"' RETURN

  # Always include repository metadata
  find . -maxdepth 1 -type f \( -name 'index-*' -o -name 'index.latest' \) -print >> "$FILE_LIST"

  ERROR_COUNT=0

  # meta + snap files
  for f in "meta-${UUID}.dat" "snap-${UUID}.dat"; do
    if [[ -f "$f" ]]; then
      echo "./$f" >> "$FILE_LIST"
      log "INFO" "  + $f"
    else
      log "WARN" "  ! $f not found"
      ((ERROR_COUNT++)) || true
    fi
  done

  # indices folders
  echo "$snap_json" | jq -r '.index_metadata_lookup | keys[]' | while read -r idx_id; do
    DIR="indices/${idx_id}"
    if [[ -d "$DIR" ]]; then
      find "$DIR" -type f -print >> "$FILE_LIST"
      log "INFO" "  + $DIR/"
    else
      log "WARN" "  ! directory $DIR not found"
      ((ERROR_COUNT++)) || true
    fi
  done

  # Deduplicate
  sort -u "$FILE_LIST" | grep -v '^$' > "${FILE_LIST}.uniq"
  mv "${FILE_LIST}.uniq" "$FILE_LIST"

  FILE_COUNT=$(wc -l < "$FILE_LIST")
  log "INFO" "Total files for this snapshot: $FILE_COUNT"

  if [[ "$FILE_COUNT" -eq 0 ]]; then
    log "WARN" "No files found for this snapshot – skipping"
    ((FAIL_COUNT++)) || true
    continue
  fi

  if [[ "$ERROR_COUNT" -ne 0 ]]; then
    log "ERROR" "Missing files / directory for this snapshot – skipping"
    log "ERROR" "Skipping snapshot due to error: $ARCHIVE_NAME"
    ((FAIL_COUNT++)) || true
    continue
  fi

  if [[ "$AUTO" == "N" ]]; then
    mkdir -p "$SCRIPT_DIR/run"
    cat $FILE_LIST > $MANUAL_MODE_FILELIST
    echo tar -czf "$ARCHIVE_PATH" -T "$MANUAL_MODE_FILELIST" >> $SCRIPT_DIR/run/manual_archive
  fi
   
  log "INFO" "Creating archive: $ARCHIVE_PATH"
  if tar -czf "$ARCHIVE_PATH" -T "$FILE_LIST"; then
    log "INFO" "Archive created successfully"
    log "INFO" "$(ls -lh "$ARCHIVE_PATH")"
    ((SUCCESS_COUNT++)) || true
  else
    log "ERROR" "Failed to create archive for $NAME"
    ((FAIL_COUNT++)) || true
  fi

done < <(echo "$MATCHING_SNAPSHOTS")   # ← This is the important change

log "INFO" "===== Backup finished ====="
log "INFO" "Successful archives: $SUCCESS_COUNT"
log "INFO" "Failed: $FAIL_COUNT"

if [[ "$AUTO" == "N" ]]; then
   echo "Run these commands to manually create the archive files:"
   cat $SCRIPT_DIR/run/manual_archive 
   rm -f manual_archive $SCRIPT_DIR/run/manual_archive
fi
