#!/usr/bin/python
import os
import sys
import json
import argparse
from datetime import datetime, timedelta

# ====================== LOCAL LIB SUPPORT ======================
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LIB_PATH = os.path.join(SCRIPT_DIR, "lib")
if os.path.exists(LIB_PATH):
    sys.path.insert(0, LIB_PATH)
    print(f"Using local packages from: {LIB_PATH}")

from elasticsearch import Elasticsearch
from elasticsearch.exceptions import NotFoundError, BadRequestError
# ================================================================

# ========================= CONFIGURATION =========================
OUTPUT_BASE = "./darktrace_exports"
BATCH_SIZE = 2000
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
KEEP_ALIVE = "15m"
TIMESTAMP_FIELD = "@timestamp"
# ================================================================

# Load from Environment Variables
ES_URL = os.getenv("ES_URL")
ES_USER = os.getenv("ES_USER")
ES_PASSWORD = os.getenv("ES_PASSWORD")

if not ES_URL:
    print("Error: ES_URL environment variable is not set.")
    sys.exit(1)

es = Elasticsearch(
    ES_URL,
    basic_auth=(ES_USER, ES_PASSWORD) if ES_USER and ES_PASSWORD else None,
    request_timeout=60,
    max_retries=3,
    retry_on_timeout=True,
    verify_certs=False,
    ssl_show_warn=False
)


def index_exists(index_name: str) -> bool:
    """Safe way to check if index exists (compatible with ES 8.x)"""
    try:
        es.indices.get(index=index_name)
        return True
    except NotFoundError:
        return False
    except BadRequestError as e:
        print(f"   → BadRequest checking index {index_name}: {e}")
        # Try fallback
        try:
            resp = es.indices.exists(index=index_name)
            return resp
        except:
            return False
    except Exception as e:
        print(f"   → Error checking index {index_name}: {e}")
        return False


def ensure_folder(alias: str):
    folder = os.path.join(OUTPUT_BASE, alias)
    os.makedirs(folder, exist_ok=True)
    return folder


def get_date_from_timestamp(doc):
    try:
        ts = doc.get(TIMESTAMP_FIELD)
        if isinstance(ts, str):
            dt_str = ts.replace("Z", "+00:00")
            dt = datetime.fromisoformat(dt_str)
            return dt.strftime("%Y%m%d")
    except:
        pass
    return datetime.now().strftime("%Y%m%d")


def export_index_data(index_name: str, alias: str, start_date: str = None, end_date: str = None):
    print(f"Querying Index     : {index_name}")
    print(f"Output Folder Alias: {alias}")
    print(f"Export Path        : {os.path.join(OUTPUT_BASE, alias)}\n")
    
    if start_date is None:
        start_date = "2000-01-01"
    if end_date is None:
        end_date = datetime.now().strftime("%Y-%m-%d")

    start_dt = datetime.strptime(start_date, "%Y-%m-%d")
    end_dt = datetime.strptime(end_date, "%Y-%m-%d")
    
    total_docs = 0
    current_dt = start_dt

    while current_dt <= end_dt:
        date_str = current_dt.strftime("%Y-%m-%d")
        next_date = (current_dt + timedelta(days=1)).strftime("%Y-%m-%d")
        
        print(f"Processing {date_str} | Index: {index_name}")
        
        try:
            if not index_exists(index_name):
                print(f"   → Index not found: {index_name} | Skipping...")
                break

            pit = es.open_point_in_time(index=index_name, keep_alive=KEEP_ALIVE)
            pit_id = pit["id"]
            search_after = None
            f = None
            file_index = 0
            current_file_path = None
            current_doc_date = None

            try:
                base_folder = ensure_folder(alias)

                while True:
                    body = {
                        "size": BATCH_SIZE,
                        "query": {
                            "bool": {
                                "filter": [{"range": {TIMESTAMP_FIELD: {"gte": date_str, "lt": next_date}}}]
                            }
                        },
                        "pit": {"id": pit_id, "keep_alive": KEEP_ALIVE},
                        "sort": ["_doc"]
                    }
                    if search_after:
                        body["search_after"] = search_after

                    resp = es.search(**body)
                    hits = resp["hits"]["hits"]
                    if not hits:
                        break

                    for hit in hits:
                        doc = hit["_source"]
                        doc_date = get_date_from_timestamp(doc)

                        if (not current_file_path or 
                            current_doc_date != doc_date or 
                            os.path.getsize(current_file_path) >= MAX_FILE_SIZE):
                            
                            if f:
                                f.close()
                            file_index += 1
                            filename = f"{doc_date}_{file_index:02d}.json"
                            current_file_path = os.path.join(base_folder, filename)
                            f = open(current_file_path, "w", encoding="utf-8")
                            current_doc_date = doc_date
                            print(f"   → Created: {filename}")

                        json.dump(doc, f, ensure_ascii=False, default=str)
                        f.write("\n")
                        total_docs += 1

                    search_after = hits[-1]["sort"]

            finally:
                if f:
                    f.close()
                es.close_point_in_time(id=pit_id)

            print(f"   ✓ {date_str} completed.\n")

        except NotFoundError:
            print(f"   → Index not found: {index_name} | Skipping...\n")
            break
        except Exception as e:
            print(f"   → Error processing {index_name}: {e} | Skipping...\n")
            continue

        current_dt += timedelta(days=1)

    print(f"Export completed! Total documents: {total_docs:,}")


# ====================== MAIN ======================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Elasticsearch Export Tool")
    parser.add_argument("--index", required=True, help="Full index name or pattern to query in Elasticsearch")
    parser.add_argument("--alias", required=True, help="Short alias name used as output folder name")
    parser.add_argument("--start", help="Start date (YYYY-MM-DD)")
    parser.add_argument("--end", help="End date (YYYY-MM-DD)")
    
    args = parser.parse_args()
    
    export_index_data(
        index_name=args.index,
        alias=args.alias,
        start_date=args.start,
        end_date=args.end
    )
