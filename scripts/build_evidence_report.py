#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
from datetime import date, datetime, timezone
from urllib.parse import urlparse


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def clamp(v):
    if v < 0:
        return 0.0
    if v > 1:
        return 1.0
    return round(float(v), 3)


def rel(path, base):
    if not path:
        return ""
    try:
        return os.path.relpath(path, base)
    except Exception:
        return path


def is_valid_url(url):
    if not isinstance(url, str) or not url.strip():
        return False
    p = urlparse(url.strip())
    return p.scheme in ("http", "https") and bool(p.netloc)


def latest_workday_repo(control_dir, repo_name):
    root = os.path.abspath(os.path.join(control_dir, "..", ".workdays"))
    if not os.path.isdir(root):
        return ""
    cands = [p for p in glob.glob(os.path.join(root, f"{repo_name}-*")) if os.path.isdir(p)]
    if not cands:
        return ""
    cands.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return cands[0]


def read_readme(repo_dir):
    if not repo_dir:
        return ""
    p = os.path.join(repo_dir, "README.md")
    if not os.path.exists(p):
        return ""
    return read_text(p)


def read_dist_html(repo_dir):
    if not repo_dir:
        return ""
    p = os.path.join(repo_dir, "dist", "index.html")
    if not os.path.exists(p):
        p = os.path.join(repo_dir, "index.html")
    if os.path.exists(p):
        return read_text(p)
    return ""


def detect_media(repo_dir):
    if not repo_dir:
        return []
    patterns = [
        os.path.join(repo_dir, "public", "media", "*"),
        os.path.join(repo_dir, "dist", "media", "*"),
        os.path.join(repo_dir, "media", "*"),
    ]
    out = []
    for pat in patterns:
        for p in glob.glob(pat):
            if os.path.isfile(p):
                out.append(p)
    return sorted(set(out))


def evaluate_visuals(readme_text, html_text, pages_url, media_files):
    lower = (readme_text + "\n" + html_text).lower()

    has_title = bool(re.search(r"^#\s+.+", readme_text, flags=re.MULTILINE)) or ("<h1" in lower)
    has_demo = any(k in lower for k in ["demo", "live", "preview", "pages"])
    has_cta = any(k in lower for k in ["try", "start", "generate", "check", "submit", "試す", "開始", "実行"])
    mobile_friendly = "viewport" in lower
    visual_asset = len(media_files) > 0 or ("<img" in lower) or ("background" in lower)

    above = 0.2
    if has_title:
        above += 0.35
    if has_demo or is_valid_url(pages_url):
        above += 0.25
    if any(k in lower for k in ["one_sentence", "description", "summary", "概要"]):
        above += 0.1

    cta = 0.2
    if has_cta:
        cta += 0.5
    if has_demo:
        cta += 0.2

    showcase = 0.25
    if visual_asset:
        showcase += 0.3
    if has_title and has_cta:
        showcase += 0.25
    if mobile_friendly:
        showcase += 0.15

    strengths = []
    issues = []
    notes = []

    if has_title:
        strengths.append("above-the-fold にタイトル/要旨がある")
    else:
        issues.append("第一画面で何のツールか伝わりにくい")

    if has_cta:
        strengths.append("CTA がテキスト上で確認できる")
    else:
        issues.append("CTA の発見性が弱い")

    if mobile_friendly:
        strengths.append("viewport 設定があり狭幅対応が期待できる")
    else:
        issues.append("モバイル向けviewport設定が見当たらない")

    if media_files:
        strengths.append("視覚素材（media/capture）が存在する")
        notes.append(f"media_count={len(media_files)}")
    else:
        notes.append("media artifact not found")

    return clamp(above), clamp(cta), clamp(showcase), strengths, issues, notes


