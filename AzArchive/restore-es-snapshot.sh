#!/bin/bash
# ============================================================
# Restore Elasticsearch Snapshot Archive
# Usage: ./restore-es-snapshot.sh <archive-filename.tar.gz>
# ============================================================

set -euo pipefail

# ---------- Configuration ----------
RESTORE_DIR="/nfshare/frozen_snap"              	 		# Target restore directory
ARCHIVE_DIR="/nfshare/AzBackup"                 			# folder where .tar.gz files are located
# -----------------------------------

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/restore-$(date '+%Y-%m-%d').log"

mkdir -p "$LOG_DIR"

log() {
  local level="$1"
  shift
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

cleanup_old_logs() {
  find "$LOG_DIR" -name "restore-*.log" -type f -mtime +30 -delete
}

show_help() {
  cat << EOF
Usage: $0 <archive-filename.tar.gz>

Example:
  $0 es-snapshot-2026.09.08.tar.gz

The archive will be extracted to: $RESTORE_DIR
EOF
}

# ---------- Validation ----------
if [[ $# -eq 0 ]]; then
  show_help
  exit 0
fi

FILENAME="$1"
ARCHIVE_PATH="${ARCHIVE_DIR}/${FILENAME}"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  echo "Error: Archive not found: $ARCHIVE_PATH"
  exit 1
fi

if [[ ! -d "$RESTORE_DIR" ]]; then
  echo "Error: Restore directory does not exist: $RESTORE_DIR"
  exit 1
fi

cleanup_old_logs
log "INFO" "===== Starting restore ====="
log "INFO" "Archive : $ARCHIVE_PATH"
log "INFO" "Target  : $RESTORE_DIR"

# ---------- Extract ----------
log "INFO" "Extracting archive..."

if tar zxvf "$ARCHIVE_PATH" -C "$RESTORE_DIR"; then
  log "INFO" "Restore completed successfully"
else
  log "ERROR" "Extract failed"
  exit 1
fi

log "INFO" "===== Restore finished ====="
