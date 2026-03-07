#!/usr/bin/env python3
import argparse
import csv
import glob
import json
import os
from datetime import date, datetime, timezone
from typing import Any, Dict, List, Optional
from id_utils import (
    build_launch_id,
    normalize_cta_family as util_normalize_cta_family,
    normalize_hook_family as util_normalize_hook_family,
    normalize_post_type,
    normalize_tool_id,
)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def latest_file(pattern: str) -> str:
    files = glob.glob(pattern)
    if not files:
        return ""
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def parse_dt(value: Any) -> Optional[datetime]:
    if not value:
        return None
    s = str(value).strip()
    if not s:
        return None
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    for fmt in (
        None,
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
        "%Y/%m/%d %H:%M:%S",
        "%Y/%m/%d %H:%M",
        "%Y/%m/%d",
    ):
        try:
            if fmt is None:
                dt = datetime.fromisoformat(s)
            else:
                dt = datetime.strptime(s, fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except Exception:
            continue
    return None


def safe_int(value: Any) -> Optional[int]:
    if value is None:
        return None
    s = str(value).strip().replace(",", "")
    if s == "":
        return None
    try:
        return int(float(s))
    except Exception:
        return None


def norm_key(key: str) -> str:
    return key.strip().lower().replace(" ", "_")


def pick(row: Dict[str, Any], aliases: List[str]) -> Any:
    for alias in aliases:
        if alias in row and row.get(alias) not in (None, ""):
            return row.get(alias)
    return None


def canonicalize_row(row: Dict[str, Any], source_file: str) -> Dict[str, Any]:
    nr = {norm_key(k): v for k, v in row.items()}
    out = {
        "channel": pick(nr, ["channel", "platform", "network"]) or "x",
        "post_url": pick(nr, ["post_url", "url", "post_link", "link", "status_url"]),
        "post_text": pick(nr, ["post_text", "text", "content", "body", "message"]),
        "published_at": pick(nr, ["published_at", "published", "publishedat", "date", "timestamp"]),
        "impressions": safe_int(pick(nr, ["impressions", "views", "view_count"])),
        "likes": safe_int(pick(nr, ["likes", "favorites", "favourites"])),
        "replies": safe_int(pick(nr, ["replies", "comments", "comment_count"])),
        "reposts": safe_int(pick(nr, ["reposts", "retweets", "shares", "repost_count"])),
        "clicks": safe_int(pick(nr, ["clicks", "link_clicks", "url_clicks", "click_count"])),
        "tool_day": pick(nr, ["tool_day", "day"]),
        "tool_id": pick(nr, ["tool_id"]),
        "repo_name": pick(nr, ["repo_name", "repo"]),
        "post_type": pick(nr, ["post_type", "type"]),
        "post_id": pick(nr, ["post_id"]),
        "launch_id": pick(nr, ["launch_id"]),
        "decision_source": pick(nr, ["decision_source"]),
        "hook": pick(nr, ["hook", "opening", "intro"]),
        "cta": pick(nr, ["cta", "call_to_action"]),
        "target_url": pick(nr, ["target_url", "landing_url", "pages_url"]),
        "source_notes": [f"manual_import:{os.path.basename(source_file)}"],
    }
    return out


def load_manual_imports(import_dir: str, notes: List[str]) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    patterns = ["*.json", "*.jsonl", "*.csv", "*.tsv"]
    files: List[str] = []
    for pat in patterns:
        files.extend(sorted(glob.glob(os.path.join(import_dir, pat))))

    for path in files:
        base = os.path.basename(path)
        if base.startswith("."):
            continue
        try:
            if path.endswith(".json"):
                data = read_json(path)
                if isinstance(data, dict):
                    if isinstance(data.get("records"), list):
                        rows = data.get("records")
                    else:
                        rows = [data]
                elif isinstance(data, list):
                    rows = data
                else:
                    rows = []
                for row in rows:
                    if isinstance(row, dict):
                        records.append(canonicalize_row(row, path))
            elif path.endswith(".jsonl"):
                with open(path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        row = json.loads(line)
                        if isinstance(row, dict):
                            records.append(canonicalize_row(row, path))
            else:
                delimiter = "\t" if path.endswith(".tsv") else ","
                with open(path, "r", encoding="utf-8", newline="") as f:
                    reader = csv.DictReader(f, delimiter=delimiter)
                    for row in reader:
                        if isinstance(row, dict):
                            records.append(canonicalize_row(row, path))
        except Exception as e:
            notes.append(f"manual import parse failed: {base}: {e}")
    if files and not records:
        notes.append("manual imports exist but no usable records parsed")
    return records


def try_collect_buffer_browser(notes: List[str]) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    target_url = os.getenv("BUFFER_ANALYTICS_URL", "https://publish.buffer.com")
    timeout_ms = int(os.getenv("BUFFER_BROWSER_TIMEOUT_MS", "20000"))

    try:
        from playwright.sync_api import sync_playwright
    except Exception as e:
        notes.append(f"buffer browser skipped: playwright unavailable ({e})")
        return records

    storage_state = os.getenv("BUFFER_STORAGE_STATE", "")
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context_args: Dict[str, Any] = {}
            if storage_state and os.path.exists(storage_state):
                context_args["storage_state"] = storage_state
            context = browser.new_context(**context_args)
            page = context.new_page()
            page.goto(target_url, wait_until="domcontentloaded", timeout=timeout_ms)
            text = page.content().lower()
            if "log in" in text or "sign in" in text:
                notes.append("buffer browser: login required or session expired")
            # best-effort extraction using broad selectors
            js = """
            () => {
              const anchors = Array.from(document.querySelectorAll('a[href*="x.com"],a[href*="twitter.com"],a[href*="status/"]')).slice(0,30);
              return anchors.map((a) => ({
                post_url: a.href || null,
                post_text: (a.innerText || '').trim().slice(0,280),
                published_at: null,
                impressions: null,
                likes: null,
                replies: null,
                reposts: null,
                clicks: null,
              }));
            }
            """
            extracted = page.evaluate(js)
            if isinstance(extracted, list):
                for rec in extracted:
                    if isinstance(rec, dict):
                        rec["channel"] = "x"
                        rec["source_notes"] = ["buffer_browser:selector_extract"]
                        records.append(rec)
            context.close()
            browser.close()
    except Exception as e:
        notes.append(f"buffer browser collection failed: {e}")

    if not records:
        notes.append("buffer browser: no post-level records extracted")
    return records


def classify_hook_family(text: str) -> str:
    return util_normalize_hook_family(text)


def classify_cta_family(text: str) -> str:
    return util_normalize_cta_family(text)


def load_state_days(state_path: str) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    if not os.path.exists(state_path):
        return out
    try:
        state = read_json(state_path)
        days = state.get("days", {}) if isinstance(state, dict) else {}
        if isinstance(days, dict):
            for day, info in days.items():
                if isinstance(info, dict):
                    out[str(day).zfill(3)] = info
    except Exception:
        return out
    return out


def infer_day_from_url(post_url: str, target_url: str, days: Dict[str, Dict[str, Any]]) -> str:
    hay = f"{post_url or ''} {target_url or ''}".lower()
    for day, info in days.items():
        pages = str(info.get("pages_url", "")).lower()
        if pages and pages in hay:
            return day
    return ""


def build_launch_lookup(cdir: str) -> Dict[str, Any]:
    p_launch_export = latest_file(os.path.join(cdir, "exports", "launch", "launch_export_*.json"))
    p_x_queue = latest_file(os.path.join(cdir, "exports", "launch", "x_queue_*.json"))
    p_make = latest_file(os.path.join(cdir, "exports", "launch", "make_payload_*.json"))

    launch_export = read_json(p_launch_export) if p_launch_export else {}
    x_queue = read_json(p_x_queue) if p_x_queue else []
    make_payload = read_json(p_make) if p_make else {}

    return {
        "launch_export": launch_export if isinstance(launch_export, dict) else {},
        "x_queue": x_queue if isinstance(x_queue, list) else [],
        "make_payload": make_payload if isinstance(make_payload, dict) else {},
        "sources": [p for p in [p_launch_export, p_x_queue, p_make] if p],
    }


def normalize_records(
    collected_at: str,
    source_mode: str,
    raw_records: List[Dict[str, Any]],
    days: Dict[str, Dict[str, Any]],
    launch_lookup: Dict[str, Any],
) -> List[Dict[str, Any]]:
    normalized: List[Dict[str, Any]] = []
    launch_export = launch_lookup.get("launch_export", {})
    x_queue = launch_lookup.get("x_queue", [])

    hero_day = ((launch_export.get("hero_tool") or {}).get("day") if isinstance(launch_export, dict) else "") or ""
    launch_id = ((launch_export.get("launch_id") if isinstance(launch_export, dict) else "") or build_launch_id(collected_at[:10]))

    collected_dt = parse_dt(collected_at) or datetime.now(timezone.utc)

    for rec in raw_records:
        n_notes: List[str] = list(rec.get("source_notes", []) if isinstance(rec.get("source_notes"), list) else [])
        post_url = rec.get("post_url") or ""
        target_url = rec.get("target_url") or ""

        tool_day = str(rec.get("tool_day") or "").zfill(3) if rec.get("tool_day") else ""
        if not tool_day:
            tool_day = infer_day_from_url(post_url, target_url, days)
        tool_id = rec.get("tool_id") or normalize_tool_id(tool_day)

        repo_name = rec.get("repo_name") or (days.get(tool_day, {}) or {}).get("repo_name", "")
        channel = (rec.get("channel") or "x").lower()
        decision_source = rec.get("decision_source") or "inferred_from_launch_export"
        post_id = rec.get("post_id") or ""
        row_launch_id = rec.get("launch_id") or launch_id

        post_type = rec.get("post_type") or ""
        if not post_type:
            for q in x_queue:
                if not isinstance(q, dict):
                    continue
                q_day = str(q.get("tool_day") or "").zfill(3) if q.get("tool_day") else ""
                q_url = q.get("url") or ""
                if (q_day and q_day == tool_day) or (q_url and post_url and q_url in post_url):
                    post_type = q.get("post_type") or ""
                    post_id = post_id or q.get("post_id") or ""
                    tool_id = tool_id or q.get("tool_id") or ""
                    decision_source = q.get("decision_source", "launch_pack")
                    break
        if not post_type:
            post_type = "hero" if tool_day and tool_day == str(hero_day).zfill(3) else "secondary"
        post_type = normalize_post_type(post_type)
        if not post_id:
            post_id = f"{row_launch_id}_{tool_id or 'day000'}_{channel}_{post_type}_na"

        hook = rec.get("hook") or rec.get("post_text") or ""
        cta = rec.get("cta") or ""
        hook_family = classify_hook_family(hook)
        cta_family = classify_cta_family(cta)

        published_at = rec.get("published_at")
        published_dt = parse_dt(published_at)
        age_hours = None
        age_days = None
        if published_dt:
            delta = collected_dt - published_dt
            age_hours = round(delta.total_seconds() / 3600, 2)
            age_days = round(age_hours / 24, 2)
        else:
            n_notes.append("published_at missing/unparseable")

        impressions = rec.get("impressions")
        likes = rec.get("likes")
        replies = rec.get("replies")
        reposts = rec.get("reposts")
        clicks = rec.get("clicks")

        likes_i = likes if isinstance(likes, int) else 0
        replies_i = replies if isinstance(replies, int) else 0
        reposts_i = reposts if isinstance(reposts, int) else 0
        clicks_i = clicks if isinstance(clicks, int) else 0
        impressions_i = impressions if isinstance(impressions, int) else 0

        engagement_simple = likes_i + replies_i + reposts_i
        engagement_rate_simple = None
        click_through_like = None
        if impressions_i > 0:
            engagement_rate_simple = round(engagement_simple / impressions_i, 6)
            click_through_like = round(clicks_i / impressions_i, 6)
        else:
            n_notes.append("impressions missing/zero")

        snap_launch_id = row_launch_id or f"{tool_day or 'unk'}:{channel}:{post_type}:{(published_dt.isoformat() if published_dt else 'na')}"

        normalized.append(
            {
                "collected_at": collected_at,
                "source_mode": source_mode,
                "launch_id": snap_launch_id,
                "tool_day": tool_day,
                "tool_id": tool_id,
                "repo_name": repo_name,
                "channel": channel,
                "post_type": post_type,
                "post_id": post_id,
                "hook_family": hook_family,
                "cta_family": cta_family,
                "decision_source": decision_source,
                "post_url": post_url,
                "published_at": published_dt.isoformat() if published_dt else published_at,
                "age_hours": age_hours,
                "age_days": age_days,
                "impressions": impressions,
                "likes": likes,
                "replies": replies,
                "reposts": reposts,
                "clicks": clicks,
                "engagement_simple": engagement_simple,
                "engagement_rate_simple": engagement_rate_simple,
                "click_through_like": click_through_like,
                "notes": n_notes,
            }
        )
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect post-launch feedback (buffer browser + manual import fallback)")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    parser.add_argument("--mode", choices=["auto", "browser", "manual"], default="auto")
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    collected_at = now_iso()

    collection_notes: List[str] = []
    browser_records: List[Dict[str, Any]] = []
    manual_records: List[Dict[str, Any]] = []

    if args.mode in ("auto", "browser"):
        browser_records = try_collect_buffer_browser(collection_notes)

    manual_dir = os.path.join(cdir, "imports", "feedback")
    if args.mode in ("auto", "manual"):
        manual_records = load_manual_imports(manual_dir, collection_notes)

    records: List[Dict[str, Any]] = []
    records.extend(browser_records)
    records.extend(manual_records)

    if browser_records and manual_records:
        source_mode = "mixed"
    elif browser_records:
        source_mode = "buffer_browser"
    elif manual_records:
        source_mode = "manual_import"
    else:
        source_mode = "manual_import"
        collection_notes.append("no records collected from browser/manual sources")

    raw_payload = {
        "collected_at": collected_at,
        "source_mode": source_mode,
        "records": records,
        "collection_notes": collection_notes,
    }

    raw_dir = os.path.join(cdir, "data", "feedback", "raw")
    norm_dir = os.path.join(cdir, "data", "feedback", "normalized")
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(norm_dir, exist_ok=True)

    raw_path = os.path.join(raw_dir, f"buffer_metrics_{args.date}.json")
    write_json(raw_path, raw_payload)

    days = load_state_days(os.path.join(cdir, "STATE.json"))
    launch_lookup = build_launch_lookup(cdir)
    normalized = normalize_records(collected_at, source_mode, records, days, launch_lookup)

    norm_daily_path = os.path.join(norm_dir, f"post_metrics_{args.date}.json")
    write_json(
        norm_daily_path,
        {
            "generated_at": collected_at,
            "source_mode": source_mode,
            "records": normalized,
            "sources": launch_lookup.get("sources", []),
            "notes": collection_notes,
        },
    )

    norm_jsonl_path = os.path.join(norm_dir, "post_metrics.jsonl")
    with open(norm_jsonl_path, "a", encoding="utf-8") as f:
        for row in normalized:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"[collect_post_launch_feedback] wrote: {os.path.relpath(raw_path, cdir)}")
    print(f"[collect_post_launch_feedback] wrote: {os.path.relpath(norm_daily_path, cdir)}")
    print(f"[collect_post_launch_feedback] appended: {os.path.relpath(norm_jsonl_path, cdir)} ({len(normalized)} records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
