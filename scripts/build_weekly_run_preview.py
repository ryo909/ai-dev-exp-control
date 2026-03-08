#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import date


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


def summarize(text: str) -> str:
    lines = [ln for ln in text.splitlines() if ln.strip()][:6]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build weekly_run preview")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    weekly_run = os.path.join(cdir, "system", "weekly_run.md")
    tower = latest(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))
    next_plan = os.path.join(cdir, "plans", "next_batch_plan.json")
    weekly_report = latest(os.path.join(cdir, "reports", "weekly", "weekly_run_report_*.json"))
    thesis = os.path.join(cdir, "shared-context", "THESIS.md")

    current = read_text(weekly_run) if os.path.exists(weekly_run) else "# Weekly Run\n"
    tower_json = read_json(tower) if tower and os.path.exists(tower) else {}
    next_json = read_json(next_plan) if os.path.exists(next_plan) else {}
    report_json = read_json(weekly_report) if weekly_report and os.path.exists(weekly_report) else {}

    mix = (tower_json.get("next_batch_recommendations") or {}).get("recommended_tier_mix", {"small": 4, "medium": 2, "large": 1})
    src_bias = (tower_json.get("next_batch_recommendations") or {}).get("recommended_source_bias", [])
    comp_bias = (tower_json.get("next_batch_recommendations") or {}).get("recommended_component_bias", [])
    showcase_slot = int(next_json.get("showcase_slot", 0) or 0)
    showcase_goal = next_json.get("showcase_goal", "") or ""
    showcase_fallback = next_json.get("showcase_fallback_tier", "") or ""
    showcase_enhancement = bool(next_json.get("showcase_adopt_competitor_enhancement", False))

    rec_profile = "safe"
    tp = tower_json.get("tier_performance", {})
    if tp.get("medium", {}).get("avg_score", 0) >= 0.7:
        rec_profile = "balanced"
    if tp.get("large", {}).get("avg_score", 0) >= 0.75 and tp.get("large", {}).get("fallback_count", 1) == 0:
        rec_profile = "aggressive"

    out = []
    out.append(f"# Weekly Run Preview ({args.date})")
    out.append("")
    out.append("## current weekly_run summary")
    out.append(summarize(current) or "(none)")
    out.append("")
    out.append("## 推奨 adoption profile")
    out.append(f"- {rec_profile}")
    out.append("")
    out.append("## 推奨 complexity mix")
    out.append(f"- small={mix.get('small', 4)} / medium={mix.get('medium', 2)} / large={mix.get('large', 1)}")
    out.append("")
    out.append("## 推奨 source bias")
    out.extend([f"- {s}" for s in src_bias[:5]] or ["- なし"])
    out.append("")
    out.append("## 推奨 component bias")
    out.extend([f"- {c}" for c in comp_bias[:5]] or ["- なし"])
    out.append("")
    out.append("## 今週の見せ玉スロット")
    if showcase_slot > 0:
        out.append(f"- slot {showcase_slot}: {showcase_goal or '見た目と差分訴求が強い1本'}")
        out.append(f"- showcaseだけ aggressive寄り運用候補: {'yes' if showcase_enhancement else 'no'}")
        out.append(f"- fallback_tier_if_needed: {showcase_fallback or 'medium'}")
    else:
        out.append("- なし")
    out.append("")
    out.append("## 今週の実行例コマンド")
    out.append("```bash")
    out.append(f"DRY_RUN=1 ADOPTION_PROFILE={rec_profile} STAGE=all bash scripts/weekly_orchestrator.sh")
    out.append(f"ADOPTION_PROFILE={rec_profile} STAGE=all bash scripts/weekly_orchestrator.sh")
    out.append("```")
    out.append("")
    out.append("## weekly_run に追記/置換すべき候補")
    out.append("### 今週の運用方針")
    out.append(f"- adoption profile: {rec_profile}")
    out.append(f"- tier mix: small={mix.get('small',4)} medium={mix.get('medium',2)} large={mix.get('large',1)}")
    if showcase_slot > 0:
        out.append(f"- showcase slot: {showcase_slot}（必要ならこの1本だけ aggressive 寄り）")
    out.append("- control_tower -> next_batch_plan -> thesis_update_draft -> weekly_run_report の順で確認")
    out.append("### 推奨コマンド例")
    out.append(f"- DRY_RUN=1 ADOPTION_PROFILE={rec_profile} STAGE=all bash scripts/weekly_orchestrator.sh")
    out.append(f"- ADOPTION_PROFILE={rec_profile} STAGE=all bash scripts/weekly_orchestrator.sh")

    out_path = os.path.join(cdir, "reports", "weekly", f"weekly_run_preview_{args.date}.md")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

    print(f"[build_weekly_run_preview] wrote: {os.path.relpath(out_path, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
