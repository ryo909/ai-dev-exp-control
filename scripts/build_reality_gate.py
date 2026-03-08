#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import date, datetime, timezone


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def rel(path, base):
    if not path:
        return ""
    try:
        return os.path.relpath(path, base)
    except Exception:
        return path


def latest(pattern):
    files = glob.glob(pattern)
    if not files:
        return ""
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def normalize_day(day):
    s = str(day)
    s = s.replace("Day", "")
    return s.zfill(3)


def main():
    parser = argparse.ArgumentParser(description="Build reality gate report")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)

    state_path = os.path.join(cdir, "STATE.json")
    state = read_json(state_path) if os.path.exists(state_path) else {}
    days = state.get("days", {}) if isinstance(state.get("days", {}), dict) else {}

    quality_files = sorted(glob.glob(os.path.join(cdir, "reports", "quality", "day*_quality.json")))
    quality_map = {}
    for p in quality_files:
        try:
            q = read_json(p)
            quality_map[normalize_day(q.get("day", ""))] = q
        except Exception:
            pass

    portfolio_path = latest(os.path.join(cdir, "reports", "portfolio", "portfolio_eval_*.json"))
    evidence_path = latest(os.path.join(cdir, "reports", "evidence", "evidence_*.json"))

    portfolio = read_json(portfolio_path) if portfolio_path else {}
    evidence = read_json(evidence_path) if evidence_path else {}

    port_map = {}
    for item in portfolio.get("by_day", []) if isinstance(portfolio.get("by_day", []), list) else []:
        port_map[normalize_day(item.get("day", ""))] = item

    ev_map = {}
    for item in evidence.get("by_day", []) if isinstance(evidence.get("by_day", []), list) else []:
        ev_map[normalize_day(item.get("day", ""))] = item

    by_day = []
    pass_count = 0
    pass_with_notes_count = 0
    hold_count = 0

    for day in sorted(days.keys()):
        d = normalize_day(day)
        entry = days.get(d, {}) if isinstance(days.get(d, {}), dict) else {}
        repo_name = entry.get("repo_name", f"ai-dev-day-{d}")

        q = quality_map.get(d, {})
        p = port_map.get(d, {})
        e = ev_map.get(d, {})

        score = q.get("tier_expectation_score", 0.0) if isinstance(q.get("tier_expectation_score", 0.0), (int, float)) else 0.0
        conf = q.get("confidence", "low") if isinstance(q.get("confidence", "low"), str) else "low"

        showstoppers = []
        non_blockers = []
        strengths = []

        if p:
            for issue in p.get("issues", [])[:6]:
                if "missing" in issue.lower() and "pages_url" in issue.lower():
                    showstoppers.append("pages_url missing")
                elif "invalid" in issue.lower() and "pages_url" in issue.lower():
                    showstoppers.append("pages_url invalid")
                else:
                    non_blockers.append(issue)
            for s in p.get("strengths", [])[:3]:
                strengths.append(s)

        if e:
            if e.get("capture_status") == "failed":
                non_blockers.append("visual evidence capture failed")
            if (e.get("above_the_fold_clarity", 0.0) or 0.0) < 0.4:
                showstoppers.append("above-the-fold clarity too low")
            elif (e.get("above_the_fold_clarity", 0.0) or 0.0) < 0.6:
                non_blockers.append("above-the-fold clarity is moderate")

            if (e.get("cta_visibility", 0.0) or 0.0) < 0.4:
                showstoppers.append("CTA visibility too low")
            elif (e.get("cta_visibility", 0.0) or 0.0) < 0.6:
                non_blockers.append("CTA visibility can be improved")

            for s in e.get("visual_strengths", [])[:2]:
                strengths.append(s)

        if q:
            missing = q.get("missing_components", []) if isinstance(q.get("missing_components", []), list) else []
            if score < 0.4:
                showstoppers.append("quality score is too low")
            elif score < 0.6:
                non_blockers.append("quality score is below target")
            if conf == "low":
                non_blockers.append("quality confidence is low")
            if len(missing) >= 3:
                non_blockers.append("multiple missing components detected")
        else:
            non_blockers.append("quality report is missing")

        if not p:
            non_blockers.append("portfolio evidence is missing")

        if not e:
            non_blockers.append("visual evidence is missing")

        decision = "PASS_WITH_NOTES"
        if showstoppers:
            decision = "HOLD"
            hold_count += 1
        elif non_blockers:
            decision = "PASS_WITH_NOTES"
            pass_with_notes_count += 1
        else:
            decision = "PASS"
            pass_count += 1

        recommended_actions = []
        if showstoppers:
            recommended_actions.append("showstoppers を優先修正して再判定")
        if non_blockers:
            recommended_actions.append("non-blocker を次バッチ改善に反映")
        if decision == "PASS":
            recommended_actions.append("現状方針を維持し、showcase候補を優先確認")

        rationale = [
            f"quality_score={round(float(score), 3)} confidence={conf}",
            f"showstoppers={len(showstoppers)} non_blockers={len(non_blockers)}",
            "reality gate は意思決定支援であり自動ブロックはしない",
        ]

        by_day.append(
            {
                "day": f"Day{d}",
                "repo_name": repo_name,
                "decision": decision,
                "showstoppers": sorted(set(showstoppers))[:7],
                "non_blockers": sorted(set(non_blockers))[:7],
                "strengths": sorted(set(strengths))[:5],
                "recommended_actions": recommended_actions[:4],
                "decision_rationale": rationale,
            }
        )

    release_hotspots = []
    hold_ct = sum(1 for x in by_day if x["decision"] == "HOLD")
    cta_ct = sum(1 for x in by_day if any("CTA" in y for y in x.get("showstoppers", []) + x.get("non_blockers", [])))
    clarity_ct = sum(1 for x in by_day if any("clarity" in y.lower() for y in x.get("showstoppers", []) + x.get("non_blockers", [])))
    if hold_ct:
        release_hotspots.append(f"{hold_ct} targets are in HOLD")
    if cta_ct:
        release_hotspots.append(f"CTA discoverability issues in {cta_ct} targets")
    if clarity_ct:
        release_hotspots.append(f"above-the-fold clarity issues in {clarity_ct} targets")

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "targets_considered": len(by_day),
            "pass_count": pass_count,
            "pass_with_notes_count": pass_with_notes_count,
            "hold_count": hold_count,
        },
        "by_day": by_day,
        "release_hotspots": release_hotspots,
        "recommended_gate_actions": [
            "improve above-the-fold clarity before release",
            "fix severe CTA visibility issues",
            "avoid shipping unclear demos",
            "use PASS_WITH_NOTES items as next-batch improvements",
        ],
        "quality_signal_sources": [
            rel(portfolio_path, cdir),
            rel(evidence_path, cdir),
            f"quality_reports:{len(quality_files)}",
            "STATE.json",
        ],
    }

    out_dir = os.path.join(cdir, "reports", "reality")
    os.makedirs(out_dir, exist_ok=True)
    out_json = os.path.join(out_dir, f"reality_gate_{args.date}.json")
    out_md = os.path.join(out_dir, f"reality_gate_{args.date}.md")

    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    lines = []
    lines.append(f"# Reality Gate ({args.date})")
    lines.append("")
    lines.append(f"- targets_considered: {payload['summary']['targets_considered']}")
    lines.append(f"- PASS/PASS_WITH_NOTES/HOLD: {pass_count}/{pass_with_notes_count}/{hold_count}")
    lines.append("")
    lines.append("## Release Hotspots")
    if release_hotspots:
        for x in release_hotspots:
            lines.append(f"- {x}")
    else:
        lines.append("- no major hotspot")
    lines.append("")
    lines.append("## By Day")
    for row in by_day:
        lines.append(f"### {row['day']} {row['repo_name']}")
        lines.append(f"- decision: {row['decision']}")
        if row["showstoppers"]:
            lines.append(f"- showstoppers: {', '.join(row['showstoppers'][:3])}")
        if row["non_blockers"]:
            lines.append(f"- non_blockers: {', '.join(row['non_blockers'][:3])}")
        if row["recommended_actions"]:
            lines.append(f"- next: {', '.join(row['recommended_actions'][:2])}")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[build_reality_gate] wrote: {rel(out_json, cdir)}")
    print(f"[build_reality_gate] wrote: {rel(out_md, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
