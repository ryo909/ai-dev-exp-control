#!/usr/bin/env python3
import argparse
import glob
import json
import os
import re
from datetime import datetime, timezone

THRESHOLDS = {
    "small": 0.5,
    "medium": 0.6,
    "large": 0.7,
}

COMPONENT_PATTERNS = {
    "local_storage": [r"localStorage"],
    "history_panel": [r"history", r"履歴"],
    "comparison_view": [r"compare", r"comparison", r"比較"],
    "export_suite": [r"download", r"blob", r"toDataURL", r"export", r"エクスポート"],
    "reason_panel": [r"reason", r"why", r"根拠", r"理由"],
    "sample_inputs": [r"sample", r"example", r"preset", r"入力例", r"サンプル"],
    "step_ui": [r"step", r"wizard", r"progress", r"ステップ", r"進行"],
}


def ensure_day(day: str) -> str:
    return str(day).replace("Day", "").zfill(3)


def load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def to_rel(path: str, base: str) -> str:
    try:
        return os.path.relpath(path, base)
    except Exception:
        return path


def find_repo_path(control_dir: str, repo_name: str, explicit: str = "") -> str | None:
    if explicit and os.path.isdir(explicit):
        return explicit

    work_root = os.path.abspath(os.path.join(control_dir, "..", ".workdays"))
    if not os.path.isdir(work_root):
        return None

    pattern = os.path.join(work_root, f"{repo_name}-*")
    cands = [p for p in glob.glob(pattern) if os.path.isdir(p)]
    if not cands:
        return None
    cands.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return cands[0]


def collect_text(repo_path: str) -> str:
    targets = []
    for rel in ["README.md", "STORY.md", "meta.json", "package.json", "index.html"]:
        p = os.path.join(repo_path, rel)
        if os.path.isfile(p):
            targets.append(p)

    src_dir = os.path.join(repo_path, "src")
    if os.path.isdir(src_dir):
        for ext in ["*.js", "*.jsx", "*.ts", "*.tsx", "*.json", "*.html", "*.css", "*.md"]:
            targets.extend(glob.glob(os.path.join(src_dir, "**", ext), recursive=True))

    blobs = []
    for p in targets[:300]:
        try:
            with open(p, "r", encoding="utf-8", errors="ignore") as f:
                blobs.append(f.read(120_000))
        except Exception:
            pass
    return "\n".join(blobs)


def detect_components(text: str) -> tuple[list[str], list[str]]:
    detected = []
    notes = []
    for comp, patterns in COMPONENT_PATTERNS.items():
        for pat in patterns:
            if re.search(pat, text, flags=re.IGNORECASE):
                detected.append(comp)
                notes.append(f"{comp} signal detected by pattern: {pat}")
                break
    return sorted(set(detected)), notes


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate generated day repo quality by complexity tier heuristics")
    parser.add_argument("--day", required=True)
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--repo-path", default="")
    parser.add_argument("--state-file", default="")
    args = parser.parse_args()

    control_dir = os.path.abspath(args.control_dir)
    state_path = args.state_file or os.path.join(control_dir, "STATE.json")
    if not os.path.exists(state_path):
        print("[evaluate_build_quality] STATE.json missing; skip")
        return 0

    state = load_json(state_path)
    day = ensure_day(args.day)
    day_entry = ((state.get("days") or {}).get(day) or {})
    meta = day_entry.get("meta") or {}

    tier = meta.get("complexity_tier", "small")
    selected = meta.get("selected_components") or []
    if not isinstance(selected, list):
        selected = []

    repo_name = day_entry.get("repo_name", f"ai-dev-day-{day}")
    repo_path = find_repo_path(control_dir, repo_name, args.repo_path)
    notes = []

    if not repo_path:
        notes.append("repo path not found in .workdays")
        detected = []
    else:
        text = collect_text(repo_path)
        detected, detect_notes = detect_components(text)
        notes.extend(detect_notes)

    selected_set = sorted(set([x for x in selected if isinstance(x, str)]))
    detected_set = sorted(set(detected))
    missing = sorted([c for c in selected_set if c not in detected_set])

    if selected_set:
        score = round((len(selected_set) - len(missing)) / len(selected_set), 2)
    else:
        score = 1.0
        notes.append("selected_components is empty; score treated as 1.0")

    threshold = THRESHOLDS.get(tier, 0.6)
    below_threshold = score < threshold

    upgrade_candidates = missing if below_threshold else []
    downgrade_recommendation = False
    if tier == "large" and score < 0.35 and len(missing) >= 2:
        downgrade_recommendation = True
        notes.append("large tier underperformed; consider downgrade to medium")

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "day": day,
        "complexity_tier": tier,
        "selected_components": selected_set,
        "detected_components": detected_set,
        "missing_components": missing,
        "tier_expectation_score": score,
        "notes": notes,
        "upgrade_candidates": upgrade_candidates,
        "downgrade_recommendation": downgrade_recommendation,
        "threshold": threshold,
        "repo_path": to_rel(repo_path, control_dir) if repo_path else "",
    }

    out_dir = os.path.join(control_dir, "reports", "quality")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"day{day}_quality.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    print(f"[evaluate_build_quality] wrote: {to_rel(out_path, control_dir)}")

    if below_threshold:
        cand = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "day": day,
            "complexity_tier": tier,
            "selected_components": selected_set,
            "missing_components": missing,
            "recommended_next_try_components": upgrade_candidates,
            "reason": "tier expectation score below threshold",
        }
        cand_path = os.path.join(control_dir, "plans", "candidates", f"day{day}_quality_upgrade_candidates.json")
        os.makedirs(os.path.dirname(cand_path), exist_ok=True)
        with open(cand_path, "w", encoding="utf-8") as f:
            json.dump(cand, f, ensure_ascii=False, indent=2)
        print(f"[evaluate_build_quality] wrote: {to_rel(cand_path, control_dir)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
