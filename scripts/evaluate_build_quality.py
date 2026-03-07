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

SUPPORTED_COMPONENTS = sorted(COMPONENT_PATTERNS.keys())


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


def normalize_component_list(values) -> list[str]:
    if not isinstance(values, list):
        return []
    out = []
    for item in values:
        if isinstance(item, str):
            name = item.strip()
            if name in SUPPORTED_COMPONENTS:
                out.append(name)
    return sorted(set(out))


def load_complexity_profiles(control_dir: str) -> dict:
    path = os.path.join(control_dir, "system", "complexity_profiles.json")
    if not os.path.exists(path):
        return {}
    try:
        return load_json(path)
    except Exception:
        return {}


def expected_components(meta: dict, profiles: dict, tier: str) -> list[str]:
    selected = normalize_component_list(meta.get("selected_components") or [])
    if selected:
        return selected

    profile = profiles.get(tier) if isinstance(profiles, dict) else None
    if not isinstance(profile, dict):
        return []

    preferred = normalize_component_list(profile.get("preferred_components") or [])
    rec_count = profile.get("recommended_count", 0)
    if isinstance(rec_count, int) and rec_count > 0:
        preferred = preferred[:rec_count]
    return preferred


def iter_text_files(repo_path: str) -> list[str]:
    seen = set()
    files = []
    patterns = [
        "README.md",
        "STORY.md",
        "meta.json",
        "package.json",
        "index.html",
        "dist/index.html",
        "dist/assets/*.js",
        "dist/assets/*.css",
        "src/**/*.js",
        "src/**/*.jsx",
        "src/**/*.ts",
        "src/**/*.tsx",
        "src/**/*.html",
        "src/**/*.json",
        "src/**/*.css",
        "public/**/*.json",
    ]

    for pat in patterns:
        for p in glob.glob(os.path.join(repo_path, pat), recursive=True):
            if os.path.isfile(p) and p not in seen:
                seen.add(p)
                files.append(p)

    files.sort()
    return files[:500]


def read_text(path: str, limit: int = 200_000) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read(limit)
    except Exception:
        return ""


def extract_json_object_after_token(text: str, token: str):
    idx = text.find(token)
    if idx < 0:
        return None

    start = text.find("{", idx)
    if start < 0:
        return None

    depth = 0
    in_string = False
    escape = False

    for i in range(start, len(text)):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                raw = text[start : i + 1]
                try:
                    return json.loads(raw)
                except Exception:
                    return None

    return None


def find_manifest(repo_path: str, control_dir: str) -> tuple[dict | None, list[str], list[str]]:
    notes = []
    sources = []

    explicit_paths = [
        os.path.join(repo_path, "dist", "component-pack-manifest.json"),
        os.path.join(repo_path, "public", "component-pack-manifest.json"),
        os.path.join(repo_path, "component-pack-manifest.json"),
    ]

    for p in explicit_paths:
        if os.path.isfile(p):
            try:
                obj = load_json(p)
                if isinstance(obj, dict):
                    sources.append(to_rel(p, control_dir))
                    notes.append("manifest detected from json file")
                    return obj, sources, notes
            except Exception:
                notes.append(f"manifest parse failed: {to_rel(p, control_dir)}")

    for p in iter_text_files(repo_path):
        text = read_text(p)
        if not text:
            continue

        found = None
        if "__COMPONENT_PACKS__" in text:
            found = extract_json_object_after_token(text, "__COMPONENT_PACKS__")

        if not found and "componentPackManifest" in text:
            m = re.search(r"componentPackManifest[^\n]{0,240}?(\{.*?\})", text, flags=re.DOTALL)
            if m:
                try:
                    found = json.loads(m.group(1))
                except Exception:
                    found = None

        if not found:
            m = re.search(
                r"<script[^>]*id=[\"']componentPackManifest[\"'][^>]*>(.*?)</script>",
                text,
                flags=re.DOTALL | re.IGNORECASE,
            )
            if m:
                raw = m.group(1).strip()
                try:
                    found = json.loads(raw)
                except Exception:
                    found = None

        if isinstance(found, dict):
            src = f"{to_rel(p, control_dir)}:embedded-manifest"
            sources.append(src)
            notes.append("manifest detected from embedded runtime payload")
            return found, sources, notes

    return None, sources, notes


