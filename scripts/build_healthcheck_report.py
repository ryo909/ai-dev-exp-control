#!/usr/bin/env python3
import argparse
import glob
import importlib.util
import json
import os
import subprocess
from datetime import date, datetime, timezone
from typing import Any, Dict, List, Tuple


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def latest_file(pattern: str) -> str:
    files = glob.glob(pattern)
    if not files:
        return ""
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def file_age_days(path: str) -> float:
    if not path or not os.path.exists(path):
        return 9999.0
    mtime = datetime.fromtimestamp(os.path.getmtime(path), tz=timezone.utc)
    return max(0.0, (datetime.now(timezone.utc) - mtime).total_seconds() / 86400.0)


def run_git_status(cdir: str) -> Tuple[str, int, int]:
    try:
        out = subprocess.check_output(["git", "-C", cdir, "status", "-sb"], stderr=subprocess.STDOUT, text=True)
    except Exception as e:
        return (f"git status unavailable: {e}", 0, 0)
    lines = [x for x in out.splitlines() if x.strip()]
    dirty = 0
    untracked = 0
    for ln in lines[1:]:
        if ln.startswith("??"):
            untracked += 1
        else:
            dirty += 1
    return (out.strip(), dirty, untracked)


def extract_ids(path: str, kind: str) -> Dict[str, Any]:
    if not path or not os.path.exists(path):
        return {}
    try:
        data = read_json(path)
    except Exception:
        return {}
    if not isinstance(data, dict):
        return {}

    if kind == "launch_pack":
        out = {
            "launch_id": data.get("launch_id", ""),
            "tool_ids": [],
        }
        by_day = data.get("by_day", []) if isinstance(data.get("by_day"), list) else []
        for row in by_day:
            if isinstance(row, dict) and row.get("tool_id"):
                out["tool_ids"].append(row.get("tool_id"))
        return out

    if kind == "launch_export":
        out = {
            "launch_id": data.get("launch_id", ""),
            "tool_ids": [],
            "post_ids": [],
        }
        for key in ("hero_tool",):
            row = data.get(key, {}) if isinstance(data.get(key), dict) else {}
            if row.get("tool_id"):
                out["tool_ids"].append(row.get("tool_id"))
        for key in ("secondary_tools", "quiet_catalog_tools", "hold_tools", "gallery_entries"):
            items = data.get(key, []) if isinstance(data.get(key), list) else []
            for row in items:
                if isinstance(row, dict) and row.get("tool_id"):
                    out["tool_ids"].append(row.get("tool_id"))
        xq = data.get("x_queue", []) if isinstance(data.get("x_queue"), list) else []
        for row in xq:
            if isinstance(row, dict) and row.get("post_id"):
                out["post_ids"].append(row.get("post_id"))
        return out

    if kind == "feedback":
        out = {
            "tool_ids": [],
        }
        by_tool = data.get("by_tool", []) if isinstance(data.get("by_tool"), list) else []
        for row in by_tool:
            if isinstance(row, dict) and row.get("tool_id"):
                out["tool_ids"].append(row.get("tool_id"))
        return out

    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description="Build healthcheck report for weekly preflight")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    out_dir = os.path.join(cdir, "reports", "healthcheck")
    os.makedirs(out_dir, exist_ok=True)

    checks: Dict[str, Dict[str, Any]] = {}
    manual_actions: List[str] = []
    recommended_next_steps: List[str] = []

    # 1) repo status
    git_status, dirty_count, untracked_count = run_git_status(cdir)
    repo_notes = [f"dirty_count={dirty_count}", f"untracked_count={untracked_count}"]
    if dirty_count > 0:
        repo_notes.append("working tree has tracked modifications")
    if untracked_count >= 20:
        repo_notes.append("large untracked backlog")
    repo_state = "clean" if dirty_count == 0 and untracked_count == 0 else "dirty"
    checks["repo_status"] = {
        "status": "ok" if repo_state == "clean" else "warn",
        "repo_cleanliness": repo_state,
        "notes": repo_notes,
        "git_status": git_status,
    }

    # 2) required paths
    required_paths = [
        "STATE.json",
        "scripts/weekly_orchestrator.sh",
        "scripts/build_launch_pack.py",
        "scripts/build_launch_exports.py",
        "scripts/collect_post_launch_feedback.py",
        "scripts/build_post_launch_feedback_digest.py",
        "scripts/build_healthcheck_report.py",
        "system/id_schema_policy.md",
        "system/healthcheck_policy.md",
        "reports/launch",
        "exports/launch",
        "reports/feedback",
        "data/feedback/normalized",
        "imports/feedback",
    ]
    missing = [p for p in required_paths if not os.path.exists(os.path.join(cdir, p))]
    checks["required_paths"] = {
        "status": "ok" if not missing else "warn",
        "missing": missing,
        "notes": ["required path check complete"],
    }
    if missing:
        manual_actions.append("missing required paths/scripts")

    # 3) artifact freshness
    latest = {
        "strategy": latest_file(os.path.join(cdir, "reports", "strategy", "strategy_brief_*.json")),
        "growth": latest_file(os.path.join(cdir, "reports", "growth", "growth_brief_*.json")),
        "portfolio": latest_file(os.path.join(cdir, "reports", "portfolio", "portfolio_eval_*.json")),
        "evidence": latest_file(os.path.join(cdir, "reports", "evidence", "evidence_*.json")),
        "reality": latest_file(os.path.join(cdir, "reports", "reality", "reality_gate_*.json")),
        "launch": latest_file(os.path.join(cdir, "reports", "launch", "launch_pack_*.json")),
        "export": latest_file(os.path.join(cdir, "exports", "launch", "launch_export_*.json")),
        "feedback": latest_file(os.path.join(cdir, "reports", "feedback", "post_launch_feedback_*.json")),
        "healthcheck": latest_file(os.path.join(cdir, "reports", "healthcheck", "healthcheck_*.json")),
    }
    freshness_notes = []
    stale = []
    for k, p in latest.items():
        if not p:
            freshness_notes.append(f"missing artifact: {k}")
            stale.append(k)
            continue
        age = file_age_days(p)
        if age > 14:
            freshness_notes.append(f"stale artifact: {k} age_days={round(age,2)}")
            stale.append(k)
    checks["artifact_freshness"] = {
        "status": "ok" if not stale else "warn",
        "latest_found": {k: (os.path.relpath(v, cdir) if v else "") for k, v in latest.items()},
        "notes": freshness_notes,
    }

    # 4) launch chain consistency + ID coverage
    launch_ids = extract_ids(latest.get("launch"), "launch_pack")
    export_ids = extract_ids(latest.get("export"), "launch_export")
    feedback_ids = extract_ids(latest.get("feedback"), "feedback")

    chain_notes = []
    if not launch_ids:
        chain_notes.append("launch pack missing or unreadable")
    if not export_ids:
        chain_notes.append("launch export missing or unreadable")
    if not feedback_ids:
        chain_notes.append("feedback digest missing or unreadable")

    if launch_ids and export_ids:
        l1 = launch_ids.get("launch_id")
        l2 = export_ids.get("launch_id")
        if l1 and l2 and l1 != l2:
            chain_notes.append(f"launch_id mismatch: launch_pack={l1} export={l2}")
    if export_ids and len(export_ids.get("post_ids", [])) == 0:
        chain_notes.append("x_queue post_id missing/empty")

    missing_tool_id = 0
    if launch_ids and len(launch_ids.get("tool_ids", [])) == 0:
        missing_tool_id += 1
    if export_ids and len(export_ids.get("tool_ids", [])) == 0:
        missing_tool_id += 1
    if feedback_ids and len(feedback_ids.get("tool_ids", [])) == 0:
        missing_tool_id += 1
    if missing_tool_id > 0:
        chain_notes.append("tool_id coverage is incomplete across launch/export/feedback")

    checks["launch_chain"] = {
        "status": "ok" if not chain_notes else "warn",
        "notes": chain_notes,
    }

    # 5) imports backlog
    pending_files = []
    import_dir = os.path.join(cdir, "imports", "feedback")
    if os.path.isdir(import_dir):
        for p in sorted(glob.glob(os.path.join(import_dir, "*"))):
            base = os.path.basename(p)
            if base.startswith("."):
                continue
            if os.path.isfile(p):
                pending_files.append(os.path.relpath(p, cdir))
    import_notes = []
    if pending_files:
        import_notes.append("manual feedback imports pending")
    checks["imports_backlog"] = {
        "status": "warn" if pending_files else "ok",
        "pending_files": pending_files,
        "notes": import_notes,
    }

    # 6) feedback continuity
    raw_latest = latest_file(os.path.join(cdir, "data", "feedback", "raw", "buffer_metrics_*.json"))
    norm_latest = latest_file(os.path.join(cdir, "data", "feedback", "normalized", "post_metrics_*.json"))
    norm_jsonl = os.path.join(cdir, "data", "feedback", "normalized", "post_metrics.jsonl")

    fb_notes = []
    if not raw_latest:
        fb_notes.append("raw feedback missing")
    if raw_latest and not norm_latest:
        fb_notes.append("raw exists but normalized missing")
    if not latest.get("feedback"):
        fb_notes.append("feedback digest missing")
    if os.path.exists(norm_jsonl) and os.path.getsize(norm_jsonl) == 0:
        fb_notes.append("normalized jsonl exists but currently empty")

    checks["feedback_continuity"] = {
        "status": "ok" if not fb_notes else "warn",
        "notes": fb_notes,
    }

    # 7) browser dependency
    browser_notes = []
    pw_available = importlib.util.find_spec("playwright") is not None
    if not pw_available:
        browser_notes.append("python playwright not installed; use manual import fallback")
    else:
        browser_notes.append("playwright import available")
    checks["browser_dependency"] = {
        "status": "ok" if pw_available else "warn",
        "notes": browser_notes,
    }

    # 8) pending operational risks
    risk_notes = []
    if latest.get("export") and not latest.get("feedback"):
        risk_notes.append("launch_export exists but feedback digest missing")
    xq = latest_file(os.path.join(cdir, "exports", "launch", "x_queue_*.json"))
    if xq:
        try:
            xq_data = read_json(xq)
            if isinstance(xq_data, list) and len(xq_data) == 0:
                risk_notes.append("x_queue exists but empty")
        except Exception:
            risk_notes.append("x_queue unreadable")
    checks["pending_operational_risks"] = {
        "status": "ok" if not risk_notes else "warn",
        "notes": risk_notes,
    }

    # overall
    warn_count = sum(1 for v in checks.values() if v.get("status") == "warn")
    if warn_count == 0:
        overall = "ok"
    elif warn_count <= 2:
        overall = "warn"
    else:
        overall = "attention"

    summary = {
        "overall_status": overall,
        "repo_cleanliness": repo_state,
        "artifact_freshness": checks["artifact_freshness"]["status"],
        "launch_chain_status": checks["launch_chain"]["status"],
        "feedback_status": checks["feedback_continuity"]["status"],
        "manual_attention_count": warn_count,
    }

    if checks["launch_chain"]["status"] == "warn":
        recommended_next_steps.append("launch/export/feedback の ID 充足率を上げる")
    if checks["imports_backlog"]["status"] == "warn":
        recommended_next_steps.append("imports/feedback の pending files を取り込む")
    if checks["feedback_continuity"]["status"] == "warn":
        recommended_next_steps.append("feedback raw->normalized->digest chain を再生成する")
    if checks["browser_dependency"]["status"] == "warn":
        recommended_next_steps.append("Playwright 依存回収が難しい場合は manual import 運用を先に固定する")

    payload = {
        "generated_at": now_iso(),
        "summary": summary,
        "checks": checks,
        "manual_actions": manual_actions,
        "recommended_next_steps": recommended_next_steps,
    }

    out_json = os.path.join(out_dir, f"healthcheck_{args.date}.json")
    out_md = os.path.join(out_dir, f"healthcheck_{args.date}.md")
    write_json(out_json, payload)

    lines: List[str] = []
    lines.append(f"# Healthcheck ({args.date})")
    lines.append("")
    lines.append("## 今週の healthcheck 総評")
    lines.append(f"- overall_status: {overall}")
    lines.append(f"- repo_cleanliness: {repo_state}")
    lines.append(f"- manual_attention_count: {warn_count}")
    lines.append("")
    lines.append("## 実行前に見ておくべき warning")
    for name, chk in checks.items():
        if chk.get("status") == "warn":
            lines.append(f"- {name}: {'; '.join(chk.get('notes', [])[:3])}")
    if warn_count == 0:
        lines.append("- なし")
    lines.append("")
    lines.append("## launch / export / feedback のつながり")
    for n in checks["launch_chain"].get("notes", []):
        lines.append(f"- {n}")
    if not checks["launch_chain"].get("notes"):
        lines.append("- 問題なし")
    lines.append("")
    lines.append("## manual import backlog")
    pending = checks["imports_backlog"].get("pending_files", [])
    if pending:
        for p in pending[:10]:
            lines.append(f"- {p}")
    else:
        lines.append("- なし")
    lines.append("")
    lines.append("## 未コミット差分")
    lines.append(f"- {repo_state} (tracked={dirty_count}, untracked={untracked_count})")
    lines.append("")
    lines.append("## すぐ直すべき点")
    for x in recommended_next_steps:
        lines.append(f"- {x}")
    if not recommended_next_steps:
        lines.append("- なし")
    lines.append("")
    lines.append("## 週次実行目安")
    if overall == "ok":
        lines.append("- このまま週次実行に進みやすい状態")
    elif overall == "warn":
        lines.append("- 実行可能だが warning を確認してから進行推奨")
    else:
        lines.append("- 実行は可能だが先に warning の解消を推奨")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[build_healthcheck_report] wrote: {os.path.relpath(out_json, cdir)}")
    print(f"[build_healthcheck_report] wrote: {os.path.relpath(out_md, cdir)}")
    print(f"[build_healthcheck_report] overall_status={overall}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
