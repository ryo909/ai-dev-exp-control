#!/usr/bin/env python3
import argparse
import glob
import os
from datetime import date


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def latest(pattern: str):
    files = glob.glob(pattern)
    if not files:
        return None
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def extract_section(text: str, header: str) -> str:
    lines = text.splitlines()
    out = []
    active = False
    for ln in lines:
        stripped = ln.strip()
        if stripped == header:
            active = True
            continue
        if active and stripped.startswith("#"):
            break
        if active:
            out.append(ln)
    return "\n".join(out).strip()


def bullet_lines(text: str):
    return [ln for ln in text.splitlines() if ln.strip().startswith("-")]


def main() -> int:
    parser = argparse.ArgumentParser(description="Build thesis preview from latest thesis draft and current THESIS")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    thesis_path = os.path.join(cdir, "shared-context", "THESIS.md")
    draft_path = latest(os.path.join(cdir, "reports", "weekly", "thesis_update_draft_*.md"))

    if not os.path.exists(thesis_path):
        print("[build_thesis_preview] THESIS.md not found; skip")
        return 0
    if not draft_path:
        print("[build_thesis_preview] thesis draft not found; skip")
        return 0

    cur = read_text(thesis_path)
    draft = read_text(draft_path)

    current_summary = extract_section(cur, "# THESIS")
    proposed_focus = extract_section(draft, "## 次週の重点候補（1〜3）")
    proposed_mix = extract_section(draft, "## 推奨 complexity mix")
    source_bias = extract_section(draft, "## 推奨 source bias")
    comp_bias = extract_section(draft, "## 推奨 component bias")
    dont_do = extract_section(draft, "## 今週はやらないこと")
    pasteable = extract_section(draft, "## THESIS貼り付け用（短縮案）")

    out = []
    out.append(f"# Thesis Preview ({args.date})")
    out.append("")
    out.append("## current thesis summary")
    out.append(current_summary or "(none)")
    out.append("")
    out.append("## proposed thesis summary")
    out.append("\n".join(bullet_lines(pasteable)) or pasteable or "(none)")
    out.append("")
    out.append("## 差分の要点")
    out.append("- 重点候補・complexity mix・source/component bias を週次重点として明示")
    out.append("- 更新手順セクションは保持し、週次重点ブロックだけ更新する方針")
    out.append("")
    out.append("## 新しい重点候補")
    out.append(proposed_focus or "(none)")
    out.append("")
    out.append("## 推奨 complexity mix")
    out.append(proposed_mix or "(none)")
    out.append("")
    out.append("## source bias / component bias")
    out.append(source_bias or "(none)")
    out.append(comp_bias or "(none)")
    out.append("")
    out.append("## 今週はやらないこと")
    out.append(dont_do or "(none)")
    out.append("")
    out.append("## そのまま貼れるTHESIS本文候補")
    out.append(pasteable or "(none)")

    out_path = os.path.join(cdir, "reports", "weekly", f"thesis_preview_{args.date}.md")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

    print(f"[build_thesis_preview] wrote: {os.path.relpath(out_path, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
