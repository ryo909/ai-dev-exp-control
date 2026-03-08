#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
from datetime import date, datetime, timezone
from urllib.parse import urlparse


WEIGHTS = {
    "one_sentence": 0.22,
    "demo_link": 0.22,
    "repo_link": 0.12,
    "novelty": 0.18,
    "clarity": 0.14,
    "showcase_fit": 0.12,
}


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def latest_file(pattern):
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


def is_valid_url(url):
    if not isinstance(url, str) or not url.strip():
        return False
    p = urlparse(url.strip())
    return p.scheme in ("http", "https") and bool(p.netloc)


def latest_workday_repo(control_dir, repo_name):
    work_root = os.path.abspath(os.path.join(control_dir, "..", ".workdays"))
    if not os.path.isdir(work_root):
        return ""
    cands = [p for p in glob.glob(os.path.join(work_root, f"{repo_name}-*")) if os.path.isdir(p)]
    if not cands:
        return ""
    cands.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return cands[0]


def read_readme_preview(repo_dir):
    if not repo_dir:
        return "", {}
    readme = os.path.join(repo_dir, "README.md")
    if not os.path.exists(readme):
        return "", {}
    txt = read_text(readme)
    low = txt.lower()
    signals = {
        "has_demo": any(k in low for k in ["demo", "live", "preview", "pages"]),
        "has_usage": any(k in low for k in ["usage", "使い方", "how to"]),
        "has_features": any(k in low for k in ["feature", "features", "機能"]),
    }
    return txt[:1200], signals


def infer_audience(meta):
    genre = (meta.get("genre") or "").lower()
    action = (meta.get("core_action") or "").lower()

    if genre in ("devtools", "coding"):
        return ["developers", "indie hackers"]
    if genre in ("productivity", "planning"):
        return ["knowledge workers", "students"]
    if genre in ("learning", "education"):
        return ["learners", "students"]
    if genre in ("health", "wellness"):
        return ["habit builders", "wellness-minded users"]
    if genre in ("fun", "game"):
        return ["casual users", "creators"]
    if action in ("rewrite", "generate"):
        return ["content creators", "busy users"]
    return ["general users", "indie makers"]


def infer_channel_priority(row):
    score = row.get("growth_readiness", 0.0)
    pages_ok = is_valid_url(row.get("pages_url", ""))
    if score >= 0.78 and pages_ok:
        return ["note + X", "showcase/gallery push"]
    if score >= 0.62:
        return ["X first", "note + X"]
    if pages_ok:
        return ["X first", "quiet catalog only"]
    return ["quiet catalog only"]


def build_hooks(title, one_sentence, twist, comp_patterns):
    base = [
        f"{title} を作って、{(twist or one_sentence)[:42]}を狙いました。",
        f"1分で使える {title}。{one_sentence[:40]}",
        f"「{(twist or 'すぐ試せる体験')}」を最短で試せる小ツールです。",
    ]
    if comp_patterns:
        base.append(f"競合観察で見えた『{comp_patterns[0]}』を、より軽く試せる形にしました。")
    base.append(f"今日の実験: {title}。触って違和感/改善点をください。")
    return base[:5]


def build_note_angles(meta, title):
    angles = [
        f"{title} を1日で組むために削った仕様と残した仕様",
        f"{meta.get('core_action', 'core action')} を短時間で価値化する設計メモ",
        "小さなWebツールを公開し続けるための実装テンプレ運用",
        "世界観を壊さずに最小差分で改善する進め方",
    ]
    return angles[:4]


def build_cta_candidates(repo_url, pages_url):
    ctas = [
        "まず触ってみて、使いづらい点を教えてください。",
        "GitHubも公開しているので実装差分も見られます。",
        "他の実験ツールも一覧から辿れます。",
        "改善アイデアがあれば気軽にください。",
    ]
    out = []
    for c in ctas:
        if "GitHub" in c and not is_valid_url(repo_url):
            continue
        if "触って" in c and not is_valid_url(pages_url):
            continue
        out.append(c)
    return out[:4] or ["フィードバック歓迎です。"]


def launch_copy_candidates(title, one_sentence, pages_url):
    url = pages_url if is_valid_url(pages_url) else "(demo link pending)"
    return [
        f"{title} を公開しました。{one_sentence} {url}",
        f"今日の1本: {title}。{one_sentence}",
    ][:3]


def read_portfolio_hotspots(portfolio):
    if not isinstance(portfolio, dict):
        return []
    hs = portfolio.get("portfolio_hotspots")
    return hs if isinstance(hs, list) else []


