#!/usr/bin/env python3
import argparse
import json
import os
from datetime import datetime, timezone


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def normalize_day(day_value):
    s = "".join(ch for ch in str(day_value or "") if ch.isdigit())
    if not s:
        return ""
    return f"{int(s):03d}"


def parse_days_csv(days_csv):
    out = []
    for p in str(days_csv or "").split(","):
        d = normalize_day(p)
        if d:
            out.append(d)
    return sorted(set(out))


def build_item(day, yt_lookup):
    src = yt_lookup.get(day, {})
    return {
        "day": day,
        "videoUrl": src.get("videoUrl", "") or f"https://www.youtube.com/watch?v=REPLACE_DAY{day}",
        "titleOverride": src.get("title", "") or "",
        "descriptionOverride": src.get("description", "") or "",
        "thumbnailUrl": src.get("thumbnailUrl", "") or "",
        "dueAtOverride": src.get("dueAt", "") or "",
        "privacy": src.get("privacy", "public") or "public",
        "madeForKids": bool(src.get("madeForKids", False)),
        "notifySubscribers": bool(src.get("notifySubscribers", True)),
        "playlistCandidate": src.get("playlistCandidate", "") or "",
        "audience": src.get("audience", "general") or "general",
        "shortsCandidate": bool(src.get("shortsCandidate", True)),
    }


def main():
    parser = argparse.ArgumentParser(description="Generate youtube_video_handoff_latest.json template")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", required=True)
    parser.add_argument("--days", default="")
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    days = parse_days_csv(args.days)
    if not days:
        raise SystemExit("days is empty")

    make_payload_path = os.path.join(cdir, "exports", "launch", f"make_payload_{args.date}.json")
    yt_lookup = {}
    if os.path.exists(make_payload_path):
        payload = read_json(make_payload_path)
        for item in payload.get("youtube_items", []) if isinstance(payload.get("youtube_items", []), list) else []:
            d = normalize_day(item.get("day"))
            if not d:
                continue
            yt_lookup[d] = {
                "title": item.get("title", ""),
                "description": item.get("description", ""),
                "thumbnailUrl": item.get("thumbnailUrl", ""),
                "dueAt": item.get("dueAt", ""),
                "privacy": item.get("privacy", "public"),
                "madeForKids": item.get("madeForKids", False),
                "notifySubscribers": item.get("notifySubscribers", True),
                "playlistCandidate": item.get("playlistCandidate", ""),
                "audience": item.get("audience", "general"),
                "shortsCandidate": item.get("shortsCandidate", True),
                "videoUrl": item.get("videoUrl", ""),
            }

    out = {
        "schema_version": "youtube_video_handoff.v1",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": f"template_from_make_payload_{args.date}",
        "note": "Fill videoUrl values and optional overrides. This file is read by build_launch_exports.py.",
        "items": [build_item(d, yt_lookup) for d in days],
    }

    output = args.output or os.path.join(cdir, "imports", "publish", "youtube_video_handoff_latest.json")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    write_json(output, out)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
