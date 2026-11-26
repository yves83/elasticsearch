#!/bin/bash
# ============================================================
# Download / List Elasticsearch archives from Azure Blob
# Usage:
#   ./download-archives-from-azure.sh list
#   ./download-archives-from-azure.sh download <filename.tar.gz>
# ============================================================

set -euo pipefail

# ---------- Configuration ----------
ARCHIVE_DIR="/nfshare/AzBackup"               # <-- change this
# -----------------------------------

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"            
AZCOPY="${SCRIPT_DIR}/azcopy"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/download-$(date '+%Y-%m-%d').log"
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
  esac
done < "$CONFIG_FILE"

# Optional: verify required values are set
if [[ -z "$STORAGE_ACCOUNT" || -z "$CONTAINER_NAME" ]]; then
  echo "Error: STORAGE_ACCOUNT or CONTAINER_NAME is missing in $CONFIG_FILE"
  exit 1
fi

# Set default if DEST_PREFIX is empty
DEST_PREFIX="${DEST_PREFIX:-es-snapshots}"

mkdir -p "$LOG_DIR" "$ARCHIVE_DIR"

# ---------- Logging ----------

log() {
  local level="$1"
  shift
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

cleanup_old_logs() {
  find "$LOG_DIR" -name "download-*.log" -type f -mtime +30 -delete
}

# ---------- Help menu ----------
show_help() {
  cat << EOF
Usage: $0 <command> [options]

Commands:
  list                          List all .tar.gz files in Azure Blob Storage
  download <filename.tar.gz>    Download a specific archive file

Examples:
  $0 list
  $0 download es-snapshot-2026.09.08.tar.gz

Notes:
  - SAS token is read from: $SAS_TOKEN_FILE
  - Downloaded files are saved to: $ARCHIVE_DIR
EOF
}

# ---------- Validation ----------
if [[ $# -eq 0 ]]; then
  show_help
  exit 0
fi

COMMAND="$1"
shift || true

if [[ ! -f "$SAS_TOKEN_FILE" ]]; then
  echo "Error: SAS token file not found: $SAS_TOKEN_FILE"
  exit 1
fi

SAS_TOKEN=$(grep -v '^\s*$' "$SAS_TOKEN_FILE" | head -1 | tr -d '[:space:]')
if [[ -z "$SAS_TOKEN" ]]; then
  echo "Error: SAS token file is empty"
  exit 1
fi

#if ! command -v azcopy &>/dev/null; then
#  echo "Error: azcopy is required but not installed"
#  exit 1
#fi

BASE_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${DEST_PREFIX}"

cleanup_old_logs

# ------------------------------------------------------------
# list
# ------------------------------------------------------------
if [[ "$COMMAND" == "list" ]]; then
  log "INFO" "Listing files in Azure Blob: ${BASE_URL}/"

  ${AZCOPY} list "${BASE_URL}?${SAS_TOKEN}" --output-type=text | \
    grep -E '\.tar\.gz' || {
      log "INFO" "No .tar.gz files found."
      exit 0
    }

  exit 0
fi

# ------------------------------------------------------------
# download
# ------------------------------------------------------------
if [[ "$COMMAND" == "download" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Error: 'download' requires a filename."
    echo
    show_help
    exit 1
  fi

  FILENAME="$1"
  SRC_URL="${BASE_URL}/${FILENAME}?${SAS_TOKEN}"
  DEST_PATH="${ARCHIVE_DIR}/${FILENAME}"

  log "INFO" "Downloading: $FILENAME"
  log "INFO" "Destination: $DEST_PATH"

  if ${AZCOPY} copy "$SRC_URL" "$DEST_PATH" --log-level=INFO; then
    log "INFO" "Download completed successfully: $DEST_PATH"
    ls -lh "$DEST_PATH"
  else
    log "ERROR" "Download failed: $FILENAME"
    exit 1
  fi

  exit 0
fi

# ---------- Unknown command ----------
echo "Error: Unknown command '$COMMAND'"
echo
show_help
exit 1