def build_showcase_launch_brief(selected_slot, selected_row, showcase_plan):
    inferred = False
    if not selected_slot:
        inferred = True
        selected_slot = selected_row.get("slot") if selected_row else None

    hero = ""
    if selected_row:
        hero = f"{selected_row.get('title', 'showcase tool')} を今週の見せ玉として、価値が一目で伝わる導線で押し出す"
    if inferred:
        hero = f"[inferred] {hero}" if hero else "[inferred] showcase slot を推定してlaunch方針を作成"

    hooks = selected_row.get("x_hooks", [])[:3] if selected_row else []
    ctas = selected_row.get("cta_candidates", [])[:3] if selected_row else []

    why = []
    if selected_row:
        why = [
            f"growth_readiness={selected_row.get('growth_readiness', 0.0)} と比較して相対的に高い",
            "one-line と demo 導線が揃っておりSNSで説明しやすい",
            "showcase slot として差分訴求を作りやすい",
        ]
    if inferred:
        why.append("showcase_plan 不在のため best-effort で推定")

    note_outline = [
        "課題の背景: なぜこのツールが必要か",
        "実装の核: 何を削って何を残したか",
        "使い方と3つの利用シーン",
        "今後の改善とフィードバック募集",
    ]
    x_outline = [
        "Hook: 何が1秒で分かるか",
        "Tool value: 何がどう楽になるか",
        "Demo: Pages URL",
        "CTA: 触って感想募集",
    ]

    return {
        "selected_slot": selected_slot,
        "hero_message": hero,
        "why_this_is_the_showpiece": why,
        "launch_hooks": hooks,
        "cta_candidates": ctas,
        "note_article_outline": note_outline,
        "x_thread_outline": x_outline,
    }


