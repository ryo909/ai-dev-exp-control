#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
from datetime import date, datetime, time, timedelta, timezone
from id_utils import (
    build_launch_id,
    build_post_id,
    normalize_cta_family,
    normalize_hook_family,
    normalize_post_type,
    normalize_tool_id,
)

WEEKDAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
DEFAULT_WEEKLY_SLOTS = {
    "mon": "21:00",
    "tue": "08:30",
    "wed": "12:10",
    "thu": "09:00",
    "fri": "08:30",
    "sat": "10:00",
    "sun": "21:00",
}


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def latest(pattern):
    files = glob.glob(pattern)
    if not files:
        return ""
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def rel(path, base):
    if not path:
        return ""
    try:
        return os.path.relpath(path, base)
    except Exception:
        return path


def clamp(v):
    if v < 0:
        return 0.0
    if v > 1:
        return 1.0
    return round(float(v), 3)


def is_hhmm(s):
    return bool(re.match(r"^([01][0-9]|2[0-3]):[0-5][0-9]$", str(s or "").strip()))


def normalize_weekly_slots(raw_slots):
    out = dict(DEFAULT_WEEKLY_SLOTS)
    if not isinstance(raw_slots, dict):
        return out
    for wk in WEEKDAY_KEYS:
        val = str(raw_slots.get(wk, "")).strip()
        if is_hhmm(val):
            out[wk] = val
    return out


def load_publish_schedule_policy(cdir):
    policy_path = os.path.join(cdir, "system", "publish_schedule_policy.json")
    base = {
        "version": "builtin-default",
        "timezone": "Asia/Tokyo",
        "timezone_offset": "+09:00",
        "start_offset_days": 1,
        "platforms": {
            "x": {"mode": "weekly_slots", "weekly_slots": dict(DEFAULT_WEEKLY_SLOTS)},
            "youtube": {
                "mode": "weekly_slots",
                "weekly_slots": dict(DEFAULT_WEEKLY_SLOTS),
                "privacy": "public",
                "madeForKids": False,
                "notifySubscribers": True,
            },
        },
    }
    if not os.path.exists(policy_path):
        return base, "builtin-default"
    try:
        raw = read_json(policy_path)
    except Exception:
        return base, "builtin-default"
    if not isinstance(raw, dict):
        return base, "builtin-default"

    out = dict(base)
    out["version"] = str(raw.get("version") or out["version"])
    out["timezone"] = str(raw.get("timezone") or out["timezone"])
    out["timezone_offset"] = str(raw.get("timezone_offset") or out["timezone_offset"])
    try:
        out["start_offset_days"] = int(raw.get("start_offset_days", out["start_offset_days"]))
    except Exception:
        pass

    raw_platforms = raw.get("platforms") or {}
    for platform in ("x", "youtube"):
        psrc = raw_platforms.get(platform) if isinstance(raw_platforms, dict) else {}
        if not isinstance(psrc, dict):
            continue
        dst = dict(out["platforms"][platform])
        dst["mode"] = str(psrc.get("mode") or dst.get("mode", "weekly_slots"))
        dst["weekly_slots"] = normalize_weekly_slots(psrc.get("weekly_slots", {}))
        if platform == "youtube":
            if "privacy" in psrc:
                dst["privacy"] = str(psrc.get("privacy") or dst.get("privacy", "public"))
            if "madeForKids" in psrc:
                dst["madeForKids"] = bool(psrc.get("madeForKids"))
            if "notifySubscribers" in psrc:
                dst["notifySubscribers"] = bool(psrc.get("notifySubscribers"))
        out["platforms"][platform] = dst
    return out, rel(policy_path, cdir)


def normalize_day_token(day_value):
    s = str(day_value or "").strip()
    m = re.search(r"(\d{1,3})$", s)
    if not m:
        return ""
    return f"{int(m.group(1)):03d}"


def normalize_day_label(day_value):
    d = normalize_day_token(day_value)
    return f"Day{d}" if d else ""


def parse_days_csv(days_csv):
    raw = str(days_csv or "").strip()
    if not raw:
        return set()
    out = set()
    for part in raw.split(","):
        d = normalize_day_token(part)
        if d:
            out.add(f"Day{d}")
    return out


def parse_timezone_offset(offset):
    m = re.match(r"^([+-])(\d{2}):?(\d{2})$", str(offset or "").strip())
    if not m:
        return timezone(timedelta(hours=9))
    sign = -1 if m.group(1) == "-" else 1
    hh = int(m.group(2))
    mm = int(m.group(3))
    return timezone(sign * timedelta(hours=hh, minutes=mm))


def weekday_key_from_date(target_date):
    return WEEKDAY_KEYS[target_date.weekday()]


def resolve_schedule_time(policy, platform, target_date, fallback_time):
    wk = weekday_key_from_date(target_date)
    platform_cfg = ((policy or {}).get("platforms") or {}).get(platform) or {}
    mode = str(platform_cfg.get("mode") or "weekly_slots")
    if mode == "weekly_slots":
        slots = platform_cfg.get("weekly_slots") or {}
        val = str(slots.get(wk, "")).strip()
        if is_hhmm(val):
            return val
    if mode == "fixed":
        val = str(platform_cfg.get("time_local", "")).strip()
        if is_hhmm(val):
            return val
    if is_hhmm(fallback_time):
        return fallback_time
    return DEFAULT_WEEKLY_SLOTS[wk]


