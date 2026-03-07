#!/usr/bin/env python3
import argparse, json
from datetime import datetime, timezone

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in-json", required=True)
    ap.add_argument("--out-json", required=True)
    ap.add_argument("--limit", type=int, default=30)
    args = ap.parse_args()

    d = json.load(open(args.in_json, "r", encoding="utf-8"))
    items = d.get("items", [])
    items = [x for x in items if "collector_error" not in (x.get("tags") or [])]
    items = [x for x in items if (x.get("title") or "").strip() and (x.get("url") or "").strip()]
    items = sorted(items, key=lambda x: float(x.get("weight", 0.0)), reverse=True)[: args.limit]

    out = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "items": items
    }
    json.dump(out, open(args.out_json, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

if __name__ == "__main__":
    main()
