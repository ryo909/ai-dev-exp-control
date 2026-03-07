#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import date, datetime, timezone


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


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


def nd(day):
    s = str(day)
    return s if s.startswith("Day") else f"Day{str(s).zfill(3)}"


def get_map(items, key="day"):
    out = {}
    for x in items if isinstance(items, list) else []:
        if isinstance(x, dict):
            out[nd(x.get(key, ""))] = x
    return out


def score_day(g, p, e, r):
    growth = float(g.get("growth_readiness", 0.0) or 0.0) if g else 0.55
    portfolio = float(p.get("total_score", 0.0) or 0.0) if p else 0.55
    ev = 0.55
    if e:
        ev = (
            float(e.get("above_the_fold_clarity", 0.0) or 0.0)
            + float(e.get("cta_visibility", 0.0) or 0.0)
            + float(e.get("showcase_visual_potential", 0.0) or 0.0)
        ) / 3.0

    gate_map = {"PASS": 1.0, "PASS_WITH_NOTES": 0.72, "HOLD": 0.2}
    gate = gate_map.get((r.get("decision") if r else ""), 0.55)

    return clamp(growth * 0.33 + portfolio * 0.22 + ev * 0.2 + gate * 0.25)


def decision_for(readiness, r):
    gate = (r.get("decision") if r else "")
    if gate == "HOLD":
        return "hold"
    if readiness >= 0.78:
        return "launch_now"
    if readiness >= 0.58:
        return "launch_with_notes"
    return "quiet_catalog"


