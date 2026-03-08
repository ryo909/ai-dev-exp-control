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


def extract(text: str, header: str) -> str:
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


def write_report(path: str, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Adopt thesis draft/preview into shared-context/THESIS.md")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    target = os.path.join(cdir, "shared-context", "THESIS.md")
    preview = latest(os.path.join(cdir, "reports", "weekly", "thesis_preview_*.md"))
    draft = latest(os.path.join(cdir, "reports", "weekly", "thesis_update_draft_*.md"))

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "adopted": False,
        "backup_path": "",
        "source_draft": os.path.relpath(draft, cdir) if draft else "",
        "source_preview": os.path.relpath(preview, cdir) if preview else "",
        "target_file": "shared-context/THESIS.md",
        "notes": [],
    }

    out_report = os.path.join(cdir, "reports", "weekly", f"thesis_adoption_report_{args.date}.json")
    os.makedirs(os.path.dirname(out_report), exist_ok=True)

    if os.getenv("ADOPT_THESIS_DRAFT", "0") != "1":
        report["notes"].append("ADOPT_THESIS_DRAFT!=1; skipped")
        write_report(out_report, report)
        print(f"[adopt_thesis_draft] skipped, report: {os.path.relpath(out_report, cdir)}")
        return 0

    if not os.path.exists(target):
        report["notes"].append("THESIS target missing")
        write_report(out_report, report)
        return 0

    source = preview or draft
    if not source:
        report["notes"].append("preview/draft missing")
        write_report(out_report, report)
        return 0

    cur = read_text(target)
    src_text = read_text(source)
    proposed = extract(src_text, "## そのまま貼れるTHESIS本文候補") or extract(src_text, "## THESIS貼り付け用（短縮案）")
    if not proposed:
        report["notes"].append("no pasteable section found")
        write_report(out_report, report)
        return 0

    ts = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    backup_dir = os.path.join(cdir, "backups", "thesis")
    os.makedirs(backup_dir, exist_ok=True)
    backup_path = os.path.join(backup_dir, f"THESIS_{ts}.md")
    shutil.copy2(target, backup_path)

    anchor = "## 更新手順（週1テンプレ）"
    if anchor in cur:
        tail = cur.split(anchor, 1)[1]
        new_text = "# THESIS\n" + proposed.strip() + "\n\n" + anchor + tail
    else:
        new_text = "# THESIS\n" + proposed.strip() + "\n"

    with open(target, "w", encoding="utf-8") as f:
        f.write(new_text)

    report["adopted"] = True
    report["backup_path"] = os.path.relpath(backup_path, cdir)
    write_report(out_report, report)
    print(f"[adopt_thesis_draft] adopted, report: {os.path.relpath(out_report, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
