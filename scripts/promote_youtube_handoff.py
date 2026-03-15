#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
from datetime import datetime, timezone


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def latest(pattern):
    files = sorted(glob.glob(pattern))
    return files[-1] if files else ""


def normalize_day_token(value):
    s = re.sub(r"[^0-9]", "", str(value or ""))
    if not s:
        return ""
    return f"{int(s):03d}"


def parse_days_csv(days_csv):
    out = []
    for p in str(days_csv or "").split(","):
        d = normalize_day_token(p)
        if d:
            out.append(d)
    return sorted(set(out))


def is_placeholder_url(value):
    s = str(value or "").strip()
    return bool(s) and ("REPLACE_" in s or "PLACEHOLDER" in s)


def as_bool(v, default=None):
    if isinstance(v, bool):
        return v
    if v is None:
        return default
    s = str(v).strip().lower()
    if s in {"1", "true", "yes", "y"}:
        return True
    if s in {"0", "false", "no", "n"}:
        return False
    return default


def pick_text(rec, keys):
    if not isinstance(rec, dict):
        return ""
    for k in keys:
        if k not in rec or rec.get(k) is None:
            continue
        s = str(rec.get(k)).strip()
        if s:
            return s
    return ""


def parse_handoff_records(raw):
    records = {}
    if isinstance(raw, dict) and isinstance(raw.get("items"), list):
        items = [x for x in raw.get("items", []) if isinstance(x, dict)]
    elif isinstance(raw, list):
        items = [x for x in raw if isinstance(x, dict)]
    elif isinstance(raw, dict):
        items = []
        for k, v in raw.items():
            if isinstance(v, dict):
                vv = dict(v)
                vv["day"] = k
                items.append(vv)
    else:
        items = []

    for rec in items:
        day = normalize_day_token(rec.get("day") or rec.get("tool_day") or rec.get("tool_id") or rec.get("id"))
        if not day:
            continue
        records[day] = {
            "videoUrl": pick_text(rec, ["videoUrl", "video_url", "youtubeUrl", "youtube_url", "url"]),
            "titleOverride": pick_text(rec, ["titleOverride", "title"]),
            "descriptionOverride": pick_text(rec, ["descriptionOverride", "description"]),
            "thumbnailUrl": pick_text(rec, ["thumbnailUrl", "thumbnail_url", "thumbUrl", "thumb_url"]),
            "dueAtOverride": pick_text(rec, ["dueAtOverride", "dueAt", "due_at", "scheduledAt", "scheduled_at"]),
            "privacy": pick_text(rec, ["privacy"]),
            "madeForKids": rec.get("madeForKids"),
            "notifySubscribers": rec.get("notifySubscribers"),
            "playlistCandidate": pick_text(rec, ["playlistCandidate", "playlist"]),
            "audience": pick_text(rec, ["audience"]),
            "shortsCandidate": rec.get("shortsCandidate"),
        }
    return records


def load_make_payload_lookup(path):
    if not os.path.exists(path):
        return {}
    try:
        payload = read_json(path)
    except Exception:
        return {}
    out = {}
    items = payload.get("youtube_items", []) if isinstance(payload, dict) else []
    if not isinstance(items, list):
        return {}
    for rec in items:
        if not isinstance(rec, dict):
            continue
        day = normalize_day_token(rec.get("day"))
        if not day:
            continue
        out[day] = {
            "titleOverride": pick_text(rec, ["title"]),
            "descriptionOverride": pick_text(rec, ["description"]),
            "thumbnailUrl": pick_text(rec, ["thumbnailUrl"]),
            "dueAtOverride": pick_text(rec, ["dueAt"]),
            "privacy": pick_text(rec, ["privacy"]) or "public",
            "madeForKids": rec.get("madeForKids"),
            "notifySubscribers": rec.get("notifySubscribers"),
            "playlistCandidate": pick_text(rec, ["playlistCandidate"]),
            "audience": pick_text(rec, ["audience"]) or "general",
            "shortsCandidate": rec.get("shortsCandidate"),
            "videoUrl": pick_text(rec, ["videoUrl"]),
        }
    return out


def load_state_lookup(path):
    if not os.path.exists(path):
        return {}
    try:
        state = read_json(path)
    except Exception:
        return {}
    days = state.get("days", {}) if isinstance(state, dict) else {}
    out = {}
    for day, rec in (days.items() if isinstance(days, dict) else []):
        d = normalize_day_token(day)
        if not d or not isinstance(rec, dict):
            continue
        pages_url = str(rec.get("pages_url") or "").strip()
        derived_mp4 = ""
        derived_webm = ""
        if pages_url:
            base = pages_url if pages_url.endswith("/") else f"{pages_url}/"
            derived_mp4 = f"{base}media/demo.mp4"
            derived_webm = f"{base}media/demo.webm"
        out[d] = {
            "state_video": pick_text(rec, ["youtube_video_url", "youtube_url", "video_url", "videoUrl"]),
            "state_thumb": pick_text(rec, ["youtube_thumbnail_url", "thumbnail_url", "thumbnailUrl"]),
            "derived_mp4": derived_mp4,
            "derived_webm": derived_webm,
        }
    return out


def choose_video_url(candidates):
    chosen_value = ""
    chosen_source = ""
    for src, value in candidates:
        val = str(value or "").strip()
        if not val:
            continue
        if not chosen_value:
            chosen_value = val
            chosen_source = src
            continue
        if is_placeholder_url(chosen_value) and not is_placeholder_url(val):
            chosen_value = val
            chosen_source = src
    return chosen_value, chosen_source


