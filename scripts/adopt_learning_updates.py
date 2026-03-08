#!/usr/bin/env python3
import argparse
import glob
import json
import os
import shutil
from datetime import date, datetime, timezone


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def write_text(path: str, text: str):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def latest(pattern: str):
    files = glob.glob(pattern)
    if not files:
        return None
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def ensure_file(path: str, default_header: str):
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_text(path, default_header.rstrip() + "\n")


def upsert_managed_section(text: str, start_marker: str, end_marker: str, block: str) -> str:
    if start_marker in text and end_marker in text:
        start_idx = text.index(start_marker) + len(start_marker)
        end_idx = text.index(end_marker)
        body = text[start_idx:end_idx]
        if block.strip() and block.strip() in body:
            return text
        insert = body.rstrip() + "\n" + block.strip() + "\n"
        return text[:start_idx] + "\n" + insert + text[end_idx:]

    suffix = "\n" if text.endswith("\n") else "\n\n"
    section = f"{start_marker}\n{block.strip()}\n{end_marker}\n"
    return text + suffix + section


def make_backup(path: str, backup_dir: str, stem: str, ts: str, cdir: str):
    os.makedirs(backup_dir, exist_ok=True)
    backup_path = os.path.join(backup_dir, f"{stem}_{ts}.bak.md")
    shutil.copy2(path, backup_path)
    return os.path.relpath(backup_path, cdir)


def to_bullets(items, prefix="- "):
    lines = []
    for item in items:
        text = item.get("text", "").strip()
        why = item.get("why", "").strip()
        conf = item.get("confidence", "")
        if not text:
            continue
        lines.append(f"{prefix}{text}")
        if why:
            lines.append(f"  - why: {why}")
        if conf != "":
            lines.append(f"  - confidence: {conf}")
    return "\n".join(lines).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Adopt learning update preview into memory/feedback/sources/rules")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    preview = latest(os.path.join(cdir, "reports", "weekly", "learning", "learning_update_preview_*.json"))
    out_report = os.path.join(cdir, "reports", "weekly", "learning", f"learning_adoption_report_{args.date}.json")
    os.makedirs(os.path.dirname(out_report), exist_ok=True)

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_preview": os.path.relpath(preview, cdir) if preview else "",
        "adopted": {"memory": False, "feedback": False, "sources": False, "rules": False},
        "backups": {"memory": None, "feedback": None, "sources": None, "rules": None},
        "notes": [],
    }

    if not preview or not os.path.exists(preview):
        report["notes"].append("learning preview not found")
        with open(out_report, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        print(f"[adopt_learning_updates] preview missing, report: {os.path.relpath(out_report, cdir)}")
        return 0

    with open(preview, "r", encoding="utf-8") as f:
        data = json.load(f)

    ts = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    mem_flag = os.getenv("ADOPT_MEMORY_UPDATES", "0") == "1"
    fb_flag = os.getenv("ADOPT_FEEDBACK_UPDATES", "0") == "1"
    src_flag = os.getenv("ADOPT_SOURCE_NOTES", "0") == "1"
    rule_flag = os.getenv("ADOPT_LEARNED_RULES", "0") == "1"

    memory_path = os.path.join(cdir, "memory", "MEMORY.md")
    feedback_path = os.path.join(cdir, "shared-context", "FEEDBACK-LOG.md")
    sources_path = os.path.join(cdir, "shared-context", "SOURCES.md")
    rules_path = os.path.join(cdir, "rules", "learned_rules.md")

    ensure_file(memory_path, "# MEMORY")
    ensure_file(feedback_path, "# FEEDBACK LOG")
    ensure_file(sources_path, "# SOURCES")
    ensure_file(rules_path, "# learned_rules")

    if mem_flag:
        items = data.get("memory_candidates") or []
        if items:
            text = read_text(memory_path)
            block = f"### {args.date}\n" + to_bullets(items)
            updated = upsert_managed_section(text, "<!-- AUTO_MEMORY_UPDATES_START -->", "<!-- AUTO_MEMORY_UPDATES_END -->", block)
            if updated != text:
                report["backups"]["memory"] = make_backup(memory_path, os.path.join(cdir, "backups", "learning"), "MEMORY", ts, cdir)
                write_text(memory_path, updated)
                report["adopted"]["memory"] = True
    else:
        report["notes"].append("memory adoption skipped by env")

    if fb_flag:
        items = data.get("feedback_candidates") or []
        if items:
            text = read_text(feedback_path)
            block = f"### {args.date}\n" + to_bullets(items)
            updated = upsert_managed_section(text, "<!-- AUTO_FEEDBACK_UPDATES_START -->", "<!-- AUTO_FEEDBACK_UPDATES_END -->", block)
            if updated != text:
                report["backups"]["feedback"] = make_backup(feedback_path, os.path.join(cdir, "backups", "learning"), "FEEDBACK-LOG", ts, cdir)
                write_text(feedback_path, updated)
                report["adopted"]["feedback"] = True
    else:
        report["notes"].append("feedback adoption skipped by env")

    if src_flag:
        items = data.get("source_note_candidates") or []
        if items:
            normalized = [{"text": i.get("text", ""), "why": i.get("why", ""), "confidence": i.get("confidence", "")} for i in items]
            text = read_text(sources_path)
            block = f"### {args.date}\n" + to_bullets(normalized)
            updated = upsert_managed_section(text, "<!-- AUTO_SOURCE_NOTES_START -->", "<!-- AUTO_SOURCE_NOTES_END -->", block)
            if updated != text:
                report["backups"]["sources"] = make_backup(sources_path, os.path.join(cdir, "backups", "learning"), "SOURCES", ts, cdir)
                write_text(sources_path, updated)
                report["adopted"]["sources"] = True
    else:
        report["notes"].append("sources adoption skipped by env")

    if rule_flag:
        items = data.get("learned_rule_candidates") or []
        if items:
            text = read_text(rules_path)
            block = f"### {args.date}\n" + to_bullets(items)
            updated = upsert_managed_section(text, "<!-- AUTO_LEARNED_RULES_START -->", "<!-- AUTO_LEARNED_RULES_END -->", block)
            if updated != text:
                report["backups"]["rules"] = make_backup(rules_path, os.path.join(cdir, "backups", "learning"), "learned_rules", ts, cdir)
                write_text(rules_path, updated)
                report["adopted"]["rules"] = True
    else:
        report["notes"].append("rules adoption skipped by env")

    with open(out_report, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    print(f"[adopt_learning_updates] wrote: {os.path.relpath(out_report, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
