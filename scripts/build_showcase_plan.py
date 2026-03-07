#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import date, datetime, timezone


# Deterministic weighted average for showcase scoring.
# total = novelty*0.2 + showcase_potential*0.25 + implementation_risk*0.2
#       + component_fit*0.15 + competitor_signal_strength*0.1 + quality_confidence*0.1
WEIGHTS = {
    "novelty": 0.2,
    "showcase_potential": 0.25,
    "implementation_risk": 0.2,
    "component_fit": 0.15,
    "competitor_signal_strength": 0.1,
    "quality_confidence": 0.1,
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


def to_rel(path, cdir):
    if not path:
        return ""
    try:
        return os.path.relpath(path, cdir)
    except Exception:
        return path


def clamp(x):
    if x < 0.0:
        return 0.0
    if x > 1.0:
        return 1.0
    return round(float(x), 3)


def confidence_to_score(value: str) -> float:
    if value == "high":
        return 0.9
    if value == "medium":
        return 0.65
    if value == "low":
        return 0.4
    return 0.5


def load_quality_stats(cdir):
    out = {"small": {"scores": [], "conf": []}, "medium": {"scores": [], "conf": []}, "large": {"scores": [], "conf": []}}
    files = sorted(glob.glob(os.path.join(cdir, "reports", "quality", "day*_quality.json")))

    for p in files:
        try:
            q = read_json(p)
        except Exception:
            continue

        tier = q.get("complexity_tier", "small")
        if tier not in out:
            continue

        s = q.get("tier_expectation_score")
        if isinstance(s, (int, float)):
            out[tier]["scores"].append(float(s))

        conf = q.get("confidence")
        if isinstance(conf, str):
            out[tier]["conf"].append(confidence_to_score(conf))

    return out


def avg(vals, default=0.0):
    if not vals:
        return default
    return sum(vals) / len(vals)


def load_fallback_pressure(cdir):
    by_tier = {"small": 0, "medium": 0, "large": 0}
    files = sorted(glob.glob(os.path.join(cdir, "plans", "candidates", "day*_fallback_plan.json")))
    for p in files:
        try:
            x = read_json(p)
        except Exception:
            continue
        tier = x.get("original_complexity_tier", "")
        if tier in by_tier:
            by_tier[tier] += 1

    return {k: min(1.0, v / 3.0) for k, v in by_tier.items()}


def load_competitor_signals(cdir):
    path = latest_file(os.path.join(cdir, "reports", "competitors", "competitor_scan_*_shortlist.json"))
    if not path:
        return {}, ""

    try:
        data = read_json(path)
    except Exception:
        return {}, path

    success_target = int(data.get("success_target", 3) or 3)
    success_count = int(data.get("success_count", 0) or 0)
    blocked_count = int(data.get("blocked_count", 0) or 0)
    failed_count = int(data.get("failed_count", 0) or 0)
    considered = int(data.get("candidates_considered", 0) or 0)

    common_patterns = data.get("common_patterns", []) if isinstance(data.get("common_patterns", []), list) else []
    twist_candidates = data.get("twist_candidates", []) if isinstance(data.get("twist_candidates", []), list) else []

    blocked_ratio = (blocked_count / max(considered, 1)) if considered > 0 else 0.0
    success_ratio = success_count / max(success_target, 1)
    pattern_strength = min(1.0, (len(common_patterns) + len(twist_candidates)) / 8.0)

    return {
        "path": path,
        "success_ratio": clamp(success_ratio),
        "pattern_strength": clamp(pattern_strength),
        "blocked_ratio": clamp(blocked_ratio),
        "common_patterns": common_patterns,
        "twist_candidates": twist_candidates,
    }, path


def load_control_tower(cdir):
    path = latest_file(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))
    if not path:
        return {}, ""

    try:
        return read_json(path), path
    except Exception:
        return {}, path


def load_state_meta(cdir):
    state_path = os.path.join(cdir, "STATE.json")
    if not os.path.exists(state_path):
        return {}

    try:
        return read_json(state_path)
    except Exception:
        return {}


