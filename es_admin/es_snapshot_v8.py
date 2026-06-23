#!/usr/bin/python3.9 
#
#  This script is compatibale Elastic Search 7.x / 8.x or 9.x
#

import os
import sys
import json
import argparse
from pathlib import Path

# ====================== LIBRARIES BUNDLING ======================
LIBS_DIR = Path("./libs")
if LIBS_DIR.exists():
    sys.path.insert(0, str(LIBS_DIR.absolute()))

import warnings
from elasticsearch import Elasticsearch
from elastic_transport import SecurityWarning

warnings.filterwarnings("ignore", category=SecurityWarning)

import requests
from requests.auth import HTTPBasicAuth
requests.packages.urllib3.disable_warnings()


def main():
    # Parse arguments
    parser = argparse.ArgumentParser(description="Elasticsearch Snapshot Management Tool (using requests)")
    parser.add_argument("repo", nargs="?", help="Repository name (REPO). Required unless --list-repo is used.")
    parser.add_argument("--uniq", action="store_true", help="Deduplicate by index name (FIFO)")
    parser.add_argument("--list-repo", action="store_true", help="List all configured snapshot repositories")
    args = parser.parse_args()

    # Get ES connection details from ENV
    es_url = os.getenv("ES_URL")
    es_user = os.getenv("ES_USER")
    es_password = os.getenv("ES_PASSWORD")

    if not es_url:
        print("Error: ES_URL environment variable is not set.", file=sys.stderr)
        print("Please set the following environment variables:", file=sys.stderr)
        print("  export ES_URL='https://your-es-host:9200'", file=sys.stderr)
        print("  export ES_USER='your_username'", file=sys.stderr)
        print("  export ES_PASSWORD='your_password'", file=sys.stderr)
        sys.exit(1)

    # Clean URL (remove trailing slash if present)
    es_url = es_url.rstrip('/')

    # Create session with auth
    session = requests.Session()
    if es_user and es_password:
        session.auth = HTTPBasicAuth(es_user, es_password)
    else:
        print("Warning: ES_USER or ES_PASSWORD not set. Trying without authentication.", file=sys.stderr)

    # Disable SSL verification warning (optional)
    requests.packages.urllib3.disable_warnings()

    # Handle --list-repo
    if args.list_repo:
        try:
            resp = session.get(f"{es_url}/_snapshot", verify=False, timeout=60)
            resp.raise_for_status()
            repos = resp.json()

            print("Configured Snapshot Repositories:")
            if not repos or not repos.get("repositories"):
                print("No repositories found.")
            else:
                for repo_name, info in repos["repositories"].items():
                    repo_type = info.get("type", "unknown")
                    print(f"- {repo_name} (Type: {repo_type})")
        except requests.exceptions.RequestException as e:
            print(f"Error fetching repositories: {e}", file=sys.stderr)
        sys.exit(0)

    # Require repo name if not listing repos
    if not args.repo:
        print("Error: Repository name is required.", file=sys.stderr)
        parser.print_help()
        sys.exit(1)

    repo = args.repo

    try:
        # Get all snapshots in the repository
        resp = session.get(f"{es_url}/_snapshot/{repo}/_all", verify=False, timeout=60)
        resp.raise_for_status()
        data = resp.json()
        snapshots = data.get("snapshots", [])
    except requests.exceptions.RequestException as e:
        print(f"Error fetching snapshots from repository '{repo}': {e}", file=sys.stderr)
        sys.exit(1)

    if not snapshots:
        print(f"No snapshots found in repository: {repo}")
        sys.exit(0)

    print("REPO SNAPSHOT_NAME INDEXES")

    if args.uniq:
        # Dedup by index name, FIFO (keep first occurrence)
        seen_indices = {}
        for snap in snapshots:
            snap_name = snap.get("snapshot")
            indices = snap.get("indices", [])
            for idx in indices:
                if idx not in seen_indices:
                    seen_indices[idx] = (repo, snap_name, idx)
        # Print in order of first appearance
        for repo_name, snap_name, idx in seen_indices.values():
            print(f"{repo_name} {snap_name} {idx}")
    else:
        # Print all
        for snap in snapshots:
            snap_name = snap.get("snapshot")
            indices = snap.get("indices", [])
            for idx in indices:
                print(f"{repo} {snap_name} {idx}")


if __name__ == "__main__":
    main()
