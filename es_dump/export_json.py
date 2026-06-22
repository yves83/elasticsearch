#!/usr/bin/python
import os
import sys
import json
import argparse
import re
from datetime import datetime, timedelta
import glob

# ====================== LOCAL LIB SUPPORT ======================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LIB_PATH = os.path.join(SCRIPT_DIR, "libs")
if os.path.exists(LIB_PATH):
    sys.path.insert(0, LIB_PATH)
    print(f"Using local packages from: {LIB_PATH}")

from elasticsearch import Elasticsearch
from elasticsearch.exceptions import NotFoundError
# ================================================================

# ========================= CONFIGURATION =========================
ES_HOST = "https://localhost:9200"
ES_USER = 'esdump'
ES_PASSWORD = '###ES PASSWORD###'

DEFAULT_INDEX_PREFIX = "fortigate.firewall"
TIMESTAMP_FIELD = "@timestamp"
OUTPUT_BASE = "./exports"
BATCH_SIZE = 2000
MAX_FILE_SIZE = 1 * 1024 * 1024  # 1MB
KEEP_ALIVE = "15m"
# ================================================================

es = Elasticsearch(
    ES_HOST,
    basic_auth=(ES_USER, ES_PASSWORD) if ES_USER and ES_PASSWORD else None,
    request_timeout=60,
    max_retries=3,
    retry_on_timeout=True,
    verify_certs=False,
    ssl_show_warn=False
)


def clean_index_prefix(prefix: str) -> str:
    """Remove any trailing -yyyy.mm.dd from the prefix"""
    if not prefix:
        return DEFAULT_INDEX_PREFIX
    prefix = re.sub(r'-\d{4}\.\d{2}\.\d{2}$', '', prefix)
    return prefix


def ensure_folder(index_prefix: str, date_str: str):
    folder = os.path.join(OUTPUT_BASE, index_prefix, date_str)
    os.makedirs(folder, exist_ok=True)
    return folder


def get_last_file_info(index_prefix: str, date_str: str, hour: int):
    folder = ensure_folder(index_prefix, date_str)
    pattern = os.path.join(folder, f"{date_str}_{hour:02d}_*.json")
   
    files = glob.glob(pattern)
    if not files:
        return 0, None, 0

    def get_index(f):
        try:
            return int(os.path.basename(f).split('_')[-1].replace('.json', ''))
        except:
            return 0

    last_file = max(files, key=get_index)
    last_index = get_index(last_file)
    current_size = os.path.getsize(last_file)
   
    return last_index, last_file, current_size


def clean_empty_files():
    print("\nCleaning up empty files...")
    deleted_count = 0
    total_checked = 0
   
    for root, dirs, files in os.walk(OUTPUT_BASE):
        for file in files:
            if not file.endswith(".json"):
                continue
            filepath = os.path.join(root, file)
            total_checked += 1
            size = os.path.getsize(filepath)
            should_delete = False
            
            if size == 0:
                should_delete = True
            elif size < 100:
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        content = f.read().strip()
                        if content == "" or content == "[]":
                            should_delete = True
                except:
                    should_delete = True
                    
            if should_delete:
                try:
                    os.remove(filepath)
                    deleted_count += 1
                    print(f" Deleted empty file: {file}")
                except Exception as e:
                    print(f" Failed to delete {file}: {e}")
                    
    print(f"Cleanup completed. Checked {total_checked} files, deleted {deleted_count} empty files.")


