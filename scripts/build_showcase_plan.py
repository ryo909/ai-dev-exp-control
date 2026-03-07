#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import datetime, timezone


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def latest_tower(cdir):
    files = glob.glob(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))
    if not files:
        return ""
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def to_rel(path, cdir):
    if not path:
        return ""
    try:
        return os.path.relpath(path, cdir)
    except Exception:
        return path


def score_slot(item):
    tier = item.get("recommended_complexity_tier", "small")
    comp_count = int(item.get("recommended_component_count", 0) or 0)
    enhancement = bool(item.get("adopt_competitor_enhancement", False))

    tier_weight = {"large": 3, "medium": 2, "small": 1}.get(tier, 1)
    return (tier_weight * 10) + comp_count + (2 if enhancement else 0)


def build_candidates(days):
    ranked = sorted(days, key=score_slot, reverse=True)
    primary = [d for d in ranked if d.get("recommended_complexity_tier") == "large"]
    if len(primary) < 2:
        primary.extend([d for d in ranked if d.get("recommended_complexity_tier") == "medium"])

    out = []
    used_slots = set()
    for rec in primary:
        slot = int(rec.get("slot", 0) or 0)
        if slot <= 0 or slot in used_slots:
            continue
        used_slots.add(slot)
        out.append(
            {
                "slot": slot,
                "recommended_complexity_tier": rec.get("recommended_complexity_tier", "small"),
                "recommended_component_count": int(rec.get("recommended_component_count", 0) or 0),
                "recommended_components": rec.get("recommended_components", []) if isinstance(rec.get("recommended_components", []), list) else [],
                "adopt_competitor_enhancement": bool(rec.get("adopt_competitor_enhancement", False)),
                "priority_score": score_slot(rec),
            }
        )
        if len(out) >= 2:
            break

    return out


def main():
    parser = argparse.ArgumentParser(description="Build showcase planner candidates from next batch plan")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--plan", default="")
    parser.add_argument("--out", default="plans/showcase_plan.json")
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    plan_path = args.plan or os.path.join(cdir, "plans", "next_batch_plan.json")
    if not os.path.exists(plan_path):
        print("[build_showcase_plan] next_batch_plan not found; skip")
        return 0

    try:
        plan = read_json(plan_path)
    except Exception as e:
        print(f"[build_showcase_plan] failed to read next_batch_plan: {e}; skip")
        return 0

    days = plan.get("days", []) if isinstance(plan.get("days", []), list) else []
    if not days:
        print("[build_showcase_plan] plan days are empty; skip")
        return 0

    tower_path = latest_tower(cdir)
    candidates = build_candidates(days)

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_next_batch_plan": to_rel(plan_path, cdir),
        "source_control_tower": to_rel(tower_path, cdir),
        "showcase_candidates": candidates,
        "notes": [
            "showcase slots prioritize large tier, then medium when large is insufficient",
            "this planner is advisory and requires explicit adoption",
        ],
    }

    out_path = os.path.join(cdir, args.out)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"[build_showcase_plan] wrote: {to_rel(out_path, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
