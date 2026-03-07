#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import date, datetime, timezone


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def read_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def latest(pattern: str):
    files = glob.glob(pattern)
    if not files:
        return None
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def rel(path: str, base: str) -> str:
    return os.path.relpath(path, base) if path else ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Build thesis update draft from control tower and weekly artifacts")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)

    tower_path = latest(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))
    weekly_digest_path = os.path.join(cdir, "reports", "weekly_digest.md")
    next_plan_path = os.path.join(cdir, "plans", "next_batch_plan.json")
    thesis_path = os.path.join(cdir, "shared-context", "THESIS.md")
    feedback_path = os.path.join(cdir, "shared-context", "FEEDBACK-LOG.md")
    memory_path = os.path.join(cdir, "memory", "MEMORY.md")

    tower = read_json(tower_path) if tower_path and os.path.exists(tower_path) else {}
    weekly_digest = read_text(weekly_digest_path) if os.path.exists(weekly_digest_path) else ""
    next_plan = read_json(next_plan_path) if os.path.exists(next_plan_path) else {}
    feedback = read_text(feedback_path) if os.path.exists(feedback_path) else ""
    memory = read_text(memory_path) if os.path.exists(memory_path) else ""

    bsum = tower.get("batch_summary", {})
    mix = (tower.get("next_batch_recommendations", {}) or {}).get("recommended_tier_mix", {"small": 4, "medium": 2, "large": 1})
    src_bias = (tower.get("next_batch_recommendations", {}) or {}).get("recommended_source_bias", [])
    comp_bias = (tower.get("next_batch_recommendations", {}) or {}).get("recommended_component_bias", [])
    focus = (tower.get("next_batch_recommendations", {}) or {}).get("recommended_focus", [])
    showcase_slot = int((next_plan.get("showcase_slot", 0) or 0))
    showcase_goal = (next_plan.get("showcase_goal", "") or "")
    showcase_bias = (next_plan.get("showcase_component_bias", []) or [])

    blocked = (tower.get("source_health", {}) or {}).get("blocked_domains", [])
    q_count = bsum.get("quality_reports_count", 0)
    fb_count = bsum.get("fallback_plans_count", 0)

    priorities = []
    if blocked:
      priorities.append("競合調査の blocked ドメイン回避を前提に source bias を調整する")
    if q_count == 0:
      priorities.append("quality report の生成率を上げ、tier成績で改善判断できる状態を先に作る")
    if fb_count > 0:
      priorities.append("fallback頻出ティアを抑え、medium中心の安定構成に寄せる")
    if not priorities:
      priorities = [
        "next_batch_plan の safe profile 採用率を上げ、複雑度注入を安定化する",
        "component bias に沿って再利用部品の実装密度を上げる",
      ]
    if showcase_slot > 0:
      priorities.append(
        f"見せ玉は slot {showcase_slot} を優先し、{showcase_goal or '差分訴求を強める方向'} を狙う"
      )

    dont_do = "UI演出の過剰な拡張に先に入らず、quality/fallbackの計測基盤が整うまで部品追加を段階運用する"

    lines = []
    lines.append(f"# THESIS Update Draft ({args.date})")
    lines.append("")
    lines.append("## 今週の要点")
    lines.append(f"- success/failure: {bsum.get('success_count', 0)}/{bsum.get('failure_count', 0)}")
    lines.append(f"- blocked domains: {', '.join(blocked) if blocked else 'なし'}")
    lines.append(f"- quality reports: {q_count}")
    lines.append(f"- fallback plans: {fb_count}")
    lines.append("")
    lines.append("## 次週の重点候補（1〜3）")
    for p in priorities[:3]:
      lines.append(f"- {p}")
    lines.append("")
    lines.append("## 推奨 complexity mix")
    lines.append(f"- small={mix.get('small', 4)} / medium={mix.get('medium', 2)} / large={mix.get('large', 1)}")
    lines.append("")
    lines.append("## 推奨 source bias")
    if src_bias:
      for s in src_bias[:5]:
        lines.append(f"- {s}")
    else:
      lines.append("- なし")
    lines.append("")
    lines.append("## 推奨 component bias")
    if comp_bias:
      for c in comp_bias[:5]:
        lines.append(f"- {c}")
    else:
      lines.append("- なし")
    if showcase_slot > 0:
      lines.append(f"- showcase(slot {showcase_slot}): {', '.join(showcase_bias) if showcase_bias else 'component bias未設定'}")
    lines.append("")
    lines.append("## 今週はやらないこと")
    lines.append(f"- {dont_do}")
    lines.append("")
    lines.append("## THESIS貼り付け用（短縮案）")
    lines.append(f"Updated: {args.date}")
    lines.append("- 今週の重点: quality report 生成率の安定化 / next_batch_plan safe採用の継続 / blocked回避のsource選定")
    lines.append(f"- 次の7本の狙う型: tier mix {mix.get('small', 4)}-{mix.get('medium', 2)}-{mix.get('large', 1)} で medium中心に部品追加を検証")
    lines.append(f"- 今週はやらないこと: {dont_do}")
    lines.append("")
    lines.append("## 参照元")
    for p in [tower_path, weekly_digest_path, next_plan_path, thesis_path, feedback_path, memory_path]:
      if p and os.path.exists(p):
        lines.append(f"- {rel(p, cdir)}")

    out_dir = os.path.join(cdir, "reports", "weekly")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"thesis_update_draft_{args.date}.md")
    with open(out_path, "w", encoding="utf-8") as f:
      f.write("\n".join(lines) + "\n")

    print(f"[build_thesis_update_draft] wrote: {rel(out_path, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
