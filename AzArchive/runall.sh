#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup-es-snap-by-date.sh"
UPLOAD_SCRIPT="${SCRIPT_DIR}/upload-archives-to-azure.sh"
VALIDATE_SCRIPT="${SCRIPT_DIR}/validate-snapshot-upload.sh"
DATE="$(date -d '90 days ago' +%Y.%m.%d)"

echo "Preparing Snapshot Archive ... ... " &&
${BACKUP_SCRIPT} ${DATE} &&
echo "Done"

echo "Upload Snapshot Archive ... ... " &&
${UPLOAD_SCRIPT} &&
echo "Done"

echo "Validate ... ... " &&
${VALIDATE_SCRIPT} ${DATE} &&
echo "Done"
