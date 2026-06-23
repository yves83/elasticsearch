#!/usr/bin/python
import os
import sys
import json
import argparse
import requests
from datetime import datetime, timedelta
from requests.auth import HTTPBasicAuth

# ====================== CONFIGURATION =========================
OUTPUT_BASE = "./darktrace_exports"
BATCH_SIZE = 2000
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10MB
TIMESTAMP_FIELD = "@timestamp"
# ================================================================

# Load from Environment Variables
ES_URL = os.getenv("ES_URL")
ES_USER = os.getenv("ES_USER")
ES_PASSWORD = os.getenv("ES_PASSWORD")

if not ES_URL:
    print("Error: ES_URL environment variable is not set.")
    sys.exit(1)

# Remove trailing slash if present
ES_URL = ES_URL.rstrip('/')

session = requests.Session()
session.verify = False
session.headers.update({
    "Content-Type": "application/json",
    "Accept": "application/vnd.elasticsearch+json;compatible-with=8"
})

if ES_USER and ES_PASSWORD:
    session.auth = HTTPBasicAuth(ES_USER, ES_PASSWORD)


def index_exists(index_name: str) -> bool:
    """Check if index exists using requests"""
    try:
        resp = session.get(f"{ES_URL}/_cat/indices/{index_name}?format=json")
        if resp.status_code == 200:
            return len(resp.json()) > 0
        return False
    except:
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
                current_dt += timedelta(days=1)
                continue

            # Open Point in Time
            pit_resp = session.post(
                f"{ES_URL}/_pit",
                json={"keep_alive": "15m", "index": index_name}
            )
            pit_resp.raise_for_status()
            pit_id = pit_resp.json()["id"]

            search_after = None
            f = None
            file_index = 0
            current_file_path = None
            current_doc_date = None

            base_folder = ensure_folder(alias)

            while True:
                body = {
                    "size": BATCH_SIZE,
                    "query": {
                        "bool": {
                            "filter": [{"range": {TIMESTAMP_FIELD: {"gte": date_str, "lt": next_date}}}]
                        }
                    },
                    "pit": {"id": pit_id, "keep_alive": "15m"},
                    "sort": ["_doc"]
                }
                if search_after:
                    body["search_after"] = search_after

                resp = session.post(f"{ES_URL}/_search", json=body)
                resp.raise_for_status()
                data = resp.json()

                hits = data.get("hits", {}).get("hits", [])
                if not hits:
                    break

                for hit in hits:
                    doc = hit["_source"]
                    doc_date = get_date_from_timestamp(doc)

                    if (not current_file_path or 
                        current_doc_date != doc_date or 
                        (os.path.exists(current_file_path) and os.path.getsize(current_file_path) >= MAX_FILE_SIZE)):
                        
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

                search_after = hits[-1].get("sort")

            # Close PIT
            try:
                session.delete(f"{ES_URL}/_pit", json={"id": pit_id})
            except:
                pass

            print(f"   ✓ {date_str} completed.\n")

        except Exception as e:
            print(f"   → Error processing {index_name}: {e}")
        finally:
            if f:
                f.close()
            current_dt += timedelta(days=1)

    print(f"Export completed! Total documents: {total_docs:,}")


# ====================== MAIN ======================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Elasticsearch Export Tool (using requests)")
    parser.add_argument("--index", required=True, help="Full index name or pattern")
    parser.add_argument("--alias", required=True, help="Output folder alias")
    parser.add_argument("--start", help="Start date (YYYY-MM-DD)")
    parser.add_argument("--end", help="End date (YYYY-MM-DD)")
    
    args = parser.parse_args()
    
    export_index_data(
        index_name=args.index,
        alias=args.alias,
        start_date=args.start,
        end_date=args.end
    )
