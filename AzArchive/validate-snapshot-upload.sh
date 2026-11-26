#!/bin/bash
# ============================================================
# Validate Elasticsearch Snapshot Archives in Azure Blob
# Usage: ./validate-snapshot-upload.sh [YYYY.MM.DD]
# ============================================================

set -euo pipefail

# ---------- Configuration ----------
SNAPSHOT_DIR="/nfshare/frozen_snap"                # local snapshot repo
# -----------------------------------

AZCOPY="$SCRIPT_DIR/azcopy"
DATE="$(date +%Y.%m.%d)"                           # default = today
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/azblob.ini"
SAS_TOKEN_FILE="${SCRIPT_DIR}/.sas_token"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/validate-${DATE}.log"

mkdir -p "$LOG_DIR"

# ---------- Logging ----------
log() {
  local level="$1"
  shift
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

cleanup_old_logs() {
  find "$LOG_DIR" -name "validate-*.log" -type f -mtime +30 -delete
}

# ---------- Load Azure config from azblob.ini ----------
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

# Support both "KEY=value" and "KEY = value" formats, ignore comments
while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip empty lines and comments
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

  # Extract key and value
  key=$(echo "$line" | cut -d'=' -f1 | xargs)
  value=$(echo "$line" | cut -d'=' -f2- | xargs)

  case "$key" in
    STORAGE_ACCOUNT)  STORAGE_ACCOUNT="$value" ;;
    CONTAINER_NAME)   CONTAINER_NAME="$value" ;;
    DEST_PREFIX)      DEST_PREFIX="$value" ;;
  esac
done < "$CONFIG_FILE"

# Set default for DEST_PREFIX if missing
DEST_PREFIX="${DEST_PREFIX:-es-snapshots}"

if [[ -z "${STORAGE_ACCOUNT:-}" || -z "${CONTAINER_NAME:-}" ]]; then
  echo "Error: STORAGE_ACCOUNT or CONTAINER_NAME is missing in $CONFIG_FILE"
  exit 1
fi

# ---------- Date handling ----------
if [[ $# -ge 1 ]]; then
  DATE="$1"
fi

if [[ ! "$DATE" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
  echo "Error: Date must be in format YYYY.MM.DD (e.g. 2026.09.09)"
  echo "Usage: $0 [YYYY.MM.DD]"
  exit 1
fi

# ---------- SAS Token ----------
if [[ ! -f "$SAS_TOKEN_FILE" ]]; then
  log "ERROR" "SAS token file not found: $SAS_TOKEN_FILE"
  exit 1
fi
SAS_TOKEN=$(grep -v '^\s*$' "$SAS_TOKEN_FILE" | head -1 | tr -d '[:space:]')
if [[ -z "$SAS_TOKEN" ]]; then
  log "ERROR" "SAS token is empty"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  log "ERROR" "jq is required"
  exit 1
fi


cleanup_old_logs
log "INFO" "===== Validating snapshot uploads for date: $DATE ====="
log "INFO" "Azure Account : $STORAGE_ACCOUNT"
log "INFO" "Container     : $CONTAINER_NAME"
log "INFO" "Prefix        : $DEST_PREFIX"

# ------------------------------------------------------------
# 1. Discover expected archives from the local index file
# ------------------------------------------------------------
cd "$SNAPSHOT_DIR"

INDEX_FILE=$(ls -1 index-[0-9]* 2>/dev/null | sort -V | tail -1)
if [[ ! -f "$INDEX_FILE" ]]; then
  log "ERROR" "Could not find index file in $SNAPSHOT_DIR"
  exit 1
fi
log "INFO" "Using index file: $INDEX_FILE"

MATCHING_SNAPSHOTS=$(jq -c --arg date "$DATE" '
  .snapshots[]
  | select(
      (.name | contains($date + "-darktrace-ilm"))
    )
' "$INDEX_FILE")

if [[ -z "$MATCHING_SNAPSHOTS" ]]; then
  log "INFO" "No snapshots found for date $DATE"
  exit 1
fi

log "INFO" "Expected snapshots:"
echo "$MATCHING_SNAPSHOTS" | jq -r '.name' | while read -r n; do
  log "INFO" "  - $n"
done

# ------------------------------------------------------------
# 2. Check each expected archive in Azure Blob
# ------------------------------------------------------------
BLOB_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${DEST_PREFIX}?${SAS_TOKEN}"

SUCCESS_COUNT=0
MISSING_COUNT=0
TOTAL=0

AZBLOB_FILELIST=$(mktemp)
${AZCOPY} list "$BLOB_URL" --output-type=text 2>/dev/null > $AZBLOB_FILELIST
#cat $AZBLOB_FILELIST

while IFS= read -r snap_json; do
  NAME=$(echo "$snap_json" | jq -r '.name')

  # Generate the same clean archive name used by the backup script
  CLUSTER_AND_DATE=$(echo "$NAME" | sed -E 's/^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-darktrace-(.*[0-9]{4}\.[0-9]{2}\.[0-9]{2}).*/\1/')
  if [[ -z "$CLUSTER_AND_DATE" || "$CLUSTER_AND_DATE" == "$NAME" ]]; then
    CLUSTER_AND_DATE=$(echo "$NAME" | cut -d'-' -f3,4)
  fi

  ARCHIVE_NAME="darktrace-${CLUSTER_AND_DATE}.tar.gz"

  ((TOTAL++)) || true
  log "INFO" "Checking: $ARCHIVE_NAME"

  if grep -q "$ARCHIVE_NAME" $AZBLOB_FILELIST; then
    log "INFO" "  ✓ FOUND in Azure Blob"
    ((SUCCESS_COUNT++)) || true
  else
    log "ERROR" "  ✗ MISSING in Azure Blob"
    ((MISSING_COUNT++)) || true
  fi

done < <(echo "$MATCHING_SNAPSHOTS")

# ------------------------------------------------------------
# 3. Summary
# ------------------------------------------------------------
log "INFO" "===== Validation finished ====="
log "INFO" "Total expected archives : $TOTAL"
log "INFO" "Found in Azure          : $SUCCESS_COUNT"
log "INFO" "Missing                 : $MISSING_COUNT"

if [[ $MISSING_COUNT -gt 0 ]]; then
  log "ERROR" "Some archives are missing in Azure Blob Storage!"
  exit 1
else
  log "INFO" "All expected archives are present in Azure Blob Storage"
  exit 0
fi
