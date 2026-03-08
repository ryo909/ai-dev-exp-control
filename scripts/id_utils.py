#!/usr/bin/env python3
import re
from datetime import date
from typing import Any


def safe_slug(value: Any, default: str = "na") -> str:
    s = str(value or "").strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s or default


def maybe_extract_tool_day(value: Any) -> str:
    s = str(value or "").strip().lower()
    m = re.search(r"day\s*0*(\d{1,3})", s)
    if m:
        return m.group(1).zfill(3)
    m2 = re.search(r"\b0*(\d{1,3})\b", s)
    if m2 and len(m2.group(1)) <= 3:
        return m2.group(1).zfill(3)
    return ""


def normalize_tool_id(day_or_tool: Any) -> str:
    day = maybe_extract_tool_day(day_or_tool)
    return f"day{day}" if day else ""


def build_launch_id(run_date: Any = None) -> str:
    if run_date is None:
        run_date = date.today().isoformat()
    return f"launch-{safe_slug(run_date)}"


def build_post_id(launch_id: str, tool_id: str, channel: str, post_type: str, index: int) -> str:
    lid = safe_slug(launch_id)
    tid = safe_slug(tool_id)
    ch = safe_slug(channel)
    pt = safe_slug(post_type)
    i = max(1, int(index))
    return f"{lid}_{tid}_{ch}_{pt}_{i:02d}"


def normalize_hook_family(text: Any) -> str:
    t = str(text or "").lower()
    if any(x in t for x in ["how", "使", "用途", "何ができる", "すぐ", "1分", "instant"]):
        return "instant-clarity"
    if any(x in t for x in ["驚", "surprise", "unexpected", "意外"]):
        return "surprise"
    if any(x in t for x in ["あるある", "共感", "relatable"]):
        return "relatable"
    if any(x in t for x in ["world", "世界観", "lore"]):
        return "worldbuilding"
    if any(x in t for x in ["utility", "実用", "役立", "効率"]):
        return "utility-first"
    return "generic"


def normalize_cta_family(text: Any) -> str:
    t = str(text or "").lower()
    if any(x in t for x in ["try", "触", "使", "demo"]):
        return "try-now"
    if any(x in t for x in ["gallery", "一覧", "browse"]):
        return "browse-gallery"
    if any(x in t for x in ["github", "repo"]):
        return "view-github"
    if any(x in t for x in ["feedback", "感想", "意見"]):
        return "feedback-welcome"
    if any(x in t for x in ["note", "記事", "read"]):
        return "read-note"
    return "generic-cta"


def normalize_post_type(value: Any) -> str:
    s = safe_slug(value)
    if s in ("hero", "secondary", "quiet"):
        return s
    if s in ("quiet-catalog", "quiet_catalog"):
        return "quiet"
    if s == "hold":
        return "hold"
    return "secondary"
