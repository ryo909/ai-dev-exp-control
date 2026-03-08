#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from urllib.parse import urlparse

WEIGHTS = {
    "link_health": 0.25,
    "readme_hygiene": 0.20,
    "demo_clarity": 0.20,
    "catalog_consistency": 0.15,
    "showcase_readiness": 0.20,
}

URL_TIMEOUT_SEC = 4


def read_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def rel(path: str, base: str) -> str:
    try:
        return os.path.relpath(path, base)
    except Exception:
        return path


def clamp(v: float) -> float:
    if v < 0.0:
        return 0.0
    if v > 1.0:
        return 1.0
    return round(v, 3)


def latest_workday_repo(control_dir: str, repo_name: str) -> str:
    work_root = os.path.abspath(os.path.join(control_dir, "..", ".workdays"))
    if not os.path.isdir(work_root):
        return ""

    pattern = os.path.join(work_root, f"{repo_name}-*")
    cands = [p for p in glob.glob(pattern) if os.path.isdir(p)]
    if not cands:
        return ""

    cands.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return cands[0]


def is_valid_url(u: str) -> bool:
    if not isinstance(u, str) or not u.strip():
        return False
    parsed = urlparse(u.strip())
    return parsed.scheme in ("http", "https") and bool(parsed.netloc)


def probe_url(url: str) -> tuple[bool, str]:
    if not is_valid_url(url):
        return False, "invalid url"

    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "ai-dev-exp-control/portfolio-evaluator"})
    try:
        with urllib.request.urlopen(req, timeout=URL_TIMEOUT_SEC) as resp:
            code = getattr(resp, "status", 200)
            return 200 <= int(code) < 400, f"status={code}"
    except urllib.error.HTTPError as e:
        # Keep best-effort: 401/403 can still mean URL exists.
        if e.code in (401, 403, 429):
            return True, f"http={e.code} (best-effort exists)"
        return False, f"http={e.code}"
    except Exception as e:
        # Retry with GET once.
        try:
            req2 = urllib.request.Request(url, method="GET", headers={"User-Agent": "ai-dev-exp-control/portfolio-evaluator"})
            with urllib.request.urlopen(req2, timeout=URL_TIMEOUT_SEC) as resp:
                code = getattr(resp, "status", 200)
                return 200 <= int(code) < 400, f"status={code}"
        except Exception as e2:
            return False, f"network_error={type(e2).__name__}"


def score_link_health(repo_url: str, pages_url: str, issues: list[str], strengths: list[str]) -> float:
    score = 0.0

    if repo_url:
        if is_valid_url(repo_url):
            score += 0.25
            ok, detail = probe_url(repo_url)
            if ok:
                score += 0.25
                strengths.append("repo_url is reachable (best-effort)")
            else:
                issues.append(f"repo_url probe failed: {detail}")
        else:
            issues.append("repo_url format is invalid")
    else:
        issues.append("repo_url is missing")

    if pages_url:
        if is_valid_url(pages_url):
            score += 0.25
            ok, detail = probe_url(pages_url)
            if ok:
                score += 0.25
                strengths.append("pages_url is reachable (best-effort)")
            else:
                issues.append(f"pages_url probe failed: {detail}")
        else:
            issues.append("pages_url format is invalid")
    else:
        issues.append("pages_url is missing")

    return clamp(score)


def detect_readme_sections(text: str) -> dict:
    lower = text.lower()
    return {
        "has_overview": bool(re.search(r"^#\s+.+", text, flags=re.MULTILINE)) and len(text.strip()) >= 40,
        "has_demo_link": any(k in lower for k in ["demo", "live", "preview", "pages", "github pages"]),
        "has_usage": any(k in lower for k in ["usage", "使い方", "how to", "手順"]),
        "has_features": any(k in lower for k in ["features", "feature", "機能", "what it does"]),
        "has_images": ("![" in text) or ("<img" in lower),
    }