def detect_markers(repo_path: str, control_dir: str) -> tuple[list[str], list[str], list[str]]:
    detected = set()
    notes = []
    sources = []

    known = "|".join(re.escape(x) for x in SUPPORTED_COMPONENTS)
    attr_re = re.compile(r"data-quality-marker\s*=\s*[\"']([a-z_]+)[\"']", flags=re.IGNORECASE)
    js_re = re.compile(rf"data-quality-marker[^\n]{{0,120}}?[\"']({known})[\"']", flags=re.IGNORECASE)

    for p in iter_text_files(repo_path):
        text = read_text(p)
        if not text:
            continue

        local_hits = set()
        for m in attr_re.finditer(text):
            comp = m.group(1).strip().lower()
            if comp in SUPPORTED_COMPONENTS:
                local_hits.add(comp)

        for m in js_re.finditer(text):
            comp = m.group(1).strip().lower()
            if comp in SUPPORTED_COMPONENTS:
                local_hits.add(comp)

        if local_hits:
            detected.update(local_hits)
            src = f"{to_rel(p, control_dir)}:data-quality-marker"
            sources.append(src)
            notes.append(f"marker signals detected in {to_rel(p, control_dir)}")

    return sorted(detected), sources, notes


def collect_text(repo_path: str) -> str:
    blobs = []
    for p in iter_text_files(repo_path):
        txt = read_text(p, limit=120_000)
        if txt:
            blobs.append(txt)
    return "\n".join(blobs)


def detect_components_heuristic(text: str) -> tuple[list[str], list[str]]:
    detected = []
    notes = []
    for comp, patterns in COMPONENT_PATTERNS.items():
        for pat in patterns:
            if re.search(pat, text, flags=re.IGNORECASE):
                detected.append(comp)
                notes.append(f"{comp} signal detected by heuristic pattern: {pat}")
                break
    return sorted(set(detected)), notes