def main():
    parser = argparse.ArgumentParser(description="Build growth brief from weekly artifacts")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    state_path = os.path.join(cdir, "STATE.json")
    catalog_path = os.path.join(cdir, "catalog", "catalog.json")
    catalog_md_path = os.path.join(cdir, "CATALOG.md")
    next_batch_path = os.path.join(cdir, "plans", "next_batch_plan.json")

    state = read_json(state_path) if os.path.exists(state_path) else {}
    catalog = read_json(catalog_path) if os.path.exists(catalog_path) else []
    catalog_md = read_text(catalog_md_path) if os.path.exists(catalog_md_path) else ""
    next_batch = read_json(next_batch_path) if os.path.exists(next_batch_path) else {}

    latest_showcase_path = latest_file(os.path.join(cdir, "reports", "showcase", "showcase_plan_*.json"))
    showcase = read_json(latest_showcase_path) if latest_showcase_path else {}

    latest_tower_path = latest_file(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))
    tower = read_json(latest_tower_path) if latest_tower_path else {}

    latest_comp_path = latest_file(os.path.join(cdir, "reports", "competitors", "competitor_scan_*_shortlist.json"))
    comp = read_json(latest_comp_path) if latest_comp_path else {}

    latest_portfolio_path = latest_file(os.path.join(cdir, "reports", "portfolio", "portfolio_eval_*.json"))
    portfolio = read_json(latest_portfolio_path) if latest_portfolio_path else {}

    days_map = state.get("days", {}) if isinstance(state.get("days", {}), dict) else {}
    catalog_map = {str((x.get("day") or "")).zfill(3): x for x in catalog if isinstance(x, dict)}

    next_days = next_batch.get("days", []) if isinstance(next_batch.get("days", []), list) else []
    slots_map = {str((x.get("slot") or "")): x for x in next_days if isinstance(x, dict)}

    comp_patterns = comp.get("common_patterns", []) if isinstance(comp.get("common_patterns", []), list) else []
    strategic_direction = []
    strategic_direction.extend((tower.get("next_batch_recommendations", {}) or {}).get("recommended_focus", [])[:4])
    strategic_direction.extend((comp.get("twist_candidates", []) if isinstance(comp.get("twist_candidates", []), list) else [])[:2])

    by_day = []
    for day in sorted(days_map.keys()):
        d = str(day).zfill(3)
        st = days_map.get(d, {}) if isinstance(days_map.get(d, {}), dict) else {}
        meta = st.get("meta", {}) if isinstance(st.get("meta", {}), dict) else {}
        cat = catalog_map.get(d, {})

        repo_name = st.get("repo_name") or cat.get("repo_name") or f"ai-dev-day-{d}"
        repo_url = st.get("repo_url") or cat.get("repo_url") or ""
        pages_url = st.get("pages_url") or cat.get("pages_url") or ""
        title = meta.get("title") or meta.get("tool_name") or cat.get("tool_name") or repo_name
        one_sentence = meta.get("one_sentence") or cat.get("one_sentence") or meta.get("description") or ""
        twist = meta.get("twist") or ""

        work_repo = latest_workday_repo(cdir, repo_name)
        readme_preview, readme_sig = read_readme_preview(work_repo)

        novelty = 0.65 if twist else 0.45
        if comp_patterns and any(p in (twist + one_sentence) for p in comp_patterns[:3]):
            novelty -= 0.1
        if re.search(r"\b(instant|即|すぐ|1分|30秒)\b", one_sentence.lower()):
            novelty += 0.05

        clarity = 0.35
        if len(one_sentence) >= 18:
            clarity += 0.3
        if readme_sig.get("has_demo"):
            clarity += 0.15
        if readme_sig.get("has_usage"):
            clarity += 0.1

        showcase_fit = 0.4
        if is_valid_url(pages_url):
            showcase_fit += 0.2
        if len(title) >= 6:
            showcase_fit += 0.15
        if twist:
            showcase_fit += 0.15

        score_map = {
            "one_sentence": 1.0 if len(one_sentence) >= 18 else (0.6 if len(one_sentence) >= 8 else 0.2),
            "demo_link": 1.0 if is_valid_url(pages_url) else 0.2,
            "repo_link": 1.0 if is_valid_url(repo_url) else 0.3,
            "novelty": clamp(novelty),
            "clarity": clamp(clarity),
            "showcase_fit": clamp(showcase_fit),
        }

        growth_readiness = clamp(sum(score_map[k] * WEIGHTS[k] for k in WEIGHTS))
        issues = []
        actions = []

        if not is_valid_url(pages_url):
            issues.append("pages_url is missing/invalid")
            actions.append("README と CATALOG に有効な demo 導線を追加")
        if len(one_sentence) < 14:
            issues.append("one_sentence is weak")
            actions.append("one_sentence を便益中心で短く再定義")
        if not readme_sig.get("has_demo"):
            issues.append("README lacks explicit demo/live hook")
            actions.append("README冒頭に Demo/Live の1行導線を追加")

        slot_guess = None
        for s, obj in slots_map.items():
            if repo_name in (obj.get("repo_name", ""), obj.get("repo", "")):
                slot_guess = int(s)
                break

        positioning = {
            "target_audience": infer_audience(meta),
            "core_angle": one_sentence or "短時間で価値を体験できるミニツール",
            "novelty_angle": twist or "操作負荷を減らす実験的UI",
            "practical_angle": (meta.get("description") or "1分以内に使い切れる実用性")[:120],
            "emotion_angle": "迷いを減らして、すぐ試せる安心感",
        }

        row = {
            "day": f"Day{d}",
            "slot": slot_guess,
            "repo_name": repo_name,
            "title": title,
            "one_sentence": one_sentence,
            "pages_url": pages_url,
            "repo_url": repo_url,
            "growth_readiness": growth_readiness,
            "positioning": positioning,
            "x_hooks": build_hooks(title, one_sentence, twist, comp_patterns),
            "note_angles": build_note_angles(meta, title),
            "cta_candidates": build_cta_candidates(repo_url, pages_url),
            "launch_copy_candidates": launch_copy_candidates(title, one_sentence, pages_url),
            "recommended_channel_priority": [],
            "issues": issues,
            "recommended_actions": actions,
        }
        row["recommended_channel_priority"] = infer_channel_priority(row)
        by_day.append(row)

    by_day.sort(key=lambda x: x.get("growth_readiness", 0.0), reverse=True)

    showcase_slot = (
        (showcase.get("selected_showcase_slot") if isinstance(showcase, dict) else None)
        or (next_batch.get("showcase_slot") if isinstance(next_batch, dict) else None)
    )
    showcase_slot = int(showcase_slot) if isinstance(showcase_slot, int) or (isinstance(showcase_slot, str) and showcase_slot.isdigit()) else None

    selected = None
    if showcase_slot:
        selected = next((x for x in by_day if x.get("slot") == showcase_slot), None)
    if not selected and by_day:
        selected = by_day[0]

    launch_brief = build_showcase_launch_brief(showcase_slot, selected, showcase)

    days_considered = len(by_day)
    overall = clamp(sum(x.get("growth_readiness", 0.0) for x in by_day) / max(days_considered, 1))

    channel_counts = {}
    for item in by_day:
        p = (item.get("recommended_channel_priority") or ["quiet catalog only"])[0]
        channel_counts[p] = channel_counts.get(p, 0) + 1
    primary_distribution = [k for k, _ in sorted(channel_counts.items(), key=lambda kv: kv[1], reverse=True)[:3]]

    hotspots = []
    for item in by_day:
        for issue in item.get("issues", []):
            hotspots.append(issue)

    summarized_hotspots = []
    for key in [
        "pages_url is missing/invalid",
        "one_sentence is weak",
        "README lacks explicit demo/live hook",
    ]:
        c = sum(1 for h in hotspots if h == key)
        if c > 0:
            summarized_hotspots.append(f"{key} ({c})")

    portfolio_hotspots = read_portfolio_hotspots(portfolio)
    recommended_growth_actions = [
        "strengthen one-line positioning for first-view clarity",
        "align README first screen with Demo/Live CTA",
        "improve showcase launch narrative with concrete user value",
        "prepare 1 short X hook + 1 note angle per day before launch",
    ]
    if portfolio_hotspots:
        recommended_growth_actions.append("portfolio hotspot と一致する導線課題を優先修正")

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "showcase_slot": showcase_slot,
            "overall_growth_readiness": overall,
            "primary_distribution_focus": primary_distribution,
            "portfolio_dependency_used": bool(latest_portfolio_path),
            "days_considered": days_considered,
        },
        "role_context": {
            "strategic_direction": strategic_direction[:6],
            "showcase_rationale": (showcase.get("selected_showcase_plan", {}) or {}).get("showcase_goal", "") if isinstance(showcase, dict) else "",
            "portfolio_hotspots": portfolio_hotspots,
        },
        "by_day": by_day,
        "showcase_launch_brief": launch_brief,
        "recommended_growth_actions": recommended_growth_actions,
        "growth_hotspots": summarized_hotspots,
        "quality_signal_sources": [
            rel(next_batch_path if os.path.exists(next_batch_path) else "", cdir),
            rel(latest_showcase_path, cdir),
            rel(latest_tower_path, cdir),
            rel(latest_comp_path, cdir),
            rel(latest_portfolio_path, cdir),
            "STATE.json",
            "catalog/catalog.json",
            "CATALOG.md",
        ],
    }

    out_dir = os.path.join(cdir, "reports", "growth")
    os.makedirs(out_dir, exist_ok=True)
    out_json = os.path.join(out_dir, f"growth_brief_{args.date}.json")
    out_md = os.path.join(out_dir, f"growth_brief_{args.date}.md")

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    lines = []
    lines.append(f"# Growth Brief ({args.date})")
    lines.append("")
    lines.append("## 今週の Growth 総評")
    lines.append(f"- overall_growth_readiness: {payload['summary']['overall_growth_readiness']}")
    lines.append(f"- showcase_slot: {payload['summary']['showcase_slot']}")
    lines.append(f"- primary_distribution_focus: {', '.join(payload['summary']['primary_distribution_focus']) if payload['summary']['primary_distribution_focus'] else 'none'}")
    lines.append(f"- portfolio_dependency_used: {payload['summary']['portfolio_dependency_used']}")
    lines.append("")

    lines.append("## showcase slot の launch 方針")
    slb = payload["showcase_launch_brief"]
    lines.append(f"- selected_slot: {slb.get('selected_slot')}")
    lines.append(f"- hero_message: {slb.get('hero_message', '')}")
    for x in slb.get("why_this_is_the_showpiece", []):
        lines.append(f"- why: {x}")
    lines.append("")

    lines.append("## 発信に使える X hook")
    for x in (slb.get("launch_hooks") or [])[:5]:
        lines.append(f"- {x}")
    if not (slb.get("launch_hooks") or []):
        lines.append("- なし")
    lines.append("")

    lines.append("## note 記事向け切り口")
    for x in (slb.get("note_article_outline") or [])[:6]:
        lines.append(f"- {x}")
    lines.append("")

    lines.append("## 共通課題")
    for x in payload.get("growth_hotspots", [])[:6]:
        lines.append(f"- {x}")
    if not payload.get("growth_hotspots"):
        lines.append("- 明確な共通課題なし")
    lines.append("")

    lines.append("## すぐ効く改善アクション")
    for x in payload.get("recommended_growth_actions", [])[:8]:
        lines.append(f"- {x}")
    lines.append("")

    lines.append("## 各 Day の短評")
    for item in by_day:
        lines.append(f"### {item['day']} {item['title']}")
        lines.append(f"- growth_readiness: {item['growth_readiness']}")
        lines.append(f"- positioning: {item['positioning']['core_angle']}")
        lines.append(f"- channels: {', '.join(item.get('recommended_channel_priority', []))}")
        if item.get("issues"):
            lines.append(f"- issues: {', '.join(item['issues'][:2])}")
        if item.get("recommended_actions"):
            lines.append(f"- next: {', '.join(item['recommended_actions'][:2])}")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[build_growth_brief] wrote: {rel(out_json, cdir)}")
    print(f"[build_growth_brief] wrote: {rel(out_md, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
