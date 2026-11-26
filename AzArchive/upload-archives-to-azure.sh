#!/bin/bash
# ============================================================
# Upload all .tar.gz archives to Azure Blob Storage
# Usage: ./upload-archives-to-azure.sh
# ============================================================

set -euo pipefail

# ---------- Configuration (edit these) ----------
BWMbps=10                                                       # bandwidth limit (Mbps)
ARCHIVE_DIR="/nfshare/AzBackup"                                 # <-- CHANGE (folder containing .tar.gz files)
OVERWRITE=false													# overwrite settings for overwrite the files in Azure Blob
# ------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
AZCOPY="${SCRIPT_DIR}/azcopy"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/upload-$(date '+%Y-%m-%d').log"
CONFIG_FILE="${SCRIPT_DIR}/azblob.ini"
SAS_TOKEN_FILE="${SCRIPT_DIR}/.sas_token"

# ---------- Load configuration from azblob.ini ----------
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found: $CONFIG_FILE"
  exit 1
fi

# Read key=value pairs (ignore empty lines and comments)
while IFS='=' read -r key value; do
  # Skip comments and empty lines
  [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

  # Trim whitespace
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)

  case "$key" in
    STORAGE_ACCOUNT)  STORAGE_ACCOUNT="$value" ;;
    CONTAINER_NAME)   CONTAINER_NAME="$value" ;;
    DEST_PREFIX)      DEST_PREFIX="$value" ;;
    OVERWRITE)        OVERWRITE="$value" ;;
  esac
done < "$CONFIG_FILE"

# Optional: verify required values are set
if [[ -z "$STORAGE_ACCOUNT" || -z "$CONTAINER_NAME" ]]; then
  echo "Error: STORAGE_ACCOUNT or CONTAINER_NAME is missing in $CONFIG_FILE"
  exit 1
fi

# Set default if DEST_PREFIX is empty
DEST_PREFIX="${DEST_PREFIX:-es-snapshots}"

mkdir -p "$LOG_DIR"

# ---------- Logging ----------

log() {
  local level="$1"
  shift
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

# Keep only the most recent 30 days of logs
cleanup_old_logs() {
  find "$LOG_DIR" -name "upload-*.log" -type f -mtime +30 -delete
}

# ---------- Validation ----------
if [[ ! -f "$SAS_TOKEN_FILE" ]]; then
  echo "Error: SAS token file not found: $SAS_TOKEN_FILE"
  exit 1
fi

SAS_TOKEN=$(grep -v '^\s*$' "$SAS_TOKEN_FILE" | head -1 | tr -d '[:space:]')
if [[ -z "$SAS_TOKEN" ]]; then
  echo "Error: SAS token file is empty"
  exit 1
fi

if [[ ! -d "$ARCHIVE_DIR" ]]; then
  echo "Error: Archive directory not found: $ARCHIVE_DIR"
  exit 1
fi

#if ! command -v azcopy &>/dev/null; then
#  echo "Error: azcopy is required but not installed"
#  exit 1
#fi

cleanup_old_logs
log "INFO" "===== Starting upload of all .tar.gz files ====="
log "INFO" "Source directory: $ARCHIVE_DIR"

# ------------------------------------------------------------
# Find all .tar.gz files
# ------------------------------------------------------------
mapfile -t TAR_FILES < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name "*.tar.gz" | sort)

if [[ ${#TAR_FILES[@]} -eq 0 ]]; then
  log "INFO" "No .tar.gz files found. Nothing to upload."
  exit 0
fi

log "INFO" "Found ${#TAR_FILES[@]} file(s) to upload:"

SUCCESS_COUNT=0
FAIL_COUNT=0

for FILE in "${TAR_FILES[@]}"; do
  FILENAME=$(basename "$FILE")
  DEST_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${DEST_PREFIX}/${FILENAME}?${SAS_TOKEN}"

  log "INFO" "Uploading: $FILENAME"

  #echo ${AZCOPY} copy "$FILE" "$DEST_URL"
  if OUTPUT=$(${AZCOPY} copy "$FILE" "$DEST_URL" \
       --cap-mbps "$BWMbps" \
       --overwrite "${OVERWRITE}" \
       --log-level=INFO 2>&1); then

    log "INFO" "Upload successful: $FILENAME"
    log "INFO" "azcopy output: $OUTPUT"
    log "INFO" "Removing local file: $FILE"
    rm -f "$FILE"
    ((SUCCESS_COUNT++)) || true
  else
    log "ERROR" "Upload failed: $FILENAME (local file kept)"
    ((FAIL_COUNT++)) || true
  fi
done

log "INFO" "===== Upload finished ====="
log "INFO" "Successful: $SUCCESS_COUNT  |  Failed: $FAIL_COUNT"
