#!/usr/bin/env python3
import argparse
import json
import os
from datetime import datetime, timezone


def load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def ensure_day(day: str) -> str:
    s = str(day).replace("Day", "")
    return s.zfill(3)


def parts(profile: dict) -> set[str]:
    req = profile.get("required_parts") or []
    opt = profile.get("optional_parts") or []
    return set([p for p in req + opt if isinstance(p, str)])


def to_rel(path: str, base: str) -> str:
    try:
        return os.path.relpath(path, base)
    except Exception:
        return path


def main() -> int:
    parser = argparse.ArgumentParser(description="Write fallback plan candidate for failed day")
    parser.add_argument("--day", required=True)
    parser.add_argument("--summary", default="")
    parser.add_argument("--state-file", default="")
    parser.add_argument("--profiles", default="")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--out-dir", default="plans/candidates")
    args = parser.parse_args()

    control_dir = os.path.abspath(args.control_dir)
    state_path = args.state_file or os.path.join(control_dir, "STATE.json")
    profiles_path = args.profiles or os.path.join(control_dir, "system", "complexity_profiles.json")

    if not os.path.exists(state_path) or not os.path.exists(profiles_path):
        print("[write_fallback_plan] state/profiles missing; skip")
        return 0

    state = load_json(state_path)
    profiles = load_json(profiles_path)
    day = ensure_day(args.day)

    day_entry = ((state.get("days") or {}).get(day) or {})
    meta = day_entry.get("meta") or {}
    original_tier = meta.get("complexity_tier", "small")

    if original_tier not in profiles:
        original_tier = "small"

    suggested = profiles.get(original_tier, {}).get("fallback_to") or original_tier
    if suggested not in profiles:
        suggested = original_tier

    original_parts = parts(profiles.get(original_tier, {}))
    suggested_parts = parts(profiles.get(suggested, {}))

    kept = sorted(original_parts & suggested_parts)
    removed = sorted(original_parts - suggested_parts)

    summary_path = args.summary if args.summary else os.path.join(control_dir, "logs", f"Day{day}.summary.md")
    has_summary = os.path.exists(summary_path)

    retry_recommended = suggested != original_tier
    if original_tier == "small":
        retry_recommended = False

    reason = f"smoke/build failure; downgrade {original_tier} -> {suggested} to reduce component surface"
    if not has_summary:
        reason += " (summary missing)"

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "day": day,
        "summary": to_rel(summary_path, control_dir) if has_summary else "",
        "original_complexity_tier": original_tier,
        "suggested_complexity_tier": suggested,
        "removed_parts": removed,
        "kept_parts": kept,
        "reason": reason,
        "retry_recommended": retry_recommended,
    }

    out_dir = os.path.join(control_dir, args.out_dir)
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"day{day}_fallback_plan.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"[write_fallback_plan] wrote: {to_rel(out_path, control_dir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