def build_recommendation(
    tier: str,
    expected_set: set[str],
    achieved_set: set[str],
    missing: list[str],
    unexpected: list[str],
    confidence: str,
) -> dict:
    keep_components = sorted([c for c in expected_set if c in achieved_set])
    add_components = sorted(missing)

    remove_components: list[str] = []
    if tier == "large" and len(unexpected) >= 3 and len(missing) > 0:
        remove_components = unexpected[:2]

    if len(expected_set) == 0:
        retry_same_tier = True
    else:
        retry_same_tier = len(missing) <= max(1, len(expected_set) // 2)

    suggest_downgrade = (
        tier == "large"
        and confidence == "high"
        and len(expected_set) > 0
        and len(missing) >= max(2, (len(expected_set) + 1) // 2)
    )

    return {
        "keep_components": keep_components,
        "add_components": add_components,
        "remove_components": remove_components,
        "retry_same_tier": retry_same_tier,
        "suggest_downgrade": suggest_downgrade,
    }


def confidence_from_methods(manifest_used: bool, marker_used: bool, heuristic_used: bool) -> str:
    if manifest_used:
        return "high"
    if marker_used:
        return "medium"
    if heuristic_used:
        return "low"
    return "low"


def compute_score(tier: str, expected: list[str], achieved_set: set[str], notes: list[str]) -> float:
    expected_set = set(expected)
    if not expected_set:
        notes.append("expected_components is empty; score treated as 1.0")
        return 1.0

    matched = len([c for c in expected_set if c in achieved_set])
    base = matched / len(expected_set)

    if tier == "small":
        bonus = 0.1 if "reason_panel" in achieved_set else 0.0
        return round(min(1.0, (base * 0.9) + bonus), 2)

    if tier == "large":
        return round(base, 2)

    return round(base, 2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate generated day repo quality by complexity tier (manifest/marker/heuristic)")
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
    if not isinstance(tier, str):
        tier = "small"

    profiles = load_complexity_profiles(control_dir)
    expected = expected_components(meta, profiles, tier)
    selected = normalize_component_list(meta.get("selected_components") or [])

    repo_name = day_entry.get("repo_name", f"ai-dev-day-{day}")
    repo_path = find_repo_path(control_dir, repo_name, args.repo_path)

    notes = []
    quality_signal_sources = []

    manifest_obj = None
    manifest_rendered = []
    manifest_selected = []

    marker_detected = []
    heuristic_detected = []

    manifest_used = False
    marker_used = False
    heuristic_used = False

    if not repo_path:
        notes.append("repo path not found in .workdays")
    else:
        manifest_obj, m_sources, m_notes = find_manifest(repo_path, control_dir)
        quality_signal_sources.extend(m_sources)
        notes.extend(m_notes)
        manifest_used = isinstance(manifest_obj, dict)

        if manifest_used:
            manifest_selected = normalize_component_list(manifest_obj.get("selected_components") or [])
            manifest_rendered = normalize_component_list(manifest_obj.get("rendered_components") or [])

        marker_detected, marker_sources, marker_notes = detect_markers(repo_path, control_dir)
        if marker_detected:
            marker_used = True
            quality_signal_sources.extend(marker_sources)
            notes.extend(marker_notes)

        # Heuristic is fallback only when manifest/marker signals are both unavailable.
        if not manifest_used and not marker_used:
            text = collect_text(repo_path)
            heuristic_detected, heuristic_notes = detect_components_heuristic(text)
            heuristic_used = True
            notes.extend(heuristic_notes)
            quality_signal_sources.append("heuristic:content-patterns")
            notes.append("confidence low: fallback heuristic only")

    if not expected and manifest_selected:
        expected = manifest_selected

    rendered_components = manifest_rendered if manifest_rendered else []
    detected_components = sorted(set(marker_detected + heuristic_detected))

    achieved_set = set(rendered_components) | set(detected_components)
    expected_set = set(expected)

    missing = sorted([c for c in expected_set if c not in achieved_set])
    unexpected = sorted([c for c in achieved_set if c not in expected_set])

    score = compute_score(tier, expected, achieved_set, notes)
    threshold = THRESHOLDS.get(tier, 0.6)
    below_threshold = score < threshold

    confidence = confidence_from_methods(manifest_used, marker_used, heuristic_used)

    recommendation = build_recommendation(
        tier=tier,
        expected_set=expected_set,
        achieved_set=achieved_set,
        missing=missing,
        unexpected=unexpected,
        confidence=confidence,
    )

    downgrade_recommendation = bool(recommendation.get("suggest_downgrade"))
    upgrade_candidates = recommendation.get("add_components", []) if below_threshold else []

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "day": day,
        "complexity_tier": tier,
        "selected_components": selected,
        "expected_components": sorted(expected_set),
        "rendered_components": sorted(set(rendered_components)),
        "detected_components": sorted(set(detected_components)),
        "missing_components": missing,
        "unexpected_components": unexpected,
        "detection_method": {
            "manifest": manifest_used,
            "markers": marker_used,
            "heuristic": heuristic_used,
        },
        "quality_signal_sources": sorted(set(quality_signal_sources)),
        "tier_expectation_score": score,
        "confidence": confidence,
        "notes": notes,
        "recommendation": recommendation,
        # Backward-compatible fields
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
            "selected_components": selected,
            "expected_components": sorted(expected_set),
            "missing_components": missing,
            "recommended_next_try_components": upgrade_candidates,
            "confidence": confidence,
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
