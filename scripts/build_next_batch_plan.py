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
        return None
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def latest_showcase(cdir):
    files = glob.glob(os.path.join(cdir, "reports", "showcase", "showcase_plan_*.json"))
    if not files:
        return None
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def tier_slots(mix):
    seq = []
    seq += ["small"] * int(mix.get("small", 0))
    seq += ["medium"] * int(mix.get("medium", 0))
    seq += ["large"] * int(mix.get("large", 0))
    while len(seq) < 7:
        seq.append("small")
    return seq[:7]


def apply_showcase_annotations(payload, showcase):
    if not isinstance(showcase, dict):
        return payload

    selected_slot = int(showcase.get("selected_showcase_slot", 0) or 0)
    selected = showcase.get("selected_showcase_plan", {}) or {}
    candidate_map = {}
    for c in showcase.get("candidate_slots", []):
        slot = int(c.get("slot", 0) or 0)
        candidate_map[slot] = c

    if selected_slot > 0:
        payload["showcase_slot"] = selected_slot
        payload["showcase_goal"] = selected.get("showcase_goal", "")
        payload["showcase_component_bias"] = selected.get("component_bias", [])
        payload["showcase_adopt_competitor_enhancement"] = bool(selected.get("adopt_competitor_enhancement", False))
        payload["showcase_fallback_tier"] = selected.get("fallback_tier_if_needed", "")

    for day in payload.get("days", []):
        slot = int(day.get("slot", 0) or 0)
        cand = candidate_map.get(slot)
        day["is_showcase_candidate"] = bool(cand)
        day["is_selected_showcase"] = slot == selected_slot
        if cand:
            day["showcase_score"] = (cand.get("scores", {}) or {}).get("total", 0.0)

    return payload


def main():
    parser = argparse.ArgumentParser(description="Build next batch recommendation plan from control tower")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    tower_path = latest_tower(cdir)
    if not tower_path:
        print("[build_next_batch_plan] control tower json not found; skip")
        return 0

    tower = read_json(tower_path)
    mix = ((tower.get("next_batch_recommendations") or {}).get("recommended_tier_mix") or {"small": 4, "medium": 2, "large": 1})

    profiles_path = os.path.join(cdir, "system", "complexity_profiles.json")
    profiles = read_json(profiles_path) if os.path.exists(profiles_path) else {}

    slots = tier_slots(mix)
    days = []
    for i, tier in enumerate(slots, start=1):
        pref = (profiles.get(tier, {}) or {}).get("preferred_components") or []
        rc = int((profiles.get(tier, {}) or {}).get("recommended_count", 1))
        days.append(
            {
                "slot": i,
                "recommended_complexity_tier": tier,
                "recommended_component_count": rc,
                "recommended_components": pref[:rc],
                "adopt_competitor_enhancement": (tier != "small"),
                "notes": ["bias away from duplicate core_action", "use selected_components first"],
            }
        )

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_control_tower": os.path.relpath(tower_path, cdir),
        "recommended_tier_mix": mix,
        "days": days,
    }

    showcase_path = latest_showcase(cdir)
    if showcase_path:
        try:
            showcase = read_json(showcase_path)
            payload = apply_showcase_annotations(payload, showcase)
            payload["source_showcase_plan"] = os.path.relpath(showcase_path, cdir)
        except Exception:
            pass

    out_path = os.path.join(cdir, "plans", "next_batch_plan.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"[build_next_batch_plan] wrote: {os.path.relpath(out_path, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
