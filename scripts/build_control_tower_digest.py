#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
from collections import Counter, defaultdict
from datetime import date, datetime, timezone


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def latest_file(pattern):
    files = glob.glob(pattern)
    if not files:
        return None
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def safe_score_avg(vals):
    if not vals:
        return 0.0
    return round(sum(vals) / len(vals), 2)


def decide_mix(tier_perf):
    # baseline 4/2/1 and adaptive correction with guardrails.
    mix = {"small": 4, "medium": 2, "large": 1}

    large = tier_perf.get("large", {})
    medium = tier_perf.get("medium", {})
    small = tier_perf.get("small", {})

    if large.get("avg_score", 0.0) < 0.5 or large.get("fallback_count", 0) >= 1:
        mix["large"] = 0
        mix["medium"] += 1

    if medium.get("count", 0) > 0 and medium.get("avg_score", 0.0) >= 0.7 and medium.get("fallback_count", 0) == 0:
        if mix["small"] > 3:
            mix["small"] -= 1
            mix["medium"] += 1

    mix["small"] = max(3, min(5, mix["small"]))

    total = sum(mix.values())
    while total > 7:
        if mix["small"] > 3:
            mix["small"] -= 1
        elif mix["medium"] > 1:
            mix["medium"] -= 1
        else:
            mix["large"] = max(0, mix["large"] - 1)
        total = sum(mix.values())
    while total < 7:
        if mix["small"] < 5:
            mix["small"] += 1
        else:
            mix["medium"] += 1
        total = sum(mix.values())

    return mix


def day_decision(day, tier, quality, has_enh, has_fallback, summary_path):
    score = quality.get("tier_expectation_score") if quality else None
    score = score if isinstance(score, (int, float)) else 0.0
    has_summary = bool(summary_path and os.path.exists(summary_path))

    if has_summary:
        txt = read_text(summary_path).lower()
        heavy = len(txt) > 5000 or len(re.findall(r"error|failed|traceback|exception", txt)) >= 8
    else:
        heavy = False

    if has_summary and heavy:
        return "retry_later", "failure summary is heavy; retry after manual stabilization"

    thresholds = {"small": 0.5, "medium": 0.6, "large": 0.7}
    th = thresholds.get(tier, 0.6)

    if has_fallback and score < th:
        return "downgrade", "fallback exists and quality is below tier threshold"
    if has_enh and score < max(0.45, th - 0.1):
        return "enhance", "enhancement candidates available and quality is mid/low"
    if score >= th and not has_fallback:
        return "keep", "quality meets threshold without fallback"
    return "enhance", "default to enhancement recommendation"