def main():
    parser = argparse.ArgumentParser(description="Promote YouTube handoff inputs into imports/publish/youtube_video_handoff_latest.json")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", required=True)
    parser.add_argument("--days", default="")
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    imports_dir = os.path.join(cdir, "imports", "publish")
    exports_dir = os.path.join(cdir, "exports", "launch")

    p_latest = os.path.join(imports_dir, "youtube_video_handoff_latest.json")
    p_dated_import = os.path.join(imports_dir, f"youtube_video_handoff_{args.date}.json")
    p_export_dated = os.path.join(exports_dir, f"youtube_upload_handoff_{args.date}.json")
    p_export_latest = latest(os.path.join(exports_dir, "youtube_upload_handoff_*.json"))
    p_make_payload = os.path.join(exports_dir, f"make_payload_{args.date}.json")
    p_state = os.path.join(cdir, "STATE.json")

    latest_records = parse_handoff_records(read_json(p_latest)) if os.path.exists(p_latest) else {}
    dated_import_records = parse_handoff_records(read_json(p_dated_import)) if os.path.exists(p_dated_import) else {}
    export_dated_records = parse_handoff_records(read_json(p_export_dated)) if os.path.exists(p_export_dated) else {}
    export_latest_records = parse_handoff_records(read_json(p_export_latest)) if p_export_latest and os.path.exists(p_export_latest) else {}
    make_lookup = load_make_payload_lookup(p_make_payload)
    state_lookup = load_state_lookup(p_state)

    target_days = parse_days_csv(args.days)
    if not target_days:
        merged_days = set()
        merged_days.update(latest_records.keys())
        merged_days.update(dated_import_records.keys())
        merged_days.update(export_dated_records.keys())
        merged_days.update(export_latest_records.keys())
        merged_days.update(make_lookup.keys())
        target_days = sorted(merged_days)
    if not target_days:
        raise SystemExit("no target days found; pass --days")

    items_by_day = {k: dict(v) for k, v in latest_records.items()}
    unresolved = []
    for day in target_days:
        current = items_by_day.get(day, {})
        base = make_lookup.get(day, {})
        rec = {
            "day": day,
            "videoUrl": str(current.get("videoUrl", "") or base.get("videoUrl", "")).strip(),
            "titleOverride": str(current.get("titleOverride", "") or base.get("titleOverride", "")).strip(),
            "descriptionOverride": str(current.get("descriptionOverride", "") or base.get("descriptionOverride", "")).strip(),
            "thumbnailUrl": str(current.get("thumbnailUrl", "") or base.get("thumbnailUrl", "")).strip(),
            "dueAtOverride": str(current.get("dueAtOverride", "") or base.get("dueAtOverride", "")).strip(),
            "privacy": str(current.get("privacy", "") or base.get("privacy", "") or "public").strip(),
            "madeForKids": as_bool(current.get("madeForKids"), as_bool(base.get("madeForKids"), False)),
            "notifySubscribers": as_bool(current.get("notifySubscribers"), as_bool(base.get("notifySubscribers"), True)),
            "playlistCandidate": str(current.get("playlistCandidate", "") or base.get("playlistCandidate", "")).strip(),
            "audience": str(current.get("audience", "") or base.get("audience", "") or "general").strip(),
            "shortsCandidate": as_bool(current.get("shortsCandidate"), as_bool(base.get("shortsCandidate"), True)),
        }

        src_dated = dated_import_records.get(day, {})
        src_latest = latest_records.get(day, {})
        src_export_dated = export_dated_records.get(day, {})
        src_export_latest = export_latest_records.get(day, {})
        src_state = state_lookup.get(day, {})
        video_url, video_source = choose_video_url(
            [
                ("imports/publish/youtube_video_handoff_<date>.json", src_dated.get("videoUrl")),
                ("imports/publish/youtube_video_handoff_latest.json", src_latest.get("videoUrl")),
                ("exports/launch/youtube_upload_handoff_<date>.json", src_export_dated.get("videoUrl")),
                ("exports/launch/youtube_upload_handoff_latest.json", src_export_latest.get("videoUrl")),
                ("STATE.json", src_state.get("state_video")),
                ("STATE.pages_url/media/demo.mp4", src_state.get("derived_mp4")),
                ("STATE.pages_url/media/demo.webm", src_state.get("derived_webm")),
            ]
        )

        if video_url:
            rec["videoUrl"] = video_url
            rec["videoSource"] = video_source
        elif not rec["videoUrl"]:
            rec["videoUrl"] = f"https://www.youtube.com/watch?v=REPLACE_DAY{day}"
            rec["videoSource"] = "placeholder"

        if is_placeholder_url(rec["videoUrl"]):
            rec["assetStatus"] = "pending_asset"
            unresolved.append(day)
        else:
            rec["assetStatus"] = "ready"
        items_by_day[day] = rec

    out_items = sorted(items_by_day.values(), key=lambda x: x.get("day", ""))
    output_path = args.output or p_latest
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    out = {
        "schema_version": "youtube_video_handoff.v1",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": f"promote_youtube_handoff:{args.date}",
        "note": "Auto-merged from imports/exports/state. Replace placeholder videoUrl values as needed.",
        "target_days": target_days,
        "unresolved_days": sorted(set(unresolved)),
        "items": out_items,
    }
    write_json(output_path, out)
    print(output_path)
    print(f"target_days={','.join(target_days)}")
    print(f"resolved={len(target_days) - len(set(unresolved))}/{len(target_days)}")
    if unresolved:
        print(f"pending_asset_days={','.join(sorted(set(unresolved)))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