def score_readme_hygiene(readme_path: str, issues: list[str], strengths: list[str]) -> tuple[float, dict]:
    if not readme_path or not os.path.exists(readme_path):
        issues.append("README.md is missing")
        return 0.0, {}

    text = read_text(readme_path)
    if not text.strip():
        issues.append("README.md is empty")
        return 0.0, {}

    sec = detect_readme_sections(text)
    score = 0.15  # existence baseline

    if sec["has_overview"]:
        score += 0.25
        strengths.append("README has overview/title")
    else:
        issues.append("README above-the-fold overview is weak")

    if sec["has_demo_link"]:
        score += 0.25
        strengths.append("README includes demo/live guidance")
    else:
        issues.append("README lacks clear demo/live guidance")

    if sec["has_usage"]:
        score += 0.2
    else:
        issues.append("README lacks usage section")

    if sec["has_features"]:
        score += 0.1

    if sec["has_images"]:
        score += 0.05

    return clamp(score), sec


def score_demo_clarity(meta: dict, readme_sections: dict, pages_url: str, issues: list[str], strengths: list[str]) -> float:
    score = 0.0
    title = (meta.get("title") or meta.get("tool_name") or "").strip()
    one_sentence = (meta.get("one_sentence") or "").strip()
    desc = (meta.get("description") or "").strip()

    if title:
        score += 0.2
    else:
        issues.append("title/tool_name is missing")

    if one_sentence and len(one_sentence) >= 12:
        score += 0.3
        strengths.append("one_sentence is present")
    elif desc and len(desc) >= 12:
        score += 0.2
        issues.append("one_sentence is weak or missing (description used)")
    else:
        issues.append("tool summary is unclear")

    if pages_url and is_valid_url(pages_url):
        score += 0.3
    else:
        issues.append("demo entry (pages_url) is unclear")

    if readme_sections.get("has_demo_link") and readme_sections.get("has_overview"):
        score += 0.2

    return clamp(score)


def score_catalog_consistency(state_entry: dict, catalog_entry: dict, issues: list[str], strengths: list[str]) -> float:
    score = 1.0
    checks = [
        ("repo_name", state_entry.get("repo_name", ""), catalog_entry.get("repo_name", "")),
        ("repo_url", state_entry.get("repo_url", ""), catalog_entry.get("repo_url", "")),
        ("pages_url", state_entry.get("pages_url", ""), catalog_entry.get("pages_url", "")),
        ("status", state_entry.get("status", ""), catalog_entry.get("status", "")),
        ("tool_name", (state_entry.get("meta") or {}).get("tool_name", ""), catalog_entry.get("tool_name", "")),
    ]

    mismatches = 0
    for key, sv, cv in checks:
        if (sv or "") != (cv or ""):
            mismatches += 1
            issues.append(f"catalog mismatch: {key} (state='{sv}' vs catalog='{cv}')")

    if mismatches == 0:
        strengths.append("catalog and STATE are consistent")
    else:
        score -= min(0.8, mismatches * 0.16)

    return clamp(score)


def score_showcase_readiness(meta: dict, readme_score: float, demo_score: float, link_score: float, issues: list[str], strengths: list[str]) -> float:
    score = 0.0

    title = (meta.get("title") or meta.get("tool_name") or "").strip()
    one_sentence = (meta.get("one_sentence") or "").strip()
    twist = (meta.get("twist") or "").strip()

    if title and len(title) >= 5:
        score += 0.2
    if one_sentence and len(one_sentence) >= 16:
        score += 0.25
    else:
        issues.append("one_sentence is too weak for portfolio browsing")

    if twist and len(twist) >= 8:
        score += 0.2

    score += (readme_score * 0.2)
    score += (demo_score * 0.1)
    score += (link_score * 0.05)

    if score >= 0.75:
        strengths.append("showcase-ready presentation is strong")

    return clamp(score)


def weighted_total(sub_scores: dict) -> float:
    total = 0.0
    for k, w in WEIGHTS.items():
        total += float(sub_scores.get(k, 0.0)) * w
    return clamp(total)


def collect_days(state: dict) -> list[tuple[str, dict]]:
    days = state.get("days", {}) if isinstance(state.get("days", {}), dict) else {}
    out = []
    for d in sorted(days.keys()):
        out.append((d, days[d]))
    return out