def main():
    parser = argparse.ArgumentParser(description="Build visual evidence report")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    state_path = os.path.join(cdir, "STATE.json")
    catalog_path = os.path.join(cdir, "catalog", "catalog.json")

    state = read_json(state_path) if os.path.exists(state_path) else {}
    catalog = read_json(catalog_path) if os.path.exists(catalog_path) else []
    catalog_map = {str((x.get("day") or "")).zfill(3): x for x in catalog if isinstance(x, dict)}

    days = state.get("days", {}) if isinstance(state.get("days", {}), dict) else {}
    by_day = []
    capture_ok = 0

    for day in sorted(days.keys()):
        d = str(day).zfill(3)
        entry = days.get(d, {}) if isinstance(days.get(d, {}), dict) else {}
        cat = catalog_map.get(d, {})

        repo_name = entry.get("repo_name") or cat.get("repo_name") or f"ai-dev-day-{d}"
        pages_url = entry.get("pages_url") or cat.get("pages_url") or ""

        repo_dir = latest_workday_repo(cdir, repo_name)
        readme_text = read_readme(repo_dir)
        html_text = read_dist_html(repo_dir)
        media_files = detect_media(repo_dir)

        above, cta, showcase, strengths, issues, notes = evaluate_visuals(readme_text, html_text, pages_url, media_files)

        status = "failed"
        if repo_dir and (readme_text or html_text):
            status = "success" if above >= 0.55 else "partial"
        elif is_valid_url(pages_url):
            status = "partial"
            notes.append("repo artifact missing, URL-only evidence")
        else:
            notes.append("repo artifact and valid pages_url are missing")

        if status == "success":
            capture_ok += 1

        actions = []
        if above < 0.55:
            actions.append("README冒頭で用途を1文で明示する")
        if cta < 0.55:
            actions.append("第一画面に CTA ボタン/リンクを追加する")
        if showcase < 0.55:
            actions.append("showcase 用に切り取りやすい visual 要素を1つ追加する")

        by_day.append(
            {
                "day": f"Day{d}",
                "repo_name": repo_name,
                "pages_url": pages_url,
                "capture_status": status,
                "visual_strengths": strengths[:5],
                "visual_issues": issues[:5],
                "cta_visibility": cta,
                "above_the_fold_clarity": above,
                "showcase_visual_potential": showcase,
                "recommended_actions": actions[:4],
                "evidence_notes": notes[:5],
            }
        )

    overall_visual_confidence = clamp(
        sum((x.get("above_the_fold_clarity", 0.0) + x.get("cta_visibility", 0.0) + x.get("showcase_visual_potential", 0.0)) / 3.0 for x in by_day)
        / max(len(by_day), 1)
    )

    hotspots = []
    weak_cta = sum(1 for x in by_day if x.get("cta_visibility", 0.0) < 0.55)
    weak_above = sum(1 for x in by_day if x.get("above_the_fold_clarity", 0.0) < 0.55)
    if weak_above:
        hotspots.append(f"above-the-fold clarity is weak in {weak_above} targets")
    if weak_cta:
        hotspots.append(f"CTA discoverability is weak in {weak_cta} targets")

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "targets_considered": len(by_day),
            "captures_succeeded": capture_ok,
            "overall_visual_confidence": overall_visual_confidence,
        },
        "by_day": by_day,
        "portfolio_relevant_findings": hotspots,
        "recommended_evidence_actions": [
            "improve above-the-fold utility sentence",
            "place primary CTA in first viewport",
            "prepare one showcase-friendly visual moment",
        ],
    }

    out_dir = os.path.join(cdir, "reports", "evidence")
    os.makedirs(out_dir, exist_ok=True)
    out_json = os.path.join(out_dir, f"evidence_{args.date}.json")
    out_md = os.path.join(out_dir, f"evidence_{args.date}.md")

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    lines = []
    lines.append(f"# Evidence Report ({args.date})")
    lines.append("")
    lines.append(f"- targets_considered: {payload['summary']['targets_considered']}")
    lines.append(f"- captures_succeeded: {payload['summary']['captures_succeeded']}")
    lines.append(f"- overall_visual_confidence: {payload['summary']['overall_visual_confidence']}")
    lines.append("")
    lines.append("## Portfolio Relevant Findings")
    if payload["portfolio_relevant_findings"]:
        for x in payload["portfolio_relevant_findings"]:
            lines.append(f"- {x}")
    else:
        lines.append("- no major hotspot")
    lines.append("")
    lines.append("## By Day")
    for row in by_day:
        lines.append(f"### {row['day']} {row['repo_name']}")
        lines.append(f"- status: {row['capture_status']}")
        lines.append(f"- above_the_fold_clarity: {row['above_the_fold_clarity']}")
        lines.append(f"- cta_visibility: {row['cta_visibility']}")
        lines.append(f"- showcase_visual_potential: {row['showcase_visual_potential']}")
        if row["visual_issues"]:
            lines.append(f"- issues: {', '.join(row['visual_issues'][:2])}")
        if row["recommended_actions"]:
            lines.append(f"- next: {', '.join(row['recommended_actions'][:2])}")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[build_evidence_report] wrote: {rel(out_json, cdir)}")
    print(f"[build_evidence_report] wrote: {rel(out_md, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
