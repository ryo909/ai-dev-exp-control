#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import datetime, timezone


def latest_scan(control_dir: str) -> str | None:
    pattern = os.path.join(control_dir, "reports", "competitors", "competitor_scan_*_shortlist.json")
    files = glob.glob(pattern)
    if not files:
        return None
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def ensure_day(day: str) -> str:
    s = str(day).replace("Day", "")
    return s.zfill(3)


def to_rel(path: str, base: str) -> str:
    try:
        return os.path.relpath(path, base)
    except Exception:
        return path


def build_candidates(twists: list[str], one_sentences: list[str], common_patterns: list[str], dont_copy: list[str]):
    if not twists or not one_sentences:
        return []

    count = min(3, max(len(twists), len(one_sentences)))
    out = []
    for i in range(count):
        t = twists[i % len(twists)]
        o = one_sentences[i % len(one_sentences)]
        score = round(max(0.5, 0.84 - (i * 0.06)), 2)
        out.append(
            {
                "id": f"cand_{i + 1}",
                "twist": t,
                "one_sentence": o,
                "why": (common_patterns or [])[:2],
                "dont_copy": dont_copy or [],
                "adoption_score": score,
            }
        )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Build enhanced plan candidates from latest competitor scan JSON")
    parser.add_argument("--day", required=True)
    parser.add_argument("--genre", required=True)
    parser.add_argument("--theme", required=True)
    parser.add_argument("--core-action", required=True)
    parser.add_argument("--twist", required=True)
    parser.add_argument("--one-sentence", required=True)
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--out-dir", default="plans/candidates")
    args = parser.parse_args()

    control_dir = os.path.abspath(args.control_dir)
    scan_path = latest_scan(control_dir)
    if not scan_path:
        print("[build_enhanced_plan_candidates] latest competitor scan json not found; skip")
        return 0

    try:
        scan = load_json(scan_path)
    except Exception as e:
        print(f"[build_enhanced_plan_candidates] failed to read scan json: {e}; skip")
        return 0

    twists = [x for x in (scan.get("twist_candidates") or []) if isinstance(x, str) and x.strip()]
    one_sentences = [x for x in (scan.get("one_sentence_candidates") or []) if isinstance(x, str) and x.strip()]
    common_patterns = [x for x in (scan.get("common_patterns") or []) if isinstance(x, str) and x.strip()]
    dont_copy = [x for x in (scan.get("dont_copy") or []) if isinstance(x, str) and x.strip()]

    candidates = build_candidates(twists, one_sentences, common_patterns, dont_copy)
    if not candidates:
        print("[build_enhanced_plan_candidates] no valid candidates; skip")
        return 0

    day = ensure_day(args.day)
    out_dir = os.path.join(control_dir, args.out_dir)
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"day{day}_enhanced_candidates.json")

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "day": day,
        "source_competitor_scan": to_rel(scan_path, control_dir),
        "context": {
            "genre": args.genre,
            "theme": args.theme,
            "core_action": args.core_action,
        },
        "original": {
            "twist": args.twist,
            "one_sentence": args.one_sentence,
        },
        "candidates": candidates,
        "recommended_candidate_id": candidates[0]["id"],
    }

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"[build_enhanced_plan_candidates] wrote: {to_rel(out_path, control_dir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
