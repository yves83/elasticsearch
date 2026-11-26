**backup-es-snap-by-date.sh**

**validate-snapshot-upload.sh**
Validate the Snapshot upload to Azure Blob Storage. Ensure the Snapshots are upload to Azure Blob Storage. 
Update this parameter before run the script:
  SNAPSHOT_DIR="/nfshare/frozen_snap"  

**download-archives-from-azure.sh**
Usage: ./download-archives-from-azure.sh <command> [options]

Commands:
  list                          List all .tar.gz files in Azure Blob Storage
  download <filename.tar.gz>    Download a specific archive file

Examples:
  ./download-archives-from-azure.sh list
  ./download-archives-from-azure.sh download es-snapshot-2026.09.08.tar.gz

Notes:
  - SAS token is read from: /opt/snap/AzArchive/.sas_token
  - Downloaded files are saved to: /nfshare/AzBackup


**restore-es-snapshot.sh**
Usage: ./restore-es-snapshot.sh <archive-filename.tar.gz>

Example:
  ./restore-es-snapshot.sh es-snapshot-2026.09.08.tar.gz

The archive will be extracted to: /nfshare/frozen_snap


**upload-archives-to-azure.sh**
This script will upload the archive files to Azure Blob Storage.
Usage: ./backup-es-snap-by-date.sh <date> [manual]
Example: ./backup-es-snap-by-date.sh 2026.11.26

**runall.sh**
Run all tasks in one script.

**list-es-snapshots.sh**
Usage: ./list-es-snapshots.sh <command> [date]

Commands:
  dates                     List all unique snapshot dates (leading YYYY.MM.DD)
  names <date>              List snapshot names for the given date
  files <date>              List snapshot names + related indices/ folders for the given date

Examples:
  ./list-es-snapshots.sh dates
  ./list-es-snapshots.sh names 2026.09.09
  ./list-es-snapshots.sh files 2026.09.09


**azblob.ini**
:: Example ::
STORAGE_ACCOUNT=esazblob
CONTAINER_NAME=snapshot
DEST_PREFIX=esfs01
OVERWRITE=false

Update this storage account information in this file. **DEST_PREFIX** if you have multiple data source, you can use this prefix to identify source.

**.sas_token**
This is a hidden file. You need to place the Azure Blob Storage SAS Token in this file.

**Installation**
1. This script requires to **azcopy**. Please download and unzip the azcopy in this folder.
2. Update the Azure Blob Storage SAS Token in this file **.sas_token**.
3. Update the Azure Blob Storage account information in this file **azblob.ini**
4. Update the **SNAPSHOT_DIR** in the **validate-snapshot-upload.sh**
5. Update the **SNAPSHOT_DIR** and **ARCHIVE_DIR** in the **backup-es-snap-by-date.sh**