def build_due_at(base_date_iso, idx, start_offset_days, fallback_time, tzinfo, schedule_policy, platform):
    base_day = datetime.strptime(base_date_iso, "%Y-%m-%d").date()
    target_date = base_day + timedelta(days=start_offset_days + idx)
    slot = resolve_schedule_time(schedule_policy, platform, target_date, fallback_time)
    hour, minute = [int(x) for x in slot.split(":", 1)]
    dt = datetime.combine(target_date, time(hour=hour, minute=minute), tzinfo=tzinfo)
    return dt.isoformat(), weekday_key_from_date(target_date), slot


def load_youtube_handoff(cdir, date_str):
    candidates = [
        os.path.join(cdir, "imports", "publish", f"youtube_video_handoff_{date_str}.json"),
        os.path.join(cdir, "imports", "publish", "youtube_video_handoff_latest.json"),
        os.path.join(cdir, "imports", "publish", "youtube_video_handoff.json"),
        os.path.join(cdir, "exports", "launch", f"youtube_upload_handoff_{date_str}.json"),
        latest(os.path.join(cdir, "exports", "launch", "youtube_upload_handoff_*.json")),
    ]
    uniq = []
    for p in candidates:
        if p and p not in uniq:
            uniq.append(p)

    def pick_text(rec, keys):
        for k in keys:
            v = rec.get(k)
            if v is None:
                continue
            s = str(v).strip()
            if s:
                return s
        return ""

    def is_placeholder_url(value):
        s = str(value or "").strip()
        if not s:
            return False
        return ("REPLACE_" in s) or ("PLACEHOLDER" in s)

    merged = {}
    source_by_day = {}
    used_sources = []
    for path in uniq:
        if not path or not os.path.exists(path):
            continue
        try:
            raw = read_json(path)
        except Exception:
            continue
        rel_path = rel(path, cdir)
        records = []
        if isinstance(raw, dict) and isinstance(raw.get("items"), list):
            records = [x for x in raw.get("items", []) if isinstance(x, dict)]
        elif isinstance(raw, list):
            records = [x for x in raw if isinstance(x, dict)]
        elif isinstance(raw, dict):
            for k, v in raw.items():
                if not isinstance(v, dict):
                    continue
                d = normalize_day_token(k)
                if not d:
                    continue
                rec = dict(v)
                rec["day"] = d
                records.append(rec)
        if not records:
            continue
        used_sources.append(rel_path)
        for rec in records:
            day_token = normalize_day_token(rec.get("day") or rec.get("tool_day") or rec.get("id") or rec.get("tool_id"))
            if not day_token:
                continue
            slot = merged.get(day_token) or {
                "videoUrl": "",
                "thumbnailUrl": "",
                "title": "",
                "description": "",
                "dueAt": "",
                "privacy": "",
                "madeForKids": None,
                "notifySubscribers": None,
                "playlistCandidate": "",
                "audience": "",
                "shortsCandidate": None,
            }
            video_url = pick_text(rec, ["videoUrl", "video_url", "youtubeUrl", "youtube_url", "url"])
            thumb = pick_text(rec, ["thumbnailUrl", "thumbnail_url", "thumbUrl", "thumb_url"])
            title = pick_text(rec, ["titleOverride", "title"])
            desc = pick_text(rec, ["descriptionOverride", "description", "desc"])
            due_at = pick_text(rec, ["dueAtOverride", "dueAt", "due_at", "scheduledAt", "scheduled_at"])
            existing_video = str(slot.get("videoUrl", "")).strip()
            if video_url:
                if (not existing_video) or (is_placeholder_url(existing_video) and not is_placeholder_url(video_url)):
                    slot["videoUrl"] = video_url
                    source_by_day[day_token] = rel_path
            if thumb and not str(slot.get("thumbnailUrl", "")).strip():
                slot["thumbnailUrl"] = thumb
            if title and not str(slot.get("title", "")).strip():
                slot["title"] = title
            if desc and not str(slot.get("description", "")).strip():
                slot["description"] = desc
            if due_at and not str(slot.get("dueAt", "")).strip():
                slot["dueAt"] = due_at
            privacy = str(rec.get("privacy") or "").strip()
            if privacy and not str(slot.get("privacy", "")).strip():
                slot["privacy"] = privacy
            if slot.get("madeForKids") is None and rec.get("madeForKids") is not None:
                slot["madeForKids"] = rec.get("madeForKids")
            if slot.get("notifySubscribers") is None and rec.get("notifySubscribers") is not None:
                slot["notifySubscribers"] = rec.get("notifySubscribers")
            playlist = pick_text(rec, ["playlistCandidate", "playlist"])
            if playlist and not str(slot.get("playlistCandidate", "")).strip():
                slot["playlistCandidate"] = playlist
            audience = pick_text(rec, ["audience"])
            if audience and not str(slot.get("audience", "")).strip():
                slot["audience"] = audience
            if slot.get("shortsCandidate") is None and rec.get("shortsCandidate") is not None:
                slot["shortsCandidate"] = rec.get("shortsCandidate")
            merged[day_token] = slot
    if merged:
        return merged, ", ".join(sorted(set(used_sources))), source_by_day
    return {}, "", {}