def main():
    parser = argparse.ArgumentParser(description="Build launch pack from strategy/growth/portfolio/evidence/reality")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)

    state = read_json(os.path.join(cdir, "STATE.json")) if os.path.exists(os.path.join(cdir, "STATE.json")) else {}
    catalog = read_json(os.path.join(cdir, "catalog", "catalog.json")) if os.path.exists(os.path.join(cdir, "catalog", "catalog.json")) else []
    catalog_map = {nd(x.get("day", "")): x for x in catalog if isinstance(x, dict)}

    p_strategy = latest(os.path.join(cdir, "reports", "strategy", "strategy_brief_*.json"))
    p_growth = latest(os.path.join(cdir, "reports", "growth", "growth_brief_*.json"))
    p_portfolio = latest(os.path.join(cdir, "reports", "portfolio", "portfolio_eval_*.json"))
    p_evidence = latest(os.path.join(cdir, "reports", "evidence", "evidence_*.json"))
    p_reality = latest(os.path.join(cdir, "reports", "reality", "reality_gate_*.json"))
    p_showcase = latest(os.path.join(cdir, "reports", "showcase", "showcase_plan_*.json"))
    p_tower = latest(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))
    p_next = os.path.join(cdir, "plans", "next_batch_plan.json")

    strategy = read_json(p_strategy) if p_strategy else {}
    growth = read_json(p_growth) if p_growth else {}
    portfolio = read_json(p_portfolio) if p_portfolio else {}
    evidence = read_json(p_evidence) if p_evidence else {}
    reality = read_json(p_reality) if p_reality else {}
    showcase = read_json(p_showcase) if p_showcase else {}
    tower = read_json(p_tower) if p_tower else {}
    next_batch = read_json(p_next) if os.path.exists(p_next) else {}

    inputs_used = {
        "strategy": bool(strategy),
        "growth": bool(growth),
        "portfolio": bool(portfolio),
        "evidence": bool(evidence),
        "reality": bool(reality),
        "showcase": bool(showcase),
        "control_tower": bool(tower),
    }

    g_map = get_map(growth.get("by_day", []), "day")
    p_map = get_map(portfolio.get("by_day", []), "day")
    e_map = get_map(evidence.get("by_day", []), "day")
    r_map = get_map(reality.get("by_day", []), "day")

    days = state.get("days", {}) if isinstance(state.get("days", {}), dict) else {}
    by_day = []

    for d in sorted(days.keys()):
        day = nd(d)
        st = days.get(str(d).zfill(3), {}) if isinstance(days.get(str(d).zfill(3), {}), dict) else {}
        meta = st.get("meta", {}) if isinstance(st.get("meta", {}), dict) else {}
        cat = catalog_map.get(day, {})

        repo_name = st.get("repo_name") or cat.get("repo_name") or f"ai-dev-day-{str(d).zfill(3)}"
        title = meta.get("title") or meta.get("tool_name") or cat.get("tool_name") or repo_name
        one_line = meta.get("one_sentence") or cat.get("one_sentence") or meta.get("description") or ""
        pages_url = st.get("pages_url") or cat.get("pages_url") or ""

        g = g_map.get(day, {})
        p = p_map.get(day, {})
        e = e_map.get(day, {})
        r = r_map.get(day, {})

        readiness = score_day(g, p, e, r)
        decision = decision_for(readiness, r)

        hooks = (g.get("x_hooks", []) if isinstance(g.get("x_hooks", []), list) else [])[:3]
        ctas = (g.get("cta_candidates", []) if isinstance(g.get("cta_candidates", []), list) else [])[:3]
        channels = (g.get("recommended_channel_priority", []) if isinstance(g.get("recommended_channel_priority", []), list) else [])[:3]
        if not channels:
            channels = ["quiet catalog only"] if decision == "quiet_catalog" else ["X first"]

        strengths = []
        strengths.extend((p.get("strengths", []) if isinstance(p.get("strengths", []), list) else [])[:2])
        strengths.extend((e.get("visual_strengths", []) if isinstance(e.get("visual_strengths", []), list) else [])[:2])

        issues = []
        issues.extend((p.get("issues", []) if isinstance(p.get("issues", []), list) else [])[:2])
        issues.extend((e.get("visual_issues", []) if isinstance(e.get("visual_issues", []), list) else [])[:2])
        issues.extend((r.get("showstoppers", []) if isinstance(r.get("showstoppers", []), list) else [])[:2])

        rec_actions = []
        rec_actions.extend((p.get("recommended_actions", []) if isinstance(p.get("recommended_actions", []), list) else [])[:2])
        rec_actions.extend((e.get("recommended_actions", []) if isinstance(e.get("recommended_actions", []), list) else [])[:2])

        by_day.append(
            {
                "day": day,
                "repo_name": repo_name,
                "launch_readiness": readiness,
                "decision": decision,
                "one_line_positioning": one_line or title,
                "recommended_channels": channels,
                "hook_candidates": hooks,
                "cta_candidates": ctas,
                "proof_points": strengths[:4],
                "issues": issues[:5],
                "recommended_actions": rec_actions[:4],
                "title": title,
                "pages_url": pages_url,
                "repo_url": st.get("repo_url") or cat.get("repo_url") or "",
            }
        )

    by_day.sort(key=lambda x: x.get("launch_readiness", 0.0), reverse=True)

    showcase_slot = None
    if showcase and isinstance(showcase.get("selected_showcase_slot"), int):
        showcase_slot = showcase.get("selected_showcase_slot")
    elif strategy:
        ss = (strategy.get("summary") or {}).get("showcase_slot")
        showcase_slot = ss if isinstance(ss, int) else None

    hero = by_day[0] if by_day else {}
    if showcase_slot and by_day and 1 <= showcase_slot <= len(by_day):
        hero = by_day[showcase_slot - 1]

    secondary = [x for x in by_day if x.get("day") != hero.get("day") and x.get("decision") in ("launch_now", "launch_with_notes")][:3]
    hold_candidates = [x for x in by_day if x.get("decision") == "hold"][:3]

    hero_decision = hero.get("decision", "quiet_catalog")
    hero_decision = {
        "launch_now": "launch_now",
        "launch_with_notes": "launch_with_notes",
        "hold": "hold",
        "quiet_catalog": "launch_with_notes",
    }.get(hero_decision, "launch_with_notes")

    hero_pack = {
        "one_line_positioning": hero.get("one_line_positioning", ""),
        "hero_message": f"{hero.get('title', '')} を今週の前面に出し、first-view clarity と proof point を揃えて出す",
        "audience_angles": (g_map.get(hero.get("day", ""), {}).get("positioning", {}) or {}).get("target_audience", []) if hero else [],
        "x_hooks": hero.get("hook_candidates", [])[:5],
        "cta_candidates": hero.get("cta_candidates", [])[:4],
        "launch_copy_candidates": (g_map.get(hero.get("day", ""), {}).get("launch_copy_candidates", []) if hero else [])[:3],
        "note_angles": (g_map.get(hero.get("day", ""), {}).get("note_angles", []) if hero else [])[:4],
        "note_outline": [
            "課題背景と想定ユーザー",
            "なぜこの体験設計にしたか",
            "使い方とユースケース",
            "改善予定とフィードバック募集",
        ],
        "x_thread_outline": [
            "Hook",
            "What it solves",
            "Demo link",
            "CTA",
        ],
        "gallery_caption_candidates": [
            hero.get("one_line_positioning", ""),
            f"{hero.get('title', '')}: 1分で使えて用途が伝わる小ツール",
        ][:3],
        "asset_recommendations": [
            "hero screenshot (first view)",
            "mobile screenshot",
            "CTAが見える crop",
        ],
        "visual_callouts": (e_map.get(hero.get("day", ""), {}).get("visual_strengths", []) if hero else [])[:3],
        "proof_points": hero.get("proof_points", [])[:4],
        "risk_notes": hero.get("issues", [])[:4],
    }

    launch_decisions = {
        "hero_tool": {
            "day": hero.get("day", ""),
            "repo_name": hero.get("repo_name", ""),
            "title": hero.get("title", ""),
            "pages_url": hero.get("pages_url", ""),
            "repo_url": hero.get("repo_url", ""),
            "decision": hero_decision,
            "why": [
                "launch_readiness が相対的に高い",
                "channel fit と one-line positioning が揃っている",
            ],
            "risks": hero.get("issues", [])[:4],
            "required_fixes_before_push": hero.get("recommended_actions", [])[:4],
            "preferred_channels": hero.get("recommended_channels", [])[:3],
        },
        "secondary_tools": [
            {
                "day": x.get("day"),
                "repo_name": x.get("repo_name"),
                "decision": x.get("decision"),
                "preferred_channels": x.get("recommended_channels", [])[:2],
            }
            for x in secondary
        ],
        "hold_candidates": [
            {
                "day": x.get("day"),
                "repo_name": x.get("repo_name"),
                "reason": x.get("issues", [])[:3],
            }
            for x in hold_candidates
        ],
    }

    launch_readiness = clamp(sum(x.get("launch_readiness", 0.0) for x in by_day) / max(len(by_day), 1))

    mix = []
    if hero:
        mix.append("hero push: X first + gallery follow-up")
    if secondary:
        mix.append("secondary: note + X short posts")
    if hold_candidates:
        mix.append("hold candidates: quiet catalog only")
    if not mix:
        mix.append("quiet catalog only")

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "launch_readiness": launch_readiness,
            "primary_showcase_slot": showcase_slot,
            "secondary_candidates": [x.get("day") for x in secondary],
            "recommended_distribution_mix": mix,
            "inputs_used": inputs_used,
        },
        "launch_decisions": launch_decisions,
        "hero_launch_pack": hero_pack,
        "by_day": by_day,
        "portfolio_level_actions": [
            "hero と secondary は README first-view と CTA を先に揃える",
            "hold/quiet候補は catalog導線の維持を優先",
        ],
        "recommended_launch_actions": [
            "hero tool の one-line / hook / CTA を1セットで固定",
            "secondary は channel-fit に応じて短文で出し分ける",
            "hold候補は visual clarity と demo導線を修正後に再評価",
        ],
        "sources": [
            rel(p_strategy, cdir),
            rel(p_growth, cdir),
            rel(p_portfolio, cdir),
            rel(p_evidence, cdir),
            rel(p_reality, cdir),
            rel(p_showcase, cdir),
            rel(p_tower, cdir),
            rel(p_next if os.path.exists(p_next) else "", cdir),
            "STATE.json",
            "catalog/catalog.json",
            "CATALOG.md",
        ],
    }

    out_dir = os.path.join(cdir, "reports", "launch")
    os.makedirs(out_dir, exist_ok=True)
    out_json = os.path.join(out_dir, f"launch_pack_{args.date}.json")
    out_md = os.path.join(out_dir, f"launch_pack_{args.date}.md")

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    lines = []
    lines.append(f"# Launch Pack ({args.date})")
    lines.append("")
    lines.append("## 今週の Launch 総評")
    lines.append(f"- launch_readiness: {launch_readiness}")
    lines.append(f"- distribution_mix: {', '.join(mix)}")
    lines.append("")
    lines.append("## hero tool の launch 方針")
    lines.append(f"- hero: {hero.get('day', '')} {hero.get('title', '')}")
    lines.append(f"- decision: {hero_decision}")
    lines.append(f"- why: {' / '.join(launch_decisions['hero_tool']['why'])}")
    if launch_decisions["hero_tool"]["risks"]:
        lines.append(f"- risks: {', '.join(launch_decisions['hero_tool']['risks'][:3])}")
    lines.append("")
    lines.append("## secondary candidate の扱い")
    if secondary:
        for x in secondary:
            lines.append(f"- {x.get('day')} {x.get('repo_name')}: {', '.join(x.get('recommended_channels', [])[:2])}")
    else:
        lines.append("- なし")
    lines.append("")
    lines.append("## hold すべきもの")
    if hold_candidates:
        for x in hold_candidates:
            lines.append(f"- {x.get('day')} {x.get('repo_name')}: {', '.join(x.get('issues', [])[:2])}")
    else:
        lines.append("- なし")
    lines.append("")
    lines.append("## X 用 hook 候補")
    for h in hero_pack.get("x_hooks", [])[:5]:
        lines.append(f"- {h}")
    if not hero_pack.get("x_hooks"):
        lines.append("- なし")
    lines.append("")
    lines.append("## note 記事化の切り口")
    for h in hero_pack.get("note_angles", [])[:4]:
        lines.append(f"- {h}")
    if not hero_pack.get("note_angles"):
        lines.append("- なし")
    lines.append("")
    lines.append("## gallery / catalog 短文候補")
    for c in hero_pack.get("gallery_caption_candidates", [])[:3]:
        lines.append(f"- {c}")
    lines.append("")
    lines.append("## すぐやるべき修正")
    for a in launch_decisions["hero_tool"].get("required_fixes_before_push", [])[:4]:
        lines.append(f"- {a}")
    if not launch_decisions["hero_tool"].get("required_fixes_before_push"):
        lines.append("- なし")
    lines.append("")
    lines.append("## 今週の distribution mix")
    for m in mix:
        lines.append(f"- {m}")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[build_launch_pack] wrote: {rel(out_json, cdir)}")
    print(f"[build_launch_pack] wrote: {rel(out_md, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
