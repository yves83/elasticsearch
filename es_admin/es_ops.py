#!/usr/bin/env python3
import os
import sys
import json
import yaml
import argparse
from pathlib import Path
from urllib.parse import urljoin

# ====================== LIBRARIES BUNDLING ======================
LIBS_DIR = Path("./libs")
if LIBS_DIR.exists():
    sys.path.insert(0, str(LIBS_DIR.absolute()))

import requests
requests.packages.urllib3.disable_warnings()


def load_templates(action_dir="action"):
    templates = {}
    action_path = Path(action_dir)
    if not action_path.exists():
        print(f"Error: '{action_dir}' directory not found!")
        sys.exit(1)

    for ext in ["*.yaml", "*.yml", "*.tpl", "*.tmp"]:
        for file in action_path.glob(ext):
            try:
                if file.suffix in [".yaml", ".yml"]:
                    templates[file.stem] = parse_yaml_template(file)
                else:
                    templates[file.stem] = parse_legacy_template(file)
            except Exception as e:
                print(f"Warning: Failed to load {file}: {e}")
    return templates


def parse_yaml_template(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)
    
    template = {
        "name": data.get("name", file_path.stem),
        "description": data.get("description", ""),
        "parameters": {},
        "query": data.get("query", ""),
        "method": "GET"
    }
    
    for param_name, param_info in data.get("parameters", {}).items():
        if isinstance(param_info, dict):
            desc = param_info.get("description", "")
            default = param_info.get("default")
        else:
            desc = str(param_info)
            default = None
        template["parameters"][param_name] = (desc, default)
    
    q = template["query"].strip().upper()
    if q.startswith("POST"):   template["method"] = "POST"
    elif q.startswith("PUT"):  template["method"] = "PUT"
    elif q.startswith("DELETE"): template["method"] = "DELETE"
    
    return template


def parse_legacy_template(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    return {
        "name": file_path.stem,
        "description": "",
        "parameters": {},
        "query": content,
        "method": "GET"
    }


def get_env_config():
    es_url = os.getenv("ES_URL")
    es_user = os.getenv("ES_USER")
    es_password = os.getenv("ES_PASSWORD")

    if not es_url:
        print("Error: ES_URL environment variable is not set!")
        print("Please set it using:")
        print("   export ES_URL='http://your-elasticsearch:9200'")
        print("   export ES_USER='elastic'")
        print("   export ES_PASSWORD='your_password'")
        sys.exit(1)

    if not es_user or not es_password:
        print("Warning: ES_USER or ES_PASSWORD is not set. Running without authentication.")

    return es_url.rstrip("/"), es_user, es_password


def parse_command_line():
    parser = argparse.ArgumentParser(description="Elasticsearch Admin Tool")
    parser.add_argument("action", nargs="?", help="Action name (e.g. snapshot_restore)")
    parser.add_argument("--list", action="store_true", help="List all available actions")
    
    args, unknown = parser.parse_known_args()
    
    param_dict = {}
    i = 0
    while i < len(unknown):
        if unknown[i].startswith("--"):
            key = unknown[i][2:]
            if i + 1 < len(unknown) and not unknown[i+1].startswith("--"):
                param_dict[key] = unknown[i+1]
                i += 2
            else:
                param_dict[key] = ""
                i += 1
        else:
            i += 1
    return args, param_dict


def main():
    templates = load_templates()
    if not templates:
        print("No templates found in 'action' folder!")
        sys.exit(1)

    args, cli_params = parse_command_line()

    if args.list:
        print("Available actions:")
        for name in sorted(templates.keys()):
            desc = templates[name]["description"]
            short = (desc[:97] + "...") if len(desc) > 100 else desc
            print(f" • {name} - {short}")
        sys.exit(0)

    if not args.action:
        # Interactive mode
        print("=== Elasticsearch Admin Tool ===\n")
        print("Available actions:")
        for i, name in enumerate(sorted(templates.keys()), 1):
            desc = templates[name]["description"]
            short = (desc[:97] + "...") if len(desc) > 100 else desc
            print(f"{i:3}. {name} - {short}")
        
        try:
            choice = int(input("\nSelect action number: ")) - 1
            action_name = list(sorted(templates.keys()))[choice]
        except:
            print("Invalid selection!")
            sys.exit(1)
    else:
        action_name = args.action
        if action_name not in templates:
            print(f"Error: Action '{action_name}' not found!")
            print("Available actions:", ", ".join(sorted(templates.keys())))
            sys.exit(1)

    template = templates[action_name]
    print(f"\nSelected: {action_name}")
    print(f"Description: {template['description'] or 'No description'}\n")

    # === NEW VALIDATION LOGIC ===
    param_values = {}
    missing_params = []

    for param_name, (desc, default) in template["parameters"].items():
        if param_name in cli_params:
            param_values[param_name] = cli_params[param_name]
        elif default is not None:
            param_values[param_name] = str(default)
        else:
            # Required parameter with no default and not provided via CLI
            missing_params.append(f"  --{param_name}   ({desc})")

    if missing_params:
        print("Error: Missing required parameters!")
        print("\nRequired parameters:")
        for p in missing_params:
            print(p)
        print("\nExample:")
        print(f"   python {sys.argv[0]} {action_name} " + " ".join([f"--{p.split()[0][2:]}" for p in missing_params[:2]] + ["..."]))
        sys.exit(1)

    # All parameters are resolved
    final_query = template["query"]
    for param, value in param_values.items():
        final_query = final_query.replace(f"###{param}###", value)

    print("\n--- Executing Query ---")
    print(final_query)
    print("-" * 80)

    es_url, user, pwd = get_env_config()
    execute_query(es_url, final_query, user, pwd)


def execute_query(es_url, query_str, username, password):
    lines = query_str.strip().split('\n', 1)
    first_line = lines[0].strip()
    parts = first_line.split(maxsplit=1)
    method = parts[0].upper()
    path = parts[1] if len(parts) > 1 else ""
    body = lines[1].strip() if len(lines) > 1 else None

    full_url = urljoin(es_url + "/", path.lstrip("/"))
    auth = (username, password) if username and password else None
    headers = {"Content-Type": "application/json"} if body else {}

    try:
        if method == "GET":
            resp = requests.get(full_url, auth=auth, headers=headers, timeout=60, verify=False)
        elif method == "POST":
            resp = requests.post(full_url, data=body, auth=auth, headers=headers, timeout=60, verify=False)
        elif method == "PUT":
            resp = requests.put(full_url, data=body, auth=auth, headers=headers, timeout=60, verify=False)
        elif method == "DELETE":
            resp = requests.delete(full_url, auth=auth, headers=headers, timeout=60, verify=False)
        else:
            print(f"Unsupported method: {method}")
            return

        print(f"\nStatus Code: {resp.status_code}")
        try:
            print(json.dumps(resp.json(), indent=2))
        except:
            print(resp.text)
    except Exception as e:
        print(f"Request failed: {e}")


if __name__ == "__main__":
    main()