def main():
    parser = argparse.ArgumentParser(description="Build weekly control tower digest")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)

    state_path = os.path.join(cdir, "STATE.json")
    if not os.path.exists(state_path):
        print("[build_control_tower_digest] STATE.json missing; skip")
        return 0
    state = read_json(state_path)

    signals_path = os.path.join(cdir, "shared-context", "SIGNALS.md")
    coverage_path = os.path.join(cdir, "reports", "coverage.json")
    memory_path = os.path.join(cdir, "memory", "MEMORY.md")
    feedback_path = os.path.join(cdir, "shared-context", "FEEDBACK-LOG.md")
    sources_path = os.path.join(cdir, "shared-context", "SOURCES.md")

    latest_comp = latest_file(os.path.join(cdir, "reports", "competitors", "competitor_scan_*_shortlist.json"))
    comp = read_json(latest_comp) if latest_comp else {}
    latest_showcase = latest_file(os.path.join(cdir, "reports", "showcase", "showcase_plan_*.json"))
    showcase = read_json(latest_showcase) if latest_showcase else {}
    latest_portfolio = latest_file(os.path.join(cdir, "reports", "portfolio", "portfolio_eval_*.json"))
    portfolio = read_json(latest_portfolio) if latest_portfolio else {}
    latest_growth = latest_file(os.path.join(cdir, "reports", "growth", "growth_brief_*.json"))
    growth = read_json(latest_growth) if latest_growth else {}
    latest_strategy = latest_file(os.path.join(cdir, "reports", "strategy", "strategy_brief_*.json"))
    strategy = read_json(latest_strategy) if latest_strategy else {}
    latest_evidence = latest_file(os.path.join(cdir, "reports", "evidence", "evidence_*.json"))
    evidence = read_json(latest_evidence) if latest_evidence else {}
    latest_reality = latest_file(os.path.join(cdir, "reports", "reality", "reality_gate_*.json"))
    reality = read_json(latest_reality) if latest_reality else {}

    quality_files = sorted(glob.glob(os.path.join(cdir, "reports", "quality", "day*_quality.json")))
    enh_files = sorted(glob.glob(os.path.join(cdir, "plans", "candidates", "day*_enhanced_candidates.json")))
    fallback_files = sorted(glob.glob(os.path.join(cdir, "plans", "candidates", "day*_fallback_plan.json")))
    upgrade_files = sorted(glob.glob(os.path.join(cdir, "plans", "candidates", "day*_quality_upgrade_candidates.json")))

    fallback_by_day = {}
    for p in fallback_files:
        try:
            x = read_json(p)
            fallback_by_day[str(x.get("day", "")).zfill(3)] = x
        except Exception:
            pass

    enh_by_day = {}
    for p in enh_files:
        try:
            x = read_json(p)
            enh_by_day[str(x.get("day", "")).zfill(3)] = x
        except Exception:
            pass

    quality_by_day = {}
    for p in quality_files:
        try:
            q = read_json(p)
            quality_by_day[str(q.get("day", "")).zfill(3)] = q
        except Exception:
            pass

    days = state.get("days", {})
    day_keys = sorted(days.keys())

    success_count = 0
    failure_count = 0
    genre_counter = Counter()
    action_counter = Counter()
    twist_counter = Counter()

    tier_scores = defaultdict(list)
    tier_confidence = defaultdict(Counter)
    tier_missing_components = defaultdict(Counter)
    tier_counts = Counter()
    tier_fallbacks = Counter()

    for d in day_keys:
        meta = (days.get(d) or {}).get("meta") or {}
        status = (days.get(d) or {}).get("status", "")
        if status in ("done", "posted", "deployed"):
            success_count += 1
        if status == "failed":
            failure_count += 1

        g = meta.get("genre")
        if g:
            genre_counter[g] += 1
        a = meta.get("core_action")
        if a:
            action_counter[a] += 1
        t = meta.get("twist")
        if t:
            twist_counter[t] += 1

        tier = meta.get("complexity_tier", "small")
        tier_counts[tier] += 1

        q = quality_by_day.get(d)
        if q:
            s = q.get("tier_expectation_score")
            if isinstance(s, (int, float)):
                tier_scores[tier].append(float(s))
            conf = q.get("confidence")
            if isinstance(conf, str) and conf:
                tier_confidence[tier][conf] += 1
            for comp in q.get("missing_components") or []:
                if isinstance(comp, str) and comp:
                    tier_missing_components[tier][comp] += 1

        if d in fallback_by_day:
            tier_fallbacks[tier] += 1

    tier_perf = {}
    for t in ("small", "medium", "large"):
        tier_perf[t] = {
            "count": int(tier_counts.get(t, 0)),
            "avg_score": safe_score_avg(tier_scores.get(t, [])),
            "fallback_count": int(tier_fallbacks.get(t, 0)),
            "confidence_distribution": dict(tier_confidence.get(t, {})),
        }

    blocked_domains = Counter()
    successful_domains = Counter()
    top_sources = Counter()
    for tgt in comp.get("targets", []) if isinstance(comp.get("targets"), list) else []:
        src = tgt.get("source")
        dom = tgt.get("domain")
        st = tgt.get("status")
        if src:
            top_sources[src] += 1
        if dom and st == "blocked":
            blocked_domains[dom] += 1
        if dom and st == "ok":
            successful_domains[dom] += 1

    day_decisions = []
    for d in day_keys[-20:]:
        meta = (days.get(d) or {}).get("meta") or {}
        tier = meta.get("complexity_tier", "small")
        q = quality_by_day.get(d)
        has_enh = d in enh_by_day
        has_fb = d in fallback_by_day
        summary = os.path.join(cdir, "logs", f"Day{d}.summary.md")
        decision, reason = day_decision(d, tier, q, has_enh, has_fb, summary)
        rec_components = []
        if q:
            rec_components = (
                (q.get("recommendation", {}) or {}).get("add_components", [])
                or q.get("upgrade_candidates", [])
                or q.get("missing_components", [])
                or []
            )

        day_decisions.append(
            {
                "day": d,
                "complexity_tier": tier,
                "quality_score": (q.get("tier_expectation_score") if q else 0.0),
                "confidence": (q.get("confidence") if q else "low"),
                "missing_components": (q.get("missing_components") if q else []),
                "unexpected_components": (q.get("unexpected_components") if q else []),
                "decision": decision,
                "reason": reason,
                "recommended_components": rec_components[:3],
                "recommended_enhancement_candidate_id": (enh_by_day.get(d, {}).get("recommended_candidate_id") if has_enh else None),
                "recommended_fallback_tier": (fallback_by_day.get(d, {}).get("suggested_complexity_tier") if has_fb else None),
            }
        )

    mix = decide_mix(tier_perf)

    missing_hotspots = {}
    for t in ("small", "medium", "large"):
        c = tier_missing_components.get(t, Counter())
        missing_hotspots[t] = [f"{name}:{count}" for name, count in c.most_common(5)]

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "batch_summary": {
            "days_considered": day_keys,
            "success_count": success_count,
            "failure_count": failure_count,
            "quality_reports_count": len(quality_files),
            "enhancement_candidates_count": len(enh_files),
            "fallback_plans_count": len(fallback_files),
        },
        "tier_performance": tier_perf,
        "source_health": {
            "top_sources": [x[0] for x in top_sources.most_common(5)],
            "blocked_domains": [x[0] for x in blocked_domains.most_common(5)],
            "successful_domains": [x[0] for x in successful_domains.most_common(5)],
        },
        "theme_and_action_bias": {
            "top_genres": [x[0] for x in genre_counter.most_common(5)],
            "top_core_actions": [x[0] for x in action_counter.most_common(5)],
            "duplicate_patterns": [x[0] for x in twist_counter.items() if x[1] >= 2][:5],
        },
        "improvement_signals": {
            "top_twist_candidates": (comp.get("twist_candidates") or [])[:3],
            "common_patterns": (comp.get("common_patterns") or [])[:5],
            "dont_copy": (comp.get("dont_copy") or [])[:5],
            "missing_components_hotspots": missing_hotspots,
            "portfolio_hotspots": (portfolio.get("portfolio_hotspots") or [])[:5],
            "growth_hotspots": (growth.get("growth_hotspots") or [])[:5],
            "strategy_primary_modes": ((strategy.get("summary") or {}).get("primary_modes") or [])[:5],
            "strategy_avoidance_modes": ((strategy.get("summary") or {}).get("avoidance_modes") or [])[:5],
            "evidence_hotspots": (evidence.get("portfolio_relevant_findings") or [])[:5],
            "reality_hotspots": (reality.get("release_hotspots") or [])[:5],
        },
        "day_decisions": day_decisions,
        "next_batch_recommendations": {
            "recommended_tier_mix": mix,
            "recommended_component_bias": (comp.get("twist_candidates") or [])[:2],
            "recommended_source_bias": [x[0] for x in successful_domains.most_common(3)],
            "recommended_showcase_slot": int(showcase.get("selected_showcase_slot", 0) or 0),
            "recommended_showcase_goal": ((showcase.get("selected_showcase_plan") or {}).get("showcase_goal", "")),
            "recommended_focus": [
                "bias away from duplicated twist patterns",
                "prioritize domains with successful extraction",
                "prefer enhancement/upgrade candidates before aggressive complexity",
                "improve README above-the-fold clarity",
                "reduce broken or missing live demo links",
                "strengthen showcase-ready presentation for standout tools",
                "improve one-line positioning for portfolio browsing",
                "strengthen one-line positioning for audience-facing messaging",
                "improve showcase launch narrative before weekly release",
                "align README and demo clarity with social hooks",
                "generate more distinct audience-facing value propositions",
                "reinforce instant-use clarity as strategic default",
                "reduce over-complex novelty bets unless portfolio impact is explicit",
                "bias showcase toward portfolio-visible impact",
                "align component selection with strategic thesis",
                "improve above-the-fold clarity",
                "reduce release-hold visual issues",
                "improve CTA discoverability",
                "strengthen showcase-visible first impression",
                "avoid shipping unclear demos",
            ],
        },
    }

    out_dir = os.path.join(cdir, "reports", "control_tower")
    os.makedirs(out_dir, exist_ok=True)
    out_json = os.path.join(out_dir, f"weekly_control_tower_{args.date}.json")
    out_md = os.path.join(out_dir, f"weekly_control_tower_{args.date}.md")

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    lines = []
    lines.append(f"# Weekly Control Tower ({args.date})")
    lines.append("")
    lines.append("## 今週の要約")
    lines.append(f"- success/failure: {success_count}/{failure_count}")
    lines.append(f"- quality reports: {len(quality_files)}")
    lines.append(f"- enhancement candidates: {len(enh_files)}")
    lines.append(f"- fallback plans: {len(fallback_files)}")
    lines.append("")
    lines.append("## tier別成績")
    for t in ("small", "medium", "large"):
        tp = tier_perf[t]
        lines.append(
            f"- {t}: count={tp['count']}, avg_score={tp['avg_score']}, "
            f"fallback_count={tp['fallback_count']}, confidence={tp.get('confidence_distribution', {})}"
        )
    lines.append("")
    lines.append("## blockedが多いドメイン")
    if blocked_domains:
        for d, c in blocked_domains.most_common(5):
            lines.append(f"- {d}: {c}")
    else:
        lines.append("- なし")
    lines.append("")
    lines.append("## よく効いた competitor patterns")
    cps = (comp.get("common_patterns") or [])[:5]
    if cps:
        for p in cps:
            lines.append(f"- {p}")
    else:
        lines.append("- なし")
    lines.append("")
    lines.append("## 失敗の多い構成")
    bad = [t for t, v in tier_perf.items() if v.get("fallback_count", 0) > 0]
    lines.append(f"- {', '.join(bad) if bad else '明確な偏りなし'}")
    lines.append("")
    lines.append("## missing components hotspot")
    for t in ("small", "medium", "large"):
        hs = payload["improvement_signals"]["missing_components_hotspots"].get(t, [])
        lines.append(f"- {t}: {', '.join(hs) if hs else 'なし'}")
    lines.append("")
    lines.append("## portfolio hotspots")
    ph = payload["improvement_signals"].get("portfolio_hotspots", [])
    if ph:
        for x in ph:
            lines.append(f"- {x}")
    else:
        lines.append("- なし")
    lines.append("")
    lines.append("## growth hotspots")
    gh = payload["improvement_signals"].get("growth_hotspots", [])
    if gh:
        for x in gh:
            lines.append(f"- {x}")
    else:
        lines.append("- なし")
    lines.append("")
    lines.append("## strategy signals")
    sp = payload["improvement_signals"].get("strategy_primary_modes", [])
    sa = payload["improvement_signals"].get("strategy_avoidance_modes", [])
    lines.append(f"- primary_modes: {', '.join(sp) if sp else 'なし'}")
    lines.append(f"- avoidance_modes: {', '.join(sa) if sa else 'なし'}")
    lines.append("")
    lines.append("## evidence/reality hotspots")
    eh = payload["improvement_signals"].get("evidence_hotspots", [])
    rh = payload["improvement_signals"].get("reality_hotspots", [])
    lines.append(f"- evidence: {', '.join(eh) if eh else 'なし'}")
    lines.append(f"- reality: {', '.join(rh) if rh else 'なし'}")
    lines.append("")
    lines.append("## dayごとの decision summary")
    for dd in day_decisions[-10:]:
        lines.append(
            f"- Day{dd['day']}: {dd['decision']} "
            f"(tier={dd['complexity_tier']}, score={dd['quality_score']}, confidence={dd.get('confidence', 'low')}) "
            f"/ {dd['reason']}"
        )
    lines.append("")
    lines.append("## 次の7本への推奨")
    lines.append(f"- tier mix: small={mix['small']}, medium={mix['medium']}, large={mix['large']}")
    if payload["next_batch_recommendations"].get("recommended_showcase_slot", 0):
        lines.append(
            f"- showcase slot: {payload['next_batch_recommendations']['recommended_showcase_slot']} / "
            f"{payload['next_batch_recommendations'].get('recommended_showcase_goal', '')}"
        )
    for r in payload["next_batch_recommendations"]["recommended_focus"]:
        lines.append(f"- {r}")
    lines.append("")
    lines.append("## Context sources")
    for p in [signals_path, coverage_path, latest_comp, latest_showcase, latest_portfolio, latest_growth, latest_strategy, latest_evidence, latest_reality, memory_path, feedback_path, sources_path]:
        if p and os.path.exists(p):
            lines.append(f"- {os.path.relpath(p, cdir)}")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[build_control_tower_digest] wrote: {os.path.relpath(out_md, cdir)}")
    print(f"[build_control_tower_digest] wrote: {os.path.relpath(out_json, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