def build_slot_scores(slot_item, ctx):
    tier = slot_item.get("recommended_complexity_tier", "small")
    rec_components = slot_item.get("recommended_components", []) if isinstance(slot_item.get("recommended_components", []), list) else []

    # novelty
    base_novelty = {"small": 0.45, "medium": 0.65, "large": 0.8}.get(tier, 0.45)
    slot_num = int(slot_item.get("slot", 0) or 0)
    slot_bonus = 0.04 if slot_num >= 5 else 0.0
    duplicate_penalty = 0.05 if ctx.get("has_duplicate_pattern", False) else 0.0
    component_variety = min(0.15, (len(set(rec_components)) / 4.0) * 0.15)
    novelty = clamp(base_novelty + slot_bonus + component_variety - duplicate_penalty)

    # showcase potential
    showcase_weights = {
        "comparison_view": 0.35,
        "reason_panel": 0.2,
        "sample_inputs": 0.15,
        "history_panel": 0.15,
        "export_suite": 0.1,
        "step_ui": 0.08,
        "local_storage": 0.05,
    }
    showcase_potential = sum(showcase_weights.get(c, 0.0) for c in rec_components)
    showcase_potential += {"small": 0.0, "medium": 0.1, "large": 0.2}.get(tier, 0.0)
    showcase_potential = clamp(showcase_potential)

    # implementation risk (higher is safer)
    base_risk = {"small": 0.9, "medium": 0.72, "large": 0.5}.get(tier, 0.72)
    fallback_pressure = ctx.get("fallback_pressure", {}).get(tier, 0.0)
    blocked_ratio = ctx.get("competitor", {}).get("blocked_ratio", 0.0)
    implementation_risk = clamp(base_risk - (0.25 * fallback_pressure) - (0.2 * blocked_ratio))

    # component fit
    preferred = ctx.get("preferred_by_tier", {}).get(tier, [])
    if rec_components:
        overlap = len([c for c in rec_components if c in preferred])
        component_fit = clamp(overlap / len(rec_components))
    else:
        component_fit = 0.5

    # competitor signal strength
    comp = ctx.get("competitor", {})
    competitor_signal_strength = clamp((comp.get("success_ratio", 0.0) * 0.55) + (comp.get("pattern_strength", 0.0) * 0.45))

    # quality confidence
    qs = ctx.get("quality_stats", {}).get(tier, {})
    q_score = avg(qs.get("scores", []), 0.55)
    q_conf = avg(qs.get("conf", []), 0.55)
    quality_confidence = clamp((q_score * 0.7) + (q_conf * 0.3))

    total = (
        novelty * WEIGHTS["novelty"]
        + showcase_potential * WEIGHTS["showcase_potential"]
        + implementation_risk * WEIGHTS["implementation_risk"]
        + component_fit * WEIGHTS["component_fit"]
        + competitor_signal_strength * WEIGHTS["competitor_signal_strength"]
        + quality_confidence * WEIGHTS["quality_confidence"]
    )

    scores = {
        "novelty": clamp(novelty),
        "showcase_potential": clamp(showcase_potential),
        "implementation_risk": clamp(implementation_risk),
        "component_fit": clamp(component_fit),
        "competitor_signal_strength": clamp(competitor_signal_strength),
        "quality_confidence": clamp(quality_confidence),
        "total": clamp(total),
    }

    reasons = [
        f"tier={tier}, components={', '.join(rec_components) if rec_components else 'none'}",
        f"showcase_potential={scores['showcase_potential']}, implementation_risk={scores['implementation_risk']}",
        f"competitor_signal_strength={scores['competitor_signal_strength']}, quality_confidence={scores['quality_confidence']}",
    ]

    return scores, reasons


def choose_target_tier(slot_item, scores):
    rec_tier = slot_item.get("recommended_complexity_tier", "small")
    if rec_tier == "large":
        return "large"

    if rec_tier == "medium":
        if scores["implementation_risk"] >= 0.62 and scores["quality_confidence"] >= 0.58:
            return "large"
        return "medium"

    if scores["implementation_risk"] >= 0.55 and scores["showcase_potential"] >= 0.45:
        return "medium"
    return "small"


def fallback_tier(tier):
    if tier == "large":
        return "medium"
    if tier == "medium":
        return "small"
    return "small"


def build_component_bias(slot_item, target_tier):
    rec_components = slot_item.get("recommended_components", []) if isinstance(slot_item.get("recommended_components", []), list) else []
    if target_tier == "large":
        order = ["comparison_view", "reason_panel", "sample_inputs", "history_panel", "export_suite", "step_ui", "local_storage"]
    elif target_tier == "medium":
        order = ["reason_panel", "sample_inputs", "comparison_view", "history_panel", "local_storage", "step_ui"]
    else:
        order = ["reason_panel", "sample_inputs", "local_storage"]

    out = []
    for c in order:
        if c in rec_components and c not in out:
            out.append(c)
    for c in order:
        if c not in out:
            out.append(c)
        if len(out) >= 3:
            break
    return out[:3]


