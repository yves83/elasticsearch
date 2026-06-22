#!/bin/bash

SAS_TOKEN="###Replace SAS Token###"
STORAGE_ACCOUNT=###Replace STORAGE Account###
CONTAINER_NAME=###Replace CONTAINER NAME###
BWMbps=1

CWD=$(dirname "$(realpath "$0")")
EXPORT_FOLDER="darktrace_exports"
LOCAL_DIR="$CWD/$EXPORT_FOLDER"  # Change if needed, or run from inside it

for i in $(ls darktrace_exports); do 
   echo Copying folder $EXPORT_FOLDER/$i; 
   $CWD/azcopy copy "$LOCAL_DIR/$i" "https://$STORAGE_ACCOUNT.blob.core.windows.net/$CONTAINER_NAME?"$SAS_TOKEN --recursive=true --cap-mbps $BWMbps
done