def build_x_entry(priority, launch_id, tool_day, tool_id, post_type, hook, body, cta, url, notes=None):
    n_post_type = normalize_post_type(post_type)
    n_tool_id = tool_id or normalize_tool_id(tool_day)
    return {
        "launch_id": launch_id,
        "post_id": build_post_id(launch_id, n_tool_id or "day000", "x", n_post_type, priority),
        "priority": priority,
        "tool_day": tool_day,
        "tool_id": n_tool_id,
        "channel": "x",
        "post_type": n_post_type,
        "hook": hook,
        "hook_family": normalize_hook_family(hook),
        "body": body,
        "cta": cta,
        "cta_family": normalize_cta_family(cta),
        "url": url,
        "decision_source": "launch_pack",
        "notes": notes or [],
    }


def main():
    parser = argparse.ArgumentParser(description="Build launch export artifacts from launch pack")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    parser.add_argument("--days", default="", help="Comma separated day list. ex: 009,010,011")
    parser.add_argument("--schedule-time", default="", help="Fallback posting time for dueAt when policy slot is unavailable. ex: 21:00")
    parser.add_argument("--schedule-start-offset-days", type=int, default=None, help="Days from --date to start scheduling")
    parser.add_argument("--schedule-timezone", default="", help="ISO timezone offset for dueAt. ex: +09:00")
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)

    p_launch = latest(os.path.join(cdir, "reports", "launch", "launch_pack_*.json"))
    p_growth = latest(os.path.join(cdir, "reports", "growth", "growth_brief_*.json"))
    p_strategy = latest(os.path.join(cdir, "reports", "strategy", "strategy_brief_*.json"))
    p_portfolio = latest(os.path.join(cdir, "reports", "portfolio", "portfolio_eval_*.json"))
    p_evidence = latest(os.path.join(cdir, "reports", "evidence", "evidence_*.json"))
    p_reality = latest(os.path.join(cdir, "reports", "reality", "reality_gate_*.json"))
    p_showcase = latest(os.path.join(cdir, "reports", "showcase", "showcase_plan_*.json"))
    p_tower = latest(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))

    launch = read_json(p_launch) if p_launch else {}
    growth = read_json(p_growth) if p_growth else {}
    strategy = read_json(p_strategy) if p_strategy else {}
    portfolio = read_json(p_portfolio) if p_portfolio else {}
    evidence = read_json(p_evidence) if p_evidence else {}
    reality = read_json(p_reality) if p_reality else {}
    showcase = read_json(p_showcase) if p_showcase else {}
    tower = read_json(p_tower) if p_tower else {}
    p_state = os.path.join(cdir, "STATE.json")
    state = read_json(p_state) if os.path.exists(p_state) else {}
    state_days = (state.get("days") or {}) if isinstance(state, dict) else {}
    selected_days = parse_days_csv(args.days)
    schedule_policy, schedule_policy_source = load_publish_schedule_policy(cdir)
    schedule_timezone = args.schedule_timezone.strip() if args.schedule_timezone else str(schedule_policy.get("timezone_offset", "+09:00"))
    tzinfo = parse_timezone_offset(schedule_timezone)
    schedule_start_offset_days = args.schedule_start_offset_days if args.schedule_start_offset_days is not None else int(schedule_policy.get("start_offset_days", 1))
    schedule_time_fallback = args.schedule_time.strip() if args.schedule_time else ""
    youtube_handoff_map, youtube_handoff_source, youtube_handoff_source_by_day = load_youtube_handoff(cdir, args.date)

    inputs_used = {
        "launch_pack": bool(launch),
        "growth": bool(growth),
        "strategy": bool(strategy),
        "portfolio": bool(portfolio),
        "evidence": bool(evidence),
        "reality": bool(reality),
        "showcase": bool(showcase),
        "control_tower": bool(tower),
    }

    hero = (launch.get("launch_decisions", {}) or {}).get("hero_tool", {}) if isinstance(launch, dict) else {}
    hero_pack = (launch.get("hero_launch_pack", {}) or {}) if isinstance(launch, dict) else {}
    by_day = launch.get("by_day", []) if isinstance(launch.get("by_day", []), list) else []
    launch_id = (launch.get("launch_id") if isinstance(launch, dict) else "") or build_launch_id(args.date)

    secondary = []
    hold_tools = []
    quiet_tools = []
    for row in by_day:
        d = row.get("decision", "")
        if d in ("launch_now", "launch_with_notes") and row.get("day") != hero.get("day"):
            secondary.append(row)
        elif d == "hold":
            hold_tools.append(row)
        elif d == "quiet_catalog":
            quiet_tools.append(row)

    def enrich_row(row):
        if not isinstance(row, dict):
            return {}
        out = dict(row)
        out["launch_id"] = launch_id
        out["tool_id"] = out.get("tool_id") or normalize_tool_id(out.get("day", ""))
        out["decision_source"] = out.get("decision_source", "launch_pack")
        return out

    secondary = [enrich_row(x) for x in secondary]
    hold_tools = [enrich_row(x) for x in hold_tools]
    quiet_tools = [enrich_row(x) for x in quiet_tools]

    hero_day = hero.get("day", "")
    hero_title = hero.get("title") or hero.get("repo_name", "")
    hero_url = hero.get("pages_url", "")
    one_line = hero_pack.get("one_line_positioning") or hero.get("one_line_positioning", "")

    hooks = hero_pack.get("x_hooks", []) if isinstance(hero_pack.get("x_hooks", []), list) else []
    ctas = hero_pack.get("cta_candidates", []) if isinstance(hero_pack.get("cta_candidates", []), list) else []
    hero_msg = hero_pack.get("hero_message", "")
    dist_mix = (launch.get("summary", {}) or {}).get("recommended_distribution_mix", [])

    x_queue = []
    if hero:
        hero_tool_id = hero.get("tool_id") or normalize_tool_id(hero_day)
        primary_hook = hooks[0] if hooks else f"{hero_title} を公開しました"
        primary_cta = ctas[0] if ctas else "触って感想をもらえると助かります。"
        body = one_line or hero_msg or f"{hero_title} を今週の1本として公開"
        x_queue.append(build_x_entry(1, launch_id, hero_day, hero_tool_id, "hero", primary_hook, body, primary_cta, hero_url, ["hero candidate"]))
        if len(hooks) > 1:
            x_queue.append(build_x_entry(2, launch_id, hero_day, hero_tool_id, "hero", hooks[1], body, primary_cta, hero_url, ["alt hook"]))

    pri = 3
    for s in secondary[:3]:
        s_tool_id = s.get("tool_id") or normalize_tool_id(s.get("day", ""))
        hook = (s.get("hook_candidates", []) or [f"{s.get('title', s.get('repo_name', 'tool'))} も公開中"])[0]
        cta = (s.get("cta_candidates", []) or ["こちらも試してみてください"])[0]
        x_queue.append(
            build_x_entry(
                pri,
                launch_id,
                s.get("day", ""),
                s_tool_id,
                "secondary",
                hook,
                s.get("one_line_positioning", ""),
                cta,
                s.get("pages_url", ""),
                ["secondary candidate"],
            )
        )
        pri += 1

    note_seed = {
        "title_candidates": [
            f"{hero_title} を作った理由と設計メモ",
            f"{hero_title} の体験設計: 1分で価値を伝える方法",
            f"小さなツールを公開し続けるための実装メモ（{hero_title}編）",
        ],
        "target_tool": hero_day,
        "target_tool_id": hero.get("tool_id") or normalize_tool_id(hero_day),
        "angle": "hero tool の用途即時理解 + launch導線最適化",
        "intro_seed": (one_line or hero_msg or "今週のhero toolをどう押し出すかを整理した。"),
        "outline": hero_pack.get("note_outline", []) if isinstance(hero_pack.get("note_outline", []), list) else [
            "背景",
            "設計意図",
            "使い方",
            "今後の改善",
        ],
        "cta_candidates": ctas[:3] if ctas else ["触ってフィードバックをください。"],
    }

    gallery_entries = []
    for row in by_day:
        pr = "hero" if row.get("day") == hero_day else ("quiet" if row.get("decision") == "quiet_catalog" else ("hold" if row.get("decision") == "hold" else "secondary"))
        caps = []
        if row.get("day") == hero_day and isinstance(hero_pack.get("gallery_caption_candidates", []), list):
            caps = hero_pack.get("gallery_caption_candidates", [])[:3]
        if not caps:
            caps = [row.get("one_line_positioning", ""), f"{row.get('title', row.get('repo_name', 'tool'))} | {row.get('decision', '')}"]

        gallery_entries.append(
            {
                "day": row.get("day", ""),
                "tool_id": row.get("tool_id") or normalize_tool_id(row.get("day", "")),
                "title": row.get("title", row.get("repo_name", "")),
                "one_line": row.get("one_line_positioning", ""),
                "caption_candidates": caps[:3],
                "pages_url": row.get("pages_url", ""),
                "repo_url": row.get("repo_url", ""),
                "display_priority": pr,
            }
        )

    def sort_by_day(rows):
        def day_key(r):
            d = normalize_day_token((r or {}).get("day", ""))
            return int(d) if d else 9999
        return sorted(rows, key=day_key)

    def post_text_for_row(row):
        day_token = normalize_day_token(row.get("day", ""))
        state_entry = state_days.get(day_token, {}) if isinstance(state_days, dict) else {}
        post_texts = state_entry.get("post_texts", {}) if isinstance(state_entry, dict) else {}
        text = post_texts.get("standard") or post_texts.get("compact") or post_texts.get("minimal") or ""
        if text:
            return text
        title = row.get("title") or row.get("repo_name") or "tool"
        one_line_fallback = row.get("one_line_positioning", "")
        pages_url = row.get("pages_url", "")
        return f"Day{day_token}｜{title}\n{one_line_fallback}\n👉 {pages_url}\n#個人開発 #100日開発"

    publish_rows = []
    for row in by_day:
        row_label = normalize_day_label(row.get("day", ""))
        if selected_days and row_label not in selected_days:
            continue
        publish_rows.append(row)
    publish_rows = sort_by_day(publish_rows)

    def pick_text_from_records(records, keys):
        for rec in records:
            if not isinstance(rec, dict):
                continue
            for k in keys:
                v = rec.get(k)
                if v is None:
                    continue
                s = str(v).strip()
                if s:
                    return s
        return ""

    def pick_bool_from_records(records, keys):
        for rec in records:
            if not isinstance(rec, dict):
                continue
            for k in keys:
                if k in rec and rec.get(k) is not None:
                    return bool(rec.get(k))
        return None

    def resolve_youtube_asset(day_token):
        handoff = youtube_handoff_map.get(day_token, {})
        handoff_source_for_day = youtube_handoff_source_by_day.get(day_token, "")
        state_entry = state_days.get(day_token, {}) if isinstance(state_days, dict) else {}
        state_records = []
        if isinstance(state_entry, dict):
            state_records.extend(
                [
                    state_entry,
                    state_entry.get("meta", {}),
                    state_entry.get("publish", {}),
                    state_entry.get("video", {}),
                    state_entry.get("deploy", {}),
                ]
            )
        video_url = (
            str(handoff.get("videoUrl", "")).strip()
            or pick_text_from_records(state_records, ["youtube_video_url", "youtube_url", "video_url", "videoUrl"])
        )
        thumbnail_url = (
            str(handoff.get("thumbnailUrl", "")).strip()
            or pick_text_from_records(state_records, ["youtube_thumbnail_url", "thumbnail_url", "thumbnailUrl"])
        )
        title = str(handoff.get("title", "")).strip() or pick_text_from_records(
            state_records, ["youtube_title", "video_title", "title"]
        )
        description = str(handoff.get("description", "")).strip() or pick_text_from_records(
            state_records, ["youtube_description", "video_description", "description"]
        )
        due_at = str(handoff.get("dueAt", "")).strip()
        privacy = str(handoff.get("privacy", "")).strip()
        made_for_kids = handoff.get("madeForKids")
        notify_subscribers = handoff.get("notifySubscribers")
        playlist_candidate = str(handoff.get("playlistCandidate", "")).strip()
        audience = str(handoff.get("audience", "")).strip()
        shorts_candidate = handoff.get("shortsCandidate")
        if made_for_kids is None:
            made_for_kids = pick_bool_from_records(state_records, ["madeForKids", "made_for_kids"])
        if notify_subscribers is None:
            notify_subscribers = pick_bool_from_records(state_records, ["notifySubscribers", "notify_subscribers"])
        if shorts_candidate is None:
            shorts_candidate = pick_bool_from_records(state_records, ["shortsCandidate", "shorts_candidate", "is_short"])
        source = ""
        if handoff:
            source = handoff_source_for_day or youtube_handoff_source or "imports/publish"
        elif video_url:
            source = "STATE.json"
        return {
            "videoUrl": video_url,
            "thumbnailUrl": thumbnail_url,
            "title": title,
            "description": description,
            "dueAt": due_at,
            "privacy": privacy,
            "madeForKids": made_for_kids,
            "notifySubscribers": notify_subscribers,
            "playlistCandidate": playlist_candidate,
            "audience": audience,
            "shortsCandidate": shorts_candidate,
            "source": source,
        }

    def is_http_url(value):
        return bool(re.match(r"^https?://", str(value or "").strip(), flags=re.IGNORECASE))

    def classify_youtube_readiness(item):
        required = ["title", "description", "videoUrl", "dueAt"]
        missing = [k for k in required if not str(item.get(k, "")).strip()]
        if missing == ["videoUrl"]:
            return "pending_asset", missing
        if missing:
            return "blocked", missing
        vu = str(item.get("videoUrl", ""))
        if "REPLACE_" in vu or "PLACEHOLDER" in vu:
            return "pending_asset", ["videoUrl"]
        if not is_http_url(item.get("videoUrl")):
            return "invalid", ["videoUrl"]
        if not re.match(r"^\d{4}-\d{2}-\d{2}T", str(item.get("dueAt"))):
            return "invalid", ["dueAt"]
        return "ready", []

    youtube_platform_policy = schedule_policy.get("platforms", {}).get("youtube", {})
    x_publish_items = []
    youtube_publish_items = []
    youtube_ready_items = []
    youtube_missing_items = []
    for idx, row in enumerate(publish_rows):
        day_label = normalize_day_label(row.get("day", ""))
        day_token = normalize_day_token(row.get("day", ""))
        if not day_token:
            continue
        tool_id = row.get("tool_id") or normalize_tool_id(day_label or row.get("day", ""))
        due_at_x, weekday_x, slot_x = build_due_at(
            args.date,
            idx,
            schedule_start_offset_days,
            schedule_time_fallback,
            tzinfo,
            schedule_policy,
            "x",
        )
        due_at_y, weekday_y, slot_y = build_due_at(
            args.date,
            idx,
            schedule_start_offset_days,
            schedule_time_fallback,
            tzinfo,
            schedule_policy,
            "youtube",
        )
        one_line_text = row.get("one_line_positioning", "")
        pages_url = row.get("pages_url", "")
        title = row.get("title") or row.get("repo_name") or f"Day{day_token}"
        youtube_asset = resolve_youtube_asset(day_token)
        yt_title = youtube_asset["title"] or f"Day{day_token}｜{title}"
        yt_desc = youtube_asset["description"] or f"{one_line_text}\n\n{pages_url}\n#個人開発 #100日開発"
        yt_due_at = youtube_asset["dueAt"] or due_at_y
        yt_privacy = youtube_asset["privacy"] or str(youtube_platform_policy.get("privacy") or "public")
        yt_mfk = youtube_asset["madeForKids"]
        if yt_mfk is None:
            yt_mfk = bool(youtube_platform_policy.get("madeForKids", False))
        yt_notify = youtube_asset["notifySubscribers"]
        if yt_notify is None:
            yt_notify = bool(youtube_platform_policy.get("notifySubscribers", True))
        yt_playlist = youtube_asset["playlistCandidate"]
        yt_audience = youtube_asset["audience"] or "general"
        yt_shorts = youtube_asset["shortsCandidate"]
        if yt_shorts is None:
            yt_shorts = bool(re.search(r"/shorts/|youtu\.be/", str(youtube_asset["videoUrl"] or ""), flags=re.IGNORECASE))

        x_publish_items.append(
            {
                "day": day_token,
                "tool_id": tool_id,
                "platform": "x",
                "text": post_text_for_row(row),
                "dueAt": due_at_x,
                "schedule_weekday": weekday_x,
                "schedule_slot": slot_x,
                "title": title,
                "one_line": one_line_text,
                "pages_url": pages_url,
            }
        )
        yt_item = {
            "day": day_token,
            "tool_id": tool_id,
            "platform": "youtube",
            "title": yt_title,
            "description": yt_desc,
            "videoUrl": youtube_asset["videoUrl"],
            "thumbnailUrl": youtube_asset["thumbnailUrl"],
            "dueAt": yt_due_at,
            "schedule_weekday": weekday_y,
            "schedule_slot": slot_y,
            "privacy": yt_privacy,
            "madeForKids": yt_mfk,
            "notifySubscribers": yt_notify,
            "playlistCandidate": yt_playlist,
            "audience": yt_audience,
            "shortsCandidate": yt_shorts,
            "video_source": youtube_asset["source"],
        }
        readiness, missing = classify_youtube_readiness(yt_item)
        yt_item["readiness"] = readiness
        yt_item["missing_fields"] = missing
        yt_item["ready_for_publish"] = readiness == "ready"
        youtube_publish_items.append(yt_item)
        if yt_item["readiness"] == "ready":
            youtube_ready_items.append(yt_item)
        else:
            youtube_missing_items.append(
                {
                    "day": day_token,
                    "readiness": readiness,
                    "missing_fields": missing,
                    "video_source": yt_item["video_source"],
                }
            )

    publish_items = x_publish_items + youtube_publish_items
    make_payload = {
        "launch_id": launch_id,
        "schema_version": "publish_payload.v2",
        "hero_tool": {
            "day": hero_day,
            "tool_id": hero.get("tool_id") or normalize_tool_id(hero_day),
            "title": hero_title,
            "pages_url": hero_url,
            "decision": hero.get("decision", "launch_with_notes"),
        },
        "secondary_tools": [{"day": x.get("day"), "tool_id": x.get("tool_id") or normalize_tool_id(x.get("day", "")), "title": x.get("title", x.get("repo_name", ""))} for x in secondary[:5]],
        "distribution_mix": dist_mix,
        "schedule_policy": {
            "version": schedule_policy.get("version"),
            "source": schedule_policy_source,
            "timezone": schedule_policy.get("timezone", "Asia/Tokyo"),
            "timezone_offset": schedule_timezone,
            "base_date": args.date,
            "start_offset_days": schedule_start_offset_days,
            "platforms": {
                "x": schedule_policy.get("platforms", {}).get("x", {}),
                "youtube": schedule_policy.get("platforms", {}).get("youtube", {}),
            },
            "selected_days": sorted([normalize_day_token(x) for x in selected_days]) if selected_days else [],
        },
        "publish_items": publish_items,
        "x_items": x_publish_items,
        "youtube_items": youtube_publish_items,
        "youtube_ready_items": youtube_ready_items,
        "youtube_missing_items": youtube_missing_items,
        "publish_readiness": {
            "x_ready_count": len(x_publish_items),
            "youtube_ready_count": len(youtube_ready_items),
            "youtube_pending_asset_count": len([x for x in youtube_publish_items if x.get("readiness") == "pending_asset"]),
            "youtube_blocked_count": len([x for x in youtube_publish_items if x.get("readiness") == "blocked"]),
            "youtube_invalid_count": len([x for x in youtube_publish_items if x.get("readiness") == "invalid"]),
            "youtube_missing_video_count": len([x for x in youtube_publish_items if "videoUrl" in (x.get("missing_fields") or [])]),
        },
        "dueAt_summary": {
            "x": [{k: x.get(k) for k in ["day", "dueAt", "schedule_weekday", "schedule_slot"]} for x in x_publish_items],
            "youtube": [{k: x.get(k) for k in ["day", "dueAt", "schedule_weekday", "schedule_slot", "readiness"]} for x in youtube_publish_items],
        },
        "copy_assets": {
            "one_line": one_line,
            "hero_message": hero_msg,
            "hooks": hooks[:5],
            "ctas": ctas[:4],
        },
        "notes": [
            "manual review required before external send",
            "do not auto-post without final human check",
            "youtube route requires videoUrl to be populated",
        ],
    }

    launch_export = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "launch_id": launch_id,
        "summary": {
            "hero_tool": hero_day,
            "secondary_count": len(secondary),
            "hold_count": len(hold_tools),
            "quiet_catalog_count": len(quiet_tools),
            "recommended_distribution_mix": dist_mix,
            "inputs_used": inputs_used,
        },
        "hero_tool": {
            "day": hero_day,
            "tool_id": hero.get("tool_id") or normalize_tool_id(hero_day),
            "repo_name": hero.get("repo_name", ""),
            "title": hero_title,
            "pages_url": hero_url,
            "repo_url": hero.get("repo_url", ""),
            "decision": hero.get("decision", "launch_with_notes"),
            "decision_source": hero.get("decision_source", "launch_pack"),
            "one_line_positioning": one_line,
            "hero_message": hero_msg,
            "preferred_channels": hero.get("preferred_channels", []),
            "proof_points": hero_pack.get("proof_points", []),
            "risk_notes": hero_pack.get("risk_notes", []),
            "required_fixes_before_push": hero.get("required_fixes_before_push", []),
        },
        "secondary_tools": secondary,
        "hold_tools": hold_tools,
        "quiet_catalog_tools": quiet_tools,
        "x_queue": x_queue,
        "note_seed": note_seed,
        "gallery_entries": gallery_entries,
        "make_payload": make_payload,
        "publish_payload_preview": {
            "selected_days": [x.get("day") for x in x_publish_items],
            "x_item_count": len(x_publish_items),
            "youtube_item_count": len(youtube_publish_items),
            "youtube_ready_count": len(youtube_ready_items),
            "youtube_pending_asset_count": len([x for x in youtube_publish_items if x.get("readiness") == "pending_asset"]),
            "youtube_blocked_count": len([x for x in youtube_publish_items if x.get("readiness") == "blocked"]),
            "youtube_invalid_count": len([x for x in youtube_publish_items if x.get("readiness") == "invalid"]),
            "youtube_missing_video_count": len(
                [
                    x
                    for x in youtube_publish_items
                    if x.get("readiness") == "pending_asset" or ("videoUrl" in (x.get("missing_fields") or []))
                ]
            ),
            "first_dueAt": (x_publish_items[0].get("dueAt") if x_publish_items else ""),
            "x_dueAt_by_day": [{k: x.get(k) for k in ["day", "dueAt", "schedule_weekday", "schedule_slot"]} for x in x_publish_items],
            "youtube_missing": youtube_missing_items[:10],
            "youtube_video_source": youtube_handoff_source or "not_connected",
        },
        "recommended_export_actions": [
            "hero 投稿文を最終確認してX/Bufferへ手動投入",
            "note seed を下書き化して見出しと導入を整える",
            "gallery entries を表示優先度に沿って反映",
            "hold対象は fixes 完了後に再export",
        ],
        "quality_signal_sources": [
            rel(p_launch, cdir),
            rel(p_growth, cdir),
            rel(p_strategy, cdir),
            rel(p_portfolio, cdir),
            rel(p_evidence, cdir),
            rel(p_reality, cdir),
            rel(p_showcase, cdir),
            rel(p_tower, cdir),
        ],
    }

    out_dir = os.path.join(cdir, "exports", "launch")
    os.makedirs(out_dir, exist_ok=True)

    p_export_json = os.path.join(out_dir, f"launch_export_{args.date}.json")
    p_export_md = os.path.join(out_dir, f"launch_export_{args.date}.md")
    p_make = os.path.join(out_dir, f"make_payload_{args.date}.json")
    p_note = os.path.join(out_dir, f"note_seed_{args.date}.md")
    p_gallery = os.path.join(out_dir, f"gallery_entries_{args.date}.json")
    p_xq = os.path.join(out_dir, f"x_queue_{args.date}.json")

    write_json(p_export_json, launch_export)
    write_json(p_make, make_payload)
    write_json(p_gallery, gallery_entries)
    write_json(p_xq, x_queue)

    note_lines = [
        f"# note seed ({args.date})",
        "",
        f"- target_tool: {note_seed['target_tool']}",
        f"- angle: {note_seed['angle']}",
        "",
        "## title_candidates",
    ]
    for t in note_seed["title_candidates"]:
        note_lines.append(f"- {t}")
    note_lines.append("")
    note_lines.append("## intro_seed")
    note_lines.append(note_seed["intro_seed"])
    note_lines.append("")
    note_lines.append("## outline")
    for o in note_seed["outline"]:
        note_lines.append(f"- {o}")
    note_lines.append("")
    note_lines.append("## cta_candidates")
    for c in note_seed["cta_candidates"]:
        note_lines.append(f"- {c}")
    write_text(p_note, "\n".join(note_lines) + "\n")

    md = []
    md.append(f"# Launch Export ({args.date})")
    md.append("")
    md.append("## 今週の export 総評")
    md.append(f"- hero_tool: {hero_day} {hero_title}")
    md.append(f"- secondary/quiet/hold: {len(secondary)}/{len(quiet_tools)}/{len(hold_tools)}")
    md.append(f"- distribution_mix: {', '.join(dist_mix) if dist_mix else 'n/a'}")
    md.append("")
    md.append("## hero tool の handoff")
    md.append(f"- decision: {hero.get('decision', 'launch_with_notes')}")
    md.append(f"- one_line: {one_line}")
    md.append(f"- pages: {hero_url}")
    md.append("")
    md.append("## secondary / quiet / hold")
    if secondary:
        for s in secondary:
            md.append(f"- secondary: {s.get('day')} {s.get('repo_name')} ({s.get('decision')})")
    if quiet_tools:
        for s in quiet_tools[:5]:
            md.append(f"- quiet: {s.get('day')} {s.get('repo_name')}")
    if hold_tools:
        for s in hold_tools[:5]:
            md.append(f"- hold: {s.get('day')} {s.get('repo_name')} / {', '.join(s.get('issues', [])[:2])}")
    if not (secondary or quiet_tools or hold_tools):
        md.append("- no additional candidates")
    md.append("")
    md.append("## X / Buffer 向け投稿候補")
    for q in x_queue[:6]:
        md.append(f"- [{q['priority']}] {q['tool_day']} {q['post_type']}: {q['hook']}")
    if not x_queue:
        md.append("- none")
    md.append("")
    md.append("## note 記事 seed")
    md.append(f"- target_tool: {note_seed['target_tool']}")
    md.append(f"- intro_seed: {note_seed['intro_seed']}")
    md.append("- outline:")
    for o in note_seed["outline"]:
        md.append(f"  - {o}")
    md.append("")
    md.append("## gallery / catalog 用短文")
    for g in gallery_entries[:5]:
        cap = (g.get("caption_candidates") or [""])[0]
        md.append(f"- {g.get('day')} {g.get('title')}: {cap}")
    md.append("")
    md.append("## Make へ渡す時の要点")
    md.append(f"- hero: {make_payload['hero_tool'].get('day')} {make_payload['hero_tool'].get('title')}")
    md.append("- manual review required before external send")
    md.append("")
    md.append("## 手動確認が必要な点")
    md.append("- hook/body/CTA の事実整合")
    md.append("- hold対象の修正完了")
    md.append("- URL と公開状態")
    md.append("")
    md.append("## Make/Webhook publish_items")
    md.append(f"- x_items: {len(x_publish_items)}")
    md.append(f"- youtube_items: {len(youtube_publish_items)}")
    md.append(f"- youtube_ready_items: {len(youtube_ready_items)}")
    md.append(f"- youtube_pending_asset: {len([x for x in youtube_publish_items if x.get('readiness') == 'pending_asset'])}")
    md.append(f"- youtube_blocked: {len([x for x in youtube_publish_items if x.get('readiness') == 'blocked'])}")
    md.append(f"- youtube_invalid: {len([x for x in youtube_publish_items if x.get('readiness') == 'invalid'])}")
    md.append(f"- youtube_video_source: {youtube_handoff_source or 'not_connected'}")
    if x_publish_items:
        md.append(f"- first_dueAt: {x_publish_items[0].get('dueAt')}")
        md.append("- x dueAt preview:")
        for item in x_publish_items:
            md.append(f"  - {item.get('day')}: {item.get('dueAt')} ({item.get('schedule_weekday')} {item.get('schedule_slot')})")
    if youtube_missing_items:
        md.append("- youtube missing:")
        for miss in youtube_missing_items[:7]:
            md.append(f"  - {miss.get('day')}: readiness={miss.get('readiness')} missing={','.join(miss.get('missing_fields', []))} (source={miss.get('video_source') or 'none'})")
    md.append("")
    md.append("## すぐやるべき export 前修正")
    for a in launch_export["recommended_export_actions"]:
        md.append(f"- {a}")

    write_text(p_export_md, "\n".join(md) + "\n")

    print(f"[build_launch_exports] wrote: {rel(p_export_json, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_export_md, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_make, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_note, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_gallery, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_xq, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