def export_darktrace_logs(start_date: str, end_date: str = None, hour: int = None, index_prefix: str = None):
    base_prefix = clean_index_prefix(index_prefix)
    print(f"Using index prefix: {base_prefix}")
    
    if end_date is None:
        end_date = start_date
        
    start_dt = datetime.strptime(start_date, "%Y-%m-%d")
    end_dt = datetime.strptime(end_date, "%Y-%m-%d")
    current_dt = start_dt

    print(f"Starting NDJSON export (resume-friendly mode)...\n")
    total_docs = 0

    while current_dt <= end_dt:
        date_str = current_dt.strftime("%Y-%m-%d")
        folder_date = current_dt.strftime("%Y%m%d")
        daily_index = f"{base_prefix}-{current_dt.strftime('%Y.%m.%d')}"
        
        hours_to_process = [hour] if hour is not None else range(24)
        
        for h in hours_to_process:
            start_time = current_dt.replace(hour=h, minute=0, second=0, microsecond=0).isoformat() + "Z"
            end_time = current_dt.replace(hour=h, minute=59, second=59, microsecond=999999).isoformat() + "Z"
            
            print(f"Processing {date_str} hour {h:02d} | Index: {daily_index}")
            
            try:
                if not es.indices.exists(index=daily_index):
                    print(f"   → Index not found: {daily_index} | Skipping...")
                    continue

                file_index, current_file_path, current_size = get_last_file_info(base_prefix, folder_date, h)
                
                pit = es.open_point_in_time(index=daily_index, keep_alive=KEEP_ALIVE)
                pit_id = pit["id"]
                search_after = None
                f = None
                
                try:
                    folder = ensure_folder(base_prefix, folder_date)
                    
                    if current_file_path and current_size < MAX_FILE_SIZE:
                        f = open(current_file_path, "a", encoding="utf-8")
                        print(f" → Resuming: {os.path.basename(current_file_path)}")
                    else:
                        file_index += 1
                        filename = f"{folder_date}_{h:02d}_{file_index:02d}.json"
                        current_file_path = os.path.join(folder, filename)
                        f = open(current_file_path, "w", encoding="utf-8")
                        print(f" → Created: {filename}")

                    while True:
                        body = {
                            "size": BATCH_SIZE,
                            "query": {
                                "bool": {
                                    "filter": [{"range": {TIMESTAMP_FIELD: {"gte": start_time, "lt": end_time}}}]
                                }
                            },
                            "pit": {"id": pit_id, "keep_alive": KEEP_ALIVE},
                            "sort": ["_doc"]
                        }
                        if search_after:
                            body["search_after"] = search_after

                        # IMPORTANT: Do NOT pass index= when using PIT
                        resp = es.search(**body)

                        hits = resp["hits"]["hits"]
                        if not hits:
                            break

                        for hit in hits:
                            doc = hit["_source"]
                            
                            if os.path.getsize(current_file_path) >= MAX_FILE_SIZE:
                                f.close()
                                file_index += 1
                                filename = f"{folder_date}_{h:02d}_{file_index:02d}.json"
                                current_file_path = os.path.join(folder, filename)
                                f = open(current_file_path, "w", encoding="utf-8")
                                print(f" → New file: {filename} (size limit reached)")

                            json.dump(doc, f, ensure_ascii=False, default=str)
                            f.write("\n")
                            total_docs += 1

                        search_after = hits[-1]["sort"]

                finally:
                    if f:
                        f.close()
                    es.close_point_in_time(id=pit_id)
                    
                print(f" Hour {h:02d} completed.\n")

            except NotFoundError:
                print(f"   → Index not found: {daily_index} | Skipping...\n")
                continue
            except Exception as e:
                print(f"   → Error processing {daily_index}: {e} | Skipping...\n")
                continue
        
        current_dt += timedelta(days=1)

    clean_empty_files()
    print(f"Export finished successfully! Total documents: {total_docs:,}")


# ====================== MAIN ======================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Elasticsearch NDJSON Export - Daily Indices")
    parser.add_argument("--start", required=True, help="Start date (YYYY-MM-DD)")
    parser.add_argument("--end", help="End date (YYYY-MM-DD)")
    parser.add_argument("--hour", type=int, choices=range(24), help="Export only specific hour (0-23)")
    parser.add_argument("--index-prefix", help="Index prefix (e.g. fortigate.firewall or fortigate.firewall-2025.06.01)")
    
    args = parser.parse_args()
    
    export_darktrace_logs(
        start_date=args.start,
        end_date=args.end,
        hour=args.hour,
        index_prefix=args.index_prefix
    )
