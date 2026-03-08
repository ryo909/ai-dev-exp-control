#!/usr/bin/env python3
import argparse
import json
import os


def main() -> int:
    parser = argparse.ArgumentParser(description="Read one slot recommendation from plans/next_batch_plan.json")
    parser.add_argument("--day", required=True, help="Day number like 3 or 003")
    parser.add_argument("--plan", default="")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    plan_path = args.plan or os.path.join(cdir, "plans", "next_batch_plan.json")

    if not os.path.exists(plan_path):
        print("{}")
        return 0

    try:
        with open(plan_path, "r", encoding="utf-8") as f:
            plan = json.load(f)
    except Exception:
        print("{}")
        return 0

    day_num = int(str(args.day).replace("Day", ""))
    slot = ((day_num - 1) % 7) + 1

    rec = None
    for item in plan.get("days", []):
        if isinstance(item, dict) and int(item.get("slot", -1)) == slot:
            rec = item
            break

    if not rec:
        print("{}")
        return 0

    out = {
        "slot": int(rec.get("slot", slot)),
        "recommended_complexity_tier": rec.get("recommended_complexity_tier", ""),
        "recommended_component_count": int(rec.get("recommended_component_count", 0) or 0),
        "recommended_components": rec.get("recommended_components", []) if isinstance(rec.get("recommended_components", []), list) else [],
        "adopt_competitor_enhancement": bool(rec.get("adopt_competitor_enhancement", False)),
        "notes": rec.get("notes", []) if isinstance(rec.get("notes", []), list) else [],
    }
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