def annotate_next_batch_plan(plan, showcase_payload):
    selected_slot = int(showcase_payload.get("selected_showcase_slot", 0) or 0)
    selected = showcase_payload.get("selected_showcase_plan", {}) or {}
    candidate_map = {}
    for c in showcase_payload.get("candidate_slots", []):
        slot = int(c.get("slot", 0) or 0)
        candidate_map[slot] = c

    plan["showcase_slot"] = selected_slot
    plan["showcase_goal"] = selected.get("showcase_goal", "")
    plan["showcase_component_bias"] = selected.get("component_bias", [])
    plan["showcase_adopt_competitor_enhancement"] = bool(selected.get("adopt_competitor_enhancement", False))
    plan["showcase_fallback_tier"] = selected.get("fallback_tier_if_needed", "")

    days = plan.get("days", []) if isinstance(plan.get("days", []), list) else []
    for d in days:
        slot = int(d.get("slot", 0) or 0)
        cand = candidate_map.get(slot)
        d["is_showcase_candidate"] = bool(cand)
        d["is_selected_showcase"] = (slot == selected_slot)
        if cand:
            d["showcase_score"] = cand.get("scores", {}).get("total", 0.0)

    return plan


def write_markdown(path, payload):
    lines = []
    lines.append(f"# Showcase Plan ({payload.get('date', '')})")
    lines.append("")
    lines.append("## 今週の見せ玉候補一覧")
    for c in payload.get("candidate_slots", []):
        lines.append(
            f"- slot {c['slot']} (tier={c['recommended_complexity_tier']}, score={c['scores']['total']}): "
            f"components={', '.join(c.get('recommended_components', [])) or 'none'}"
        )
    lines.append("")
    lines.append("## 各候補の採点理由")
    for c in payload.get("candidate_slots", []):
        lines.append(f"### slot {c['slot']}")
        s = c["scores"]
        lines.append(
            f"- scores: novelty={s['novelty']}, showcase_potential={s['showcase_potential']}, "
            f"implementation_risk={s['implementation_risk']}, component_fit={s['component_fit']}, "
            f"competitor_signal_strength={s['competitor_signal_strength']}, quality_confidence={s['quality_confidence']}, total={s['total']}"
        )
        for r in c.get("reason", []):
            lines.append(f"- {r}")
    lines.append("")

    selected_slot = payload.get("selected_showcase_slot", 0)
    selected = payload.get("selected_showcase_plan", {}) or {}

    lines.append("## 選定された showcase slot")
    lines.append(f"- slot: {selected_slot}")
    lines.append("")
    lines.append("## その1本に推奨する構成")
    lines.append(f"- target tier: {selected.get('target_tier', 'medium')}")
    lines.append(f"- component bias: {', '.join(selected.get('component_bias', [])) or 'none'}")
    lines.append(f"- adopt competitor enhancement: {selected.get('adopt_competitor_enhancement', False)}")
    lines.append(f"- goal: {selected.get('showcase_goal', '')}")
    lines.append("")
    lines.append("## なぜ他のスロットではないのか")
    lines.append("- total score が最も高いスロットを採用（同点時は showcase_potential -> implementation_risk の順で比較）。")
    lines.append("- quality/fallback/blocked signal を加味し、映えと実装安定性のバランスを優先。")
    lines.append("")
    lines.append("## fallback 方針")
    lines.append(f"- fallback_tier_if_needed: {selected.get('fallback_tier_if_needed', 'medium')}")
    lines.append("- 自動再試行は行わず、quality report / fallback plan / showcase plan を見て人手判断する。")

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Build showcase planner for next 7-day strategy")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    parser.add_argument("--plan", default="")
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    plan_path = args.plan or os.path.join(cdir, "plans", "next_batch_plan.json")
    if not os.path.exists(plan_path):
        print("[build_showcase_plan] next_batch_plan not found; skip")
        return 0

    try:
        plan = read_json(plan_path)
    except Exception as e:
        print(f"[build_showcase_plan] failed to read next_batch_plan: {e}; skip")
        return 0

    days = plan.get("days", []) if isinstance(plan.get("days", []), list) else []
    if not days:
        print("[build_showcase_plan] plan days are empty; skip")
        return 0

    tower, tower_path = load_control_tower(cdir)
    comp, comp_path = load_competitor_signals(cdir)
    quality_stats = load_quality_stats(cdir)
    fallback_pressure = load_fallback_pressure(cdir)
    state = load_state_meta(cdir)

    profiles_path = os.path.join(cdir, "system", "complexity_profiles.json")
    profiles = read_json(profiles_path) if os.path.exists(profiles_path) else {}
    preferred_by_tier = {
        "small": (profiles.get("small", {}) or {}).get("preferred_components", []),
        "medium": (profiles.get("medium", {}) or {}).get("preferred_components", []),
        "large": (profiles.get("large", {}) or {}).get("preferred_components", []),
    }

    duplicate_patterns = ((tower.get("theme_and_action_bias", {}) or {}).get("duplicate_patterns", [])) if tower else []

    thesis_path = os.path.join(cdir, "shared-context", "THESIS.md")
    sources_path = os.path.join(cdir, "shared-context", "SOURCES.md")

    ctx = {
        "quality_stats": quality_stats,
        "fallback_pressure": fallback_pressure,
        "competitor": comp,
        "preferred_by_tier": preferred_by_tier,
        "has_duplicate_pattern": len(duplicate_patterns) > 0,
        "state": state,
    }

    candidate_slots = []
    for item in days:
        scores, reasons = build_slot_scores(item, ctx)
        candidate_slots.append(
            {
                "slot": int(item.get("slot", 0) or 0),
                "recommended_complexity_tier": item.get("recommended_complexity_tier", "small"),
                "recommended_components": item.get("recommended_components", []) if isinstance(item.get("recommended_components", []), list) else [],
                "adopt_competitor_enhancement": bool(item.get("adopt_competitor_enhancement", False)),
                "scores": scores,
                "reason": reasons,
            }
        )

    candidate_slots = sorted(
        candidate_slots,
        key=lambda x: (x["scores"]["total"], x["scores"]["showcase_potential"], x["scores"]["implementation_risk"], -x["slot"]),
        reverse=True,
    )

    selected = candidate_slots[0]
    selected_slot = selected["slot"]
    target_tier = choose_target_tier(selected, selected["scores"])
    component_bias = build_component_bias(selected, target_tier)
    adopt_comp_enh = bool(selected["scores"]["competitor_signal_strength"] >= 0.55 and target_tier != "small")

    selected_showcase_plan = {
        "slot": selected_slot,
        "target_tier": target_tier,
        "component_bias": component_bias,
        "adopt_competitor_enhancement": adopt_comp_enh,
        "showcase_goal": "見た目と差分訴求が強い1本にする",
        "fallback_tier_if_needed": fallback_tier(target_tier),
    }

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "date": args.date,
        "source_control_tower": to_rel(tower_path, cdir),
        "source_next_batch_plan": to_rel(plan_path, cdir),
        "source_competitor_scan": to_rel(comp_path, cdir),
        "source_thesis": to_rel(thesis_path, cdir) if os.path.exists(thesis_path) else "",
        "source_sources": to_rel(sources_path, cdir) if os.path.exists(sources_path) else "",
        "candidate_slots": candidate_slots,
        "selected_showcase_slot": selected_slot,
        "selected_showcase_plan": selected_showcase_plan,
    }

    # Reflect showcase recommendation into next_batch_plan (still advisory only).
    annotated = annotate_next_batch_plan(plan, payload)
    with open(plan_path, "w", encoding="utf-8") as f:
        json.dump(annotated, f, ensure_ascii=False, indent=2)

    out_dir = os.path.join(cdir, "reports", "showcase")
    os.makedirs(out_dir, exist_ok=True)
    out_json = os.path.join(out_dir, f"showcase_plan_{args.date}.json")
    out_md = os.path.join(out_dir, f"showcase_plan_{args.date}.md")

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    write_markdown(out_md, payload)

    # Compatibility output for existing planner references.
    compat_path = os.path.join(cdir, "plans", "showcase_plan.json")
    with open(compat_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"[build_showcase_plan] wrote: {to_rel(out_json, cdir)}")
    print(f"[build_showcase_plan] wrote: {to_rel(out_md, cdir)}")
    print(f"[build_showcase_plan] updated: {to_rel(plan_path, cdir)}")
    print(f"[build_showcase_plan] wrote: {to_rel(compat_path, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
