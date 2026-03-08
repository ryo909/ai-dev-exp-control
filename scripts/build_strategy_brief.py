#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
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


def take_list(obj, key, limit=5):
    val = obj.get(key, []) if isinstance(obj, dict) else []
    if isinstance(val, list):
        return [x for x in val if isinstance(x, str)][:limit]
    return []


def parse_thesis_focus(thesis_text):
    focus = []
    for line in thesis_text.splitlines():
        if line.strip().startswith("- 今週の重点:"):
            raw = line.split(":", 1)[1].strip()
            focus.extend([x.strip() for x in re.split(r"/|,|、", raw) if x.strip()])
        if line.strip().startswith("- 次の7本の狙う型:"):
            focus.append(line.split(":", 1)[1].strip())
    return focus[:6]


def build_decision_rules(showcase_slot, tier_mix, comp_patterns):
    rules = [
        "用途が一文で伝わらない案は showcase 候補にしない",
        "large は novelty より portfolio impact が明確な時だけ採用",
        "competitor enhancement は clarity を壊さない範囲でのみ採用",
        "README / demo / social hook が揃わない場合は先に導線改善を優先",
    ]
    if showcase_slot:
        rules.append(f"showcase slot {showcase_slot} は演出強化を許容し、他slotは安全実装を優先")
    if tier_mix:
        rules.append(f"推奨 tier mix ({tier_mix}) を逸脱する場合は根拠を残す")
    if comp_patterns:
        rules.append("競合の共通構成は参考にとどめ、言い回しの模倣は避ける")
    return rules[:8]