def md_escape(x: str) -> str:
    return (x or "").replace("\n", " ").replace("|", "\\|")


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate portfolio quality across day repos (best-effort)")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)

    state_path = os.path.join(cdir, "STATE.json")
    catalog_path = os.path.join(cdir, "catalog", "catalog.json")
    catalog_md_path = os.path.join(cdir, "CATALOG.md")

    if not os.path.exists(state_path):
        print("[evaluate_portfolio] STATE.json missing; skip")
        return 0

    state = read_json(state_path)
    catalog = read_json(catalog_path) if os.path.exists(catalog_path) else []
    catalog_by_day = {str(item.get("day", "")).zfill(3): item for item in catalog if isinstance(item, dict)}
    catalog_md = read_text(catalog_md_path) if os.path.exists(catalog_md_path) else ""

    by_day = []
    hotspots = []

    for day, entry in collect_days(state):
        meta = entry.get("meta") if isinstance(entry.get("meta"), dict) else {}
        repo_name = entry.get("repo_name", f"ai-dev-day-{day}")
        repo_url = entry.get("repo_url", "")
        pages_url = entry.get("pages_url", "")
        status = entry.get("status", "")

        issues = []
        strengths = []
        actions = []

        repo_path = latest_workday_repo(cdir, repo_name)
        readme_path = os.path.join(repo_path, "README.md") if repo_path else ""

        link_score = score_link_health(repo_url, pages_url, issues, strengths)
        readme_score, readme_sections = score_readme_hygiene(readme_path, issues, strengths)
        demo_score = score_demo_clarity(meta, readme_sections, pages_url, issues, strengths)

        catalog_entry = catalog_by_day.get(day, {})
        if not catalog_entry:
            issues.append("catalog entry is missing for this day")
            catalog_score = 0.4
        else:
            catalog_score = score_catalog_consistency(entry, catalog_entry, issues, strengths)

        if catalog_md and f"Day{day}" not in catalog_md:
            issues.append("CATALOG.md may not include this day")
            catalog_score = clamp(catalog_score - 0.1)

        showcase_score = score_showcase_readiness(meta, readme_score, demo_score, link_score, issues, strengths)

        sub_scores = {
            "link_health": link_score,
            "readme_hygiene": readme_score,
            "demo_clarity": demo_score,
            "catalog_consistency": catalog_score,
            "showcase_readiness": showcase_score,
        }

        total = weighted_total(sub_scores)

        if link_score < 0.6:
            actions.append("fix repo/pages links and confirm demo reachability")
        if readme_score < 0.6:
            actions.append("improve README above-the-fold + usage/demo sections")
        if demo_score < 0.6:
            actions.append("strengthen one-line value proposition and demo entry clarity")
        if catalog_score < 0.7:
            actions.append("sync STATE and catalog fields (repo/pages/status/title)")
        if showcase_score < 0.65:
            actions.append("tighten twist/one_sentence for stronger showcase pitch")

        by_day.append(
            {
                "day": f"Day{day}",
                "repo_name": repo_name,
                "repo_url": repo_url,
                "pages_url": pages_url,
                "status": status,
                "total_score": total,
                "sub_scores": sub_scores,
                "issues": sorted(set(issues))[:12],
                "strengths": sorted(set(strengths))[:8],
                "recommended_actions": actions[:6],
            }
        )

    if not by_day:
        print("[evaluate_portfolio] no days to evaluate; skip")
        return 0

    avg_link = clamp(sum(x["sub_scores"]["link_health"] for x in by_day) / len(by_day))
    avg_readme = clamp(sum(x["sub_scores"]["readme_hygiene"] for x in by_day) / len(by_day))
    avg_demo = clamp(sum(x["sub_scores"]["demo_clarity"] for x in by_day) / len(by_day))
    overall = clamp(sum(x["total_score"] for x in by_day) / len(by_day))

    def hotspot_count(prefix: str) -> int:
        c = 0
        for item in by_day:
            for issue in item.get("issues", []):
                if prefix in issue:
                    c += 1
        return c

    if hotspot_count("pages_url") > 0:
        hotspots.append("missing or weak live demo links")
    if hotspot_count("README") > 0:
        hotspots.append("README above-the-fold clarity is inconsistent")
    if hotspot_count("catalog mismatch") > 0:
        hotspots.append("STATE and catalog consistency gaps")
    if hotspot_count("one_sentence") > 0:
        hotspots.append("one-line positioning is weak for portfolio browsing")

    top_showcase = sorted(by_day, key=lambda x: x["sub_scores"]["showcase_readiness"], reverse=True)[:3]
    low_total = sorted(by_day, key=lambda x: x["total_score"])[:3]

    rec_actions = []
    if avg_link < 0.8:
        rec_actions.append("Reduce broken or missing live demo links")
    if avg_readme < 0.75:
        rec_actions.append("Improve README above-the-fold clarity and usage guidance")
    if avg_demo < 0.75:
        rec_actions.append("Strengthen demo-first messaging and one-line positioning")
    if any("catalog" in h for h in hotspots):
        rec_actions.append("Synchronize STATE/catalog/CATALOG publication records")
    rec_actions.append("Use showcase-ready repos as reference templates for presentation quality")

    summary = {
        "days_considered": len(by_day),
        "overall_score": overall,
        "avg_link_health": avg_link,
        "avg_readme_score": avg_readme,
        "avg_demo_clarity": avg_demo,
    }

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": summary,
        "by_day": by_day,
        "portfolio_hotspots": hotspots,
        "recommended_portfolio_actions": rec_actions[:6],
    }

    out_dir = os.path.join(cdir, "reports", "portfolio")
    os.makedirs(out_dir, exist_ok=True)
    out_json = os.path.join(out_dir, f"portfolio_eval_{args.date}.json")
    out_md = os.path.join(out_dir, f"portfolio_eval_{args.date}.md")

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    lines = []
    lines.append(f"# Portfolio Evaluation ({args.date})")
    lines.append("")
    lines.append("## Summary")
    lines.append(f"- days_considered: {summary['days_considered']}")
    lines.append(f"- overall_score: {summary['overall_score']}")
    lines.append(f"- avg_link_health: {summary['avg_link_health']}")
    lines.append(f"- avg_readme_score: {summary['avg_readme_score']}")
    lines.append(f"- avg_demo_clarity: {summary['avg_demo_clarity']}")
    lines.append("")

    lines.append("## Showcase-ready Candidates")
    for item in top_showcase:
        lines.append(f"- {item['day']} {item['repo_name']}: showcase={item['sub_scores']['showcase_readiness']}, total={item['total_score']}")
    lines.append("")

    lines.append("## Lower-score Repos (priority fixes)")
    for item in low_total:
        lines.append(f"- {item['day']} {item['repo_name']}: total={item['total_score']}")
    lines.append("")

    lines.append("## Portfolio Hotspots")
    if hotspots:
        for h in hotspots:
            lines.append(f"- {h}")
    else:
        lines.append("- no critical hotspot detected")
    lines.append("")

    lines.append("## Recommended Portfolio Actions")
    for a in rec_actions[:6]:
        lines.append(f"- {a}")
    lines.append("")

    lines.append("## By Day")
    lines.append("| Day | Repo | Total | Link | README | Demo | Catalog | Showcase |")
    lines.append("|---|---|---:|---:|---:|---:|---:|---:|")
    for item in by_day:
        s = item["sub_scores"]
        lines.append(
            f"| {item['day']} | {md_escape(item['repo_name'])} | {item['total_score']} | {s['link_health']} | {s['readme_hygiene']} | {s['demo_clarity']} | {s['catalog_consistency']} | {s['showcase_readiness']} |"
        )
    lines.append("")

    lines.append("## Short Notes")
    for item in by_day:
        lines.append(f"### {item['day']} {item['repo_name']}")
        lines.append(f"- total: {item['total_score']}")
        if item.get("strengths"):
            lines.append(f"- strengths: {', '.join(item['strengths'][:3])}")
        if item.get("issues"):
            lines.append(f"- issues: {', '.join(item['issues'][:3])}")
        if item.get("recommended_actions"):
            lines.append(f"- next: {', '.join(item['recommended_actions'][:2])}")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[evaluate_portfolio] wrote: {rel(out_json, cdir)}")
    print(f"[evaluate_portfolio] wrote: {rel(out_md, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
