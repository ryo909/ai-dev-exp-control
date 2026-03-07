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


def latest(pattern: str):
    files = glob.glob(pattern)
    if not files:
        return None
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def extract_block(text: str, header: str) -> str:
    lines = text.splitlines()
    out = []
    active = False
    for ln in lines:
        if ln.strip() == header:
            active = True
            continue
        if active and ln.strip().startswith("## "):
            break
        if active:
            out.append(ln)
    return "\n".join(out).strip()


def replace_or_append_section(text: str, title: str, body: str) -> str:
    marker = f"## {title}"
    lines = text.splitlines()
    start = None
    end = None
    for i, ln in enumerate(lines):
        if ln.strip() == marker:
            start = i
            continue
        if start is not None and ln.startswith("## "):
            end = i
            break
    if start is None:
        return text.rstrip() + "\n\n" + marker + "\n" + body.strip() + "\n"
    if end is None:
        end = len(lines)
    new_lines = lines[:start] + [marker] + body.strip().splitlines() + lines[end:]
    return "\n".join(new_lines).rstrip() + "\n"


def write_json(path: str, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Adopt weekly_run preview into system/weekly_run.md")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    target = os.path.join(cdir, "system", "weekly_run.md")
    preview = latest(os.path.join(cdir, "reports", "weekly", "weekly_run_preview_*.md"))

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "adopted": False,
        "backup_path": "",
        "source_preview": os.path.relpath(preview, cdir) if preview else "",
        "target_file": "system/weekly_run.md",
        "recommended_profile": "safe",
        "notes": [],
    }

    out_report = os.path.join(cdir, "reports", "weekly", f"weekly_run_adoption_report_{args.date}.json")

    if os.getenv("ADOPT_WEEKLY_RUN", "0") != "1":
        report["notes"].append("ADOPT_WEEKLY_RUN!=1; skipped")
        write_json(out_report, report)
        print(f"[adopt_weekly_run] skipped, report: {os.path.relpath(out_report, cdir)}")
        return 0

    if not preview or not os.path.exists(preview):
        report["notes"].append("weekly_run preview missing")
        write_json(out_report, report)
        return 0

    if not os.path.exists(target):
        with open(target, "w", encoding="utf-8") as f:
            f.write("# Weekly Run\n\n## 基本手順\n- DRY_RUN=1 で確認してから本実行する\n")

    current = read_text(target)
    ptxt = read_text(preview)

    policy = extract_block(ptxt, "### 今週の運用方針")
    commands = extract_block(ptxt, "### 推奨コマンド例")
    if not policy:
        policy = "- adoption profile: safe\n- control_tower -> next_batch_plan -> thesis_update_draft -> weekly_run_report"
    if not commands:
        commands = "- DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh"

    rec_profile = "safe"
    for ln in policy.splitlines():
        if "adoption profile:" in ln:
            rec_profile = ln.split(":", 1)[1].strip()
            break
    report["recommended_profile"] = rec_profile

    ts = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    backup_dir = os.path.join(cdir, "backups", "weekly_run")
    os.makedirs(backup_dir, exist_ok=True)
    backup = os.path.join(backup_dir, f"weekly_run_{ts}.md")
    shutil.copy2(target, backup)

    updated = replace_or_append_section(current, "今週の運用方針", policy)
    updated = replace_or_append_section(updated, "推奨コマンド例", commands)

    with open(target, "w", encoding="utf-8") as f:
        f.write(updated)

    report["adopted"] = True
    report["backup_path"] = os.path.relpath(backup, cdir)
    write_json(out_report, report)
    print(f"[adopt_weekly_run] adopted, report: {os.path.relpath(out_report, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