def main():
    parser = argparse.ArgumentParser(description="Build strategy brief for weekly framing")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)

    signals_path = os.path.join(cdir, "shared-context", "SIGNALS.md")
    shortlist_path = os.path.join(cdir, "idea_bank", "shortlist.json")
    weekly_prompt_path = os.path.join(cdir, "system", "prompts", "weekly_run.md")
    thesis_path = os.path.join(cdir, "shared-context", "THESIS.md")
    next_batch_path = os.path.join(cdir, "plans", "next_batch_plan.json")

    latest_comp_path = latest_file(os.path.join(cdir, "reports", "competitors", "competitor_scan_*_shortlist.json"))
    latest_tower_path = latest_file(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))
    latest_showcase_path = latest_file(os.path.join(cdir, "reports", "showcase", "showcase_plan_*.json"))
    latest_growth_path = latest_file(os.path.join(cdir, "reports", "growth", "growth_brief_*.json"))
    latest_portfolio_path = latest_file(os.path.join(cdir, "reports", "portfolio", "portfolio_eval_*.json"))

    signals_text = read_text(signals_path) if os.path.exists(signals_path) else ""
    shortlist = read_json(shortlist_path) if os.path.exists(shortlist_path) else {}
    weekly_prompt_text = read_text(weekly_prompt_path) if os.path.exists(weekly_prompt_path) else ""
    thesis_text = read_text(thesis_path) if os.path.exists(thesis_path) else ""
    next_batch = read_json(next_batch_path) if os.path.exists(next_batch_path) else {}

    comp = read_json(latest_comp_path) if latest_comp_path else {}
    tower = read_json(latest_tower_path) if latest_tower_path else {}
    showcase = read_json(latest_showcase_path) if latest_showcase_path else {}
    growth = read_json(latest_growth_path) if latest_growth_path else {}
    portfolio = read_json(latest_portfolio_path) if latest_portfolio_path else {}

    inputs_used = {
        "signals_used": bool(signals_text),
        "shortlist_used": bool(shortlist),
        "competitor_scan_used": bool(comp),
        "control_tower_used": bool(tower),
        "showcase_used": bool(showcase),
        "growth_used": bool(growth),
        "portfolio_used": bool(portfolio),
    }

    showcase_slot = None
    if isinstance(showcase, dict) and showcase.get("selected_showcase_slot"):
        try:
            showcase_slot = int(showcase.get("selected_showcase_slot"))
        except Exception:
            showcase_slot = None

    tier_mix = (tower.get("next_batch_recommendations", {}) or {}).get("recommended_tier_mix", {}) if isinstance(tower, dict) else {}
    next_days = next_batch.get("days", []) if isinstance(next_batch.get("days", []), list) else []
    competitor_patterns = take_list(comp, "common_patterns", limit=6)
    twist_candidates = take_list(comp, "twist_candidates", limit=6)
    growth_hotspots = take_list(growth, "growth_hotspots", limit=5)
    portfolio_hotspots = take_list(portfolio, "portfolio_hotspots", limit=5)
    thesis_focus = parse_thesis_focus(thesis_text)

    core_thesis = (
        "novelty 単体ではなく『一文で用途が伝わる即時価値 + 小さな驚き』を軸に、"
        "showcase 1本で差分訴求、残りは再現性重視で積み上げる"
    )

    winning_angles = [
        "小さくても即伝わる utility",
        "one-line clarity を先に固定",
        "showcase 1本の演出を明確化",
        "README / demo / social hook の一貫性",
        "medium中心で component を安全に増やす",
    ]
    if twist_candidates:
        winning_angles.append("competitor signal を流用しつつ差分 twist を明文化")

    deprioritized_angles = [
        "実装コストの高すぎる大型機能",
        "説明しないと伝わらない複雑演出",
        "競合フックの過度な模倣",
        "導線が弱いままの showcase 強行",
    ]

    risks_to_watch = [
        "novelty はあるが用途が不明な案が混ざる",
        "showcase 候補の README/demo clarity 不足",
        "component 追加で complexity が過負荷になる",
        "small 量産で portfolio で埋もれる",
    ]

    differentiation_axes = [
        "instant clarity vs lore depth",
        "utility vs gimmick",
        "portfolio fit vs one-off novelty",
        "replayability vs one-shot delight",
    ]

    showcase_rationale = []
    if isinstance(showcase, dict) and isinstance(showcase.get("selected_showcase_plan"), dict):
        goal = showcase.get("selected_showcase_plan", {}).get("showcase_goal", "")
        if goal:
            showcase_rationale.append(goal)
    if showcase_slot:
        showcase_rationale.append(f"slot {showcase_slot} を見せ玉として位置付ける")
    if not showcase_rationale:
        showcase_rationale.append("showcase_plan 未生成のため、次バッチの上位候補を暫定見せ玉として扱う")

    complexity_bias = []
    if tier_mix:
        complexity_bias.append(f"tier mix target: small={tier_mix.get('small', 0)}, medium={tier_mix.get('medium', 0)}, large={tier_mix.get('large', 0)}")
    else:
        complexity_bias.append("tier mix は small/medium 中心を維持")

    component_bias = []
    if isinstance(next_days, list) and next_days:
        comp_counter = {}
        for item in next_days:
            for c in item.get("recommended_components", []) if isinstance(item.get("recommended_components", []), list) else []:
                comp_counter[c] = comp_counter.get(c, 0) + 1
        for k, _ in sorted(comp_counter.items(), key=lambda kv: kv[1], reverse=True)[:4]:
            component_bias.append(k)
    if not component_bias:
        component_bias = ["reason_panel", "sample_inputs", "local_storage"]

    enhancement_bias = [
        "competitor enhancement は clarity を維持できる slot に限定",
        "showcase slot でのみ aggressive enhancement を検討",
    ]

    fallback_posture = [
        "showcase は large失敗時に medium へ段階fallback",
        "missing component が多い場合は同tier再試行より先に構成を削る",
    ]

    batch_guidance = {
        "recommended_biases": [
            "clarity first",
            "showcase one + safe six",
            "portfolio-visible outcomes",
        ],
        "complexity_bias": complexity_bias,
        "component_bias": component_bias,
        "enhancement_bias": enhancement_bias,
        "fallback_posture": fallback_posture,
        "portfolio_implications": portfolio_hotspots[:3] or ["README/demo導線を先に整える"],
        "growth_implications": growth_hotspots[:3] or ["one-line positioning を先に固定"],
    }

    slot_recommendations = []
    if next_days:
        for item in next_days:
            slot = item.get("slot")
            tier = item.get("recommended_complexity_tier", "small")
            comps = item.get("recommended_components", []) if isinstance(item.get("recommended_components", []), list) else []
            conf = 0.62
            conf += 0.08 if inputs_used["control_tower_used"] else 0.0
            conf += 0.08 if inputs_used["competitor_scan_used"] else 0.0
            conf += 0.06 if inputs_used["showcase_used"] else 0.0
            conf = clamp(conf)
            slot_recommendations.append(
                {
                    "slot": f"Slot{slot}",
                    "recommended_direction": f"{tier} で {'/'.join(comps) if comps else 'safe components'} を活かし、用途の即時伝達を優先",
                    "why": [
                        "next_batch_plan の complexity/components 推奨に整合",
                        "戦略軸を clarity-first に固定",
                    ],
                    "do_more_of": ["one_sentence の便益明確化", "README 冒頭の demo 導線"],
                    "avoid": ["説明前提の複雑演出", "用途が曖昧な twist"],
                    "confidence": conf,
                }
            )
    else:
        for idx in range(1, 8):
            slot_recommendations.append(
                {
                    "slot": f"Slot{idx}",
                    "recommended_direction": "small/medium中心で即時価値を優先",
                    "why": ["入力不足のため安全側に推奨"],
                    "do_more_of": ["one-line clarity"],
                    "avoid": ["過度な実装拡張"],
                    "confidence": 0.45,
                }
            )

    thesis_candidates = [
        {
            "label": "clarity-first",
            "candidate_text": "今週は『一文で用途が伝わる即時価値』を最優先にし、showcase 1本で差分訴求、残りは再現性重視で回す。",
            "why": ["growth/portfolio に共通する改善軸", "next_batch の安全運用と両立"],
            "confidence": clamp(0.7 + (0.1 if inputs_used["control_tower_used"] else 0.0)),
        },
        {
            "label": "showcase-discipline",
            "candidate_text": "showcase は目立つ演出よりも『使いどころの即時理解 + demo導線』を満たす案だけ採用する。",
            "why": ["portfolio/growth観点で効果が高い", "失敗時のfallback判断が容易"],
            "confidence": clamp(0.66 + (0.1 if inputs_used["showcase_used"] else 0.0)),
        },
        {
            "label": "component-safety",
            "candidate_text": "component追加は medium帯で段階導入し、missing signal が出た部品は翌週に再評価する。",
            "why": ["quality/fallback の既存ループと整合"],
            "confidence": clamp(0.64 + (0.1 if inputs_used["control_tower_used"] else 0.0)),
        },
    ]

    used_count = sum(1 for v in inputs_used.values() if v)
    strategic_confidence = clamp(0.4 + 0.08 * used_count)

    primary_modes = [
        "clarity-first utility",
        "showcase one + safe six",
        "portfolio-visible impact",
    ]
    avoidance_modes = [
        "over-complex novelty bets",
        "模倣色の強い competitor hook",
        "demo導線が弱いままの公開",
    ]

    key_thesis_shift = thesis_focus[:3]
    if not key_thesis_shift:
        key_thesis_shift = [
            "quality優先から clarity+distribution 優先へのシフト",
            "showcase の意味づけを明文化",
        ]

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "strategic_confidence": strategic_confidence,
            "primary_modes": primary_modes,
            "avoidance_modes": avoidance_modes,
            "showcase_slot": showcase_slot,
            "next_batch_bias": batch_guidance["recommended_biases"],
            "key_thesis_shift": key_thesis_shift,
        },
        "inputs_used": inputs_used,
        "strategic_direction": {
            "core_thesis": core_thesis,
            "why_now": [
                "quality/fallback は整ってきたため、次は勝ち筋の言語化がボトルネック",
                "showcase/growth/portfolio の判断が分散しており、統合フレーミングが必要",
            ],
            "winning_angles": winning_angles,
            "deprioritized_angles": deprioritized_angles,
            "risks_to_watch": risks_to_watch,
            "differentiation_axes": differentiation_axes,
            "showcase_rationale": showcase_rationale,
        },
        "batch_guidance": batch_guidance,
        "slot_recommendations": slot_recommendations,
        "thesis_candidates": thesis_candidates,
        "decision_rules": build_decision_rules(showcase_slot, tier_mix, competitor_patterns),
        "recommended_strategy_actions": [
            "THESIS 更新時に strategy_brief の thesis_candidates から1つ採用候補を選ぶ",
            "showcase slot は launch前に README/demo/hook を1セットで確認",
            "next_batch slot ごとに do_more_of/avoid を run_day 前にメタへ反映",
            "control_tower の recommended_focus と戦略文言の齟齬を週次で解消",
        ],
        "sources": [
            rel(signals_path if os.path.exists(signals_path) else "", cdir),
            rel(shortlist_path if os.path.exists(shortlist_path) else "", cdir),
            rel(latest_comp_path, cdir),
            rel(latest_tower_path, cdir),
            rel(latest_showcase_path, cdir),
            rel(next_batch_path if os.path.exists(next_batch_path) else "", cdir),
            rel(thesis_path if os.path.exists(thesis_path) else "", cdir),
            rel(weekly_prompt_path if os.path.exists(weekly_prompt_path) else "", cdir),
            rel(latest_growth_path, cdir),
            rel(latest_portfolio_path, cdir),
        ],
    }

    out_dir = os.path.join(cdir, "reports", "strategy")
    os.makedirs(out_dir, exist_ok=True)
    out_json = os.path.join(out_dir, f"strategy_brief_{args.date}.json")
    out_md = os.path.join(out_dir, f"strategy_brief_{args.date}.md")

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    lines = []
    lines.append(f"# Strategy Brief ({args.date})")
    lines.append("")
    lines.append("## 今週の勝ち筋総評")
    lines.append(f"- strategic_confidence: {strategic_confidence}")
    lines.append(f"- core_thesis: {core_thesis}")
    lines.append("")
    lines.append("## なぜその方向が有望か")
    for x in payload["strategic_direction"]["why_now"]:
        lines.append(f"- {x}")
    lines.append("")
    lines.append("## 避けるべき方向")
    for x in deprioritized_angles:
        lines.append(f"- {x}")
    lines.append("")
    lines.append("## showcase の意味づけ")
    for x in showcase_rationale:
        lines.append(f"- {x}")
    lines.append("")
    lines.append("## 次バッチへの示唆")
    for x in batch_guidance["recommended_biases"]:
        lines.append(f"- {x}")
    for x in batch_guidance["complexity_bias"]:
        lines.append(f"- {x}")
    lines.append("")
    lines.append("## THESIS に入れられそうな候補")
    for c in thesis_candidates:
        lines.append(f"- [{c['label']}] {c['candidate_text']} (confidence={c['confidence']})")
    lines.append("")
    lines.append("## 各 slot / day への短い方向性メモ")
    for s in slot_recommendations:
        lines.append(f"- {s['slot']}: {s['recommended_direction']} (confidence={s['confidence']})")
    lines.append("")
    lines.append("## すぐ効く戦略アクション")
    for x in payload["recommended_strategy_actions"]:
        lines.append(f"- {x}")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[build_strategy_brief] wrote: {rel(out_json, cdir)}")
    print(f"[build_strategy_brief] wrote: {rel(out_md, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
