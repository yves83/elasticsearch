#!/bin/bash
# Run this from inside darktrace_exports/

CWD=$(dirname "$(realpath "$0")")
EXPORT_FOLDER="darktrace_exports"
BASE_DIR="$CWD/$EXPORT_FOLDER"  # Change if needed, or run from inside it

cd "$BASE_DIR" || { echo "Cannot cd to $BASE_DIR"; exit 1; }

echo "Starting compression of date folders..."

for vendor_dir in */; do
    [ -d "$vendor_dir" ] || continue
    
    echo "Processing vendor: ${vendor_dir%/}"
    
    cd "$vendor_dir" || continue
    
    for date_dir in 20[0-9][0-9][0-1][0-9][0-3][0-9]/; do
        [ -d "$date_dir" ] || continue
        
        date_name="${date_dir%/}"
        tarfile="${date_name}.tar.xz"
        
        echo "  Compressing $vendor_dir/$date_name → $tarfile"
        
        if tar -Jcf "$tarfile" "$date_name"; then
            echo "  ✓ Compression successful, removing folder $date_name"
            rm -rf "$date_name"
        else
            echo "  ✗ Compression FAILED for $date_name - folder NOT removed"
        fi
    done
    
    cd - > /dev/null
done

echo "All done!"
