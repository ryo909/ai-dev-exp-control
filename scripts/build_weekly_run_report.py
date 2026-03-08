#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import date, datetime, timezone


def latest(pattern: str):
    files = glob.glob(pattern)
    if not files:
        return None
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def rel(path: str, base: str) -> str:
    return os.path.relpath(path, base) if path and os.path.exists(path) else ""


def write_json(path: str, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build weekly run report from current artifacts")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    parser.add_argument("--adoption-profile", default="safe")
    parser.add_argument("--dry-run", default="0")
    parser.add_argument("--stages", default="")
    parser.add_argument("--resume-executed", default="false")
    parser.add_argument("--publish-mode", default="preview")
    parser.add_argument("--allow-external-send", default="0")
    parser.add_argument("--publish-summary", default="")
    parser.add_argument("--flags-json", default="{}")
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    out_dir = os.path.join(cdir, "reports", "weekly")
    os.makedirs(out_dir, exist_ok=True)

    signals = os.path.join(cdir, "shared-context", "SIGNALS.md")
    shortlist = os.path.join(cdir, "idea_bank", "shortlist.json")
    tower = latest(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))
    next_plan = os.path.join(cdir, "plans", "next_batch_plan.json")
    thesis_draft = latest(os.path.join(cdir, "reports", "weekly", "thesis_update_draft_*.md"))
    thesis_preview = latest(os.path.join(cdir, "reports", "weekly", "thesis_preview_*.md"))
    weekly_run_preview = latest(os.path.join(cdir, "reports", "weekly", "weekly_run_preview_*.md"))
    thesis_adoption_report = latest(os.path.join(cdir, "reports", "weekly", "thesis_adoption_report_*.json"))
    weekly_run_adoption_report = latest(os.path.join(cdir, "reports", "weekly", "weekly_run_adoption_report_*.json"))
    learning_preview = latest(os.path.join(cdir, "reports", "weekly", "learning", "learning_update_preview_*.json"))
    learning_adoption_report = latest(os.path.join(cdir, "reports", "weekly", "learning", "learning_adoption_report_*.json"))
    weekly_digest = os.path.join(cdir, "reports", "weekly_digest.md")
    portfolio_eval = latest(os.path.join(cdir, "reports", "portfolio", "portfolio_eval_*.json"))
    growth_brief = latest(os.path.join(cdir, "reports", "growth", "growth_brief_*.json"))
    strategy_brief = latest(os.path.join(cdir, "reports", "strategy", "strategy_brief_*.json"))
    evidence_report = latest(os.path.join(cdir, "reports", "evidence", "evidence_*.json"))
    reality_gate = latest(os.path.join(cdir, "reports", "reality", "reality_gate_*.json"))
    launch_pack = latest(os.path.join(cdir, "reports", "launch", "launch_pack_*.json"))
    launch_export = latest(os.path.join(cdir, "exports", "launch", "launch_export_*.json"))
    feedback_raw = latest(os.path.join(cdir, "data", "feedback", "raw", "buffer_metrics_*.json"))
    feedback_digest = latest(os.path.join(cdir, "reports", "feedback", "post_launch_feedback_*.json"))
    healthcheck = latest(os.path.join(cdir, "reports", "healthcheck", "healthcheck_*.json"))
    publish_preview = latest(os.path.join(cdir, "reports", "publish", "publish_preview_*.json"))
    publish_send = ""
    if str(args.publish_mode).lower() == "send" or str(args.allow_external_send) == "1":
        publish_send = latest(os.path.join(cdir, "reports", "publish", "make_webhook_send_*.json"))
    publish_weekly_summary = args.publish_summary if (args.publish_summary and os.path.exists(args.publish_summary)) else latest(
        os.path.join(cdir, "reports", "publish", "publish_weekly_summary_*.json")
    )

    quality_reports = sorted(glob.glob(os.path.join(cdir, "reports", "quality", "day*_quality.json")))
    fallback_plans = sorted(glob.glob(os.path.join(cdir, "plans", "candidates", "day*_fallback_plan.json")))
    enhanced_candidates = sorted(glob.glob(os.path.join(cdir, "plans", "candidates", "day*_enhanced_candidates.json")))

    try:
      flags = json.loads(args.flags_json)
      if not isinstance(flags, dict):
        flags = {}
    except Exception:
      flags = {}

    stages_run = [s for s in args.stages.split(",") if s]

    publish_summary_data = {}
    if publish_weekly_summary and os.path.exists(publish_weekly_summary):
      try:
        with open(publish_weekly_summary, "r", encoding="utf-8") as f:
          publish_summary_data = json.load(f)
      except Exception:
        publish_summary_data = {}

    payload = {
      "generated_at": datetime.now(timezone.utc).isoformat(),
      "adoption_profile": args.adoption_profile,
      "dry_run": str(args.dry_run) == "1",
      "stages_run": stages_run,
      "artifacts": {
        "signals": rel(signals, cdir),
        "shortlist": rel(shortlist, cdir),
        "control_tower": rel(tower, cdir),
        "next_batch_plan": rel(next_plan, cdir),
        "thesis_update_draft": rel(thesis_draft, cdir),
        "thesis_preview": rel(thesis_preview, cdir),
        "weekly_run_preview": rel(weekly_run_preview, cdir),
        "thesis_adoption_report": rel(thesis_adoption_report, cdir),
        "weekly_run_adoption_report": rel(weekly_run_adoption_report, cdir),
        "learning_preview": rel(learning_preview, cdir),
        "learning_adoption_report": rel(learning_adoption_report, cdir),
        "weekly_digest": rel(weekly_digest, cdir),
        "portfolio_eval": rel(portfolio_eval, cdir),
        "growth_brief": rel(growth_brief, cdir),
        "strategy_brief": rel(strategy_brief, cdir),
        "evidence_report": rel(evidence_report, cdir),
        "reality_gate": rel(reality_gate, cdir),
        "launch_pack": rel(launch_pack, cdir),
        "launch_export": rel(launch_export, cdir),
        "feedback_raw": rel(feedback_raw, cdir),
        "feedback_digest": rel(feedback_digest, cdir),
        "healthcheck": rel(healthcheck, cdir),
        "publish_preview": rel(publish_preview, cdir),
        "publish_send_report": rel(publish_send, cdir),
        "publish_weekly_summary": rel(publish_weekly_summary, cdir),
        "id_linked_chain_present": bool(rel(launch_pack, cdir) and rel(launch_export, cdir) and rel(feedback_digest, cdir)),
        "quality_reports": [rel(p, cdir) for p in quality_reports],
        "fallback_plans": [rel(p, cdir) for p in fallback_plans],
        "enhanced_candidates": [rel(p, cdir) for p in enhanced_candidates],
      },
      "adoption_flags": flags,
      "summary": {
        "resume_executed": str(args.resume_executed).lower() == "true",
        "publish_mode": args.publish_mode,
        "allow_external_send": str(args.allow_external_send) == "1",
        "publish": {
          "target_days": publish_summary_data.get("target_days", []),
          "target_platforms": publish_summary_data.get("target_platforms", []),
          "x_ready_count": ((publish_summary_data.get("readiness") or {}).get("x_ready_count", 0)),
          "youtube_ready_count": ((publish_summary_data.get("readiness") or {}).get("youtube_ready_count", 0)),
          "youtube_pending_asset_count": ((publish_summary_data.get("readiness") or {}).get("youtube_pending_asset_count", 0)),
          "gallery_apply_count": publish_summary_data.get("gallery_apply_count", 0),
          "x_sent_target_count": len(publish_summary_data.get("x_sent_targets", []) or []),
          "youtube_sent_target_count": len(publish_summary_data.get("youtube_sent_targets", []) or []),
          "duplicate_target_count": publish_summary_data.get("duplicate_target_count", 0),
          "blocked_target_count": publish_summary_data.get("blocked_target_count", 0),
          "skipped_target_count": publish_summary_data.get("skipped_target_count", 0),
          "batch_ids": publish_summary_data.get("batch_ids", []),
          "external_send_executed": bool(publish_summary_data.get("external_send_executed", False)),
        },
        "notes": []
      }
    }

    if payload["dry_run"]:
      payload["summary"]["notes"].append("dry-run mode: no resume execution and no mutation steps")
    if not payload["artifacts"]["control_tower"]:
      payload["summary"]["notes"].append("control tower artifact missing")

    out_json = os.path.join(out_dir, f"weekly_run_report_{args.date}.json")
    out_md = os.path.join(out_dir, f"weekly_run_report_{args.date}.md")
    write_json(out_json, payload)

    lines = []
    lines.append(f"# Weekly Run Report ({args.date})")
    lines.append("")
    lines.append(f"- adoption profile: {payload['adoption_profile']}")
    lines.append(f"- dry_run: {payload['dry_run']}")
    lines.append(f"- resume executed: {payload['summary']['resume_executed']}")
    lines.append(f"- publish_mode: {payload['summary']['publish_mode']}")
    lines.append(f"- allow_external_send: {payload['summary']['allow_external_send']}")
    lines.append("")
    lines.append("## Stages")
    for s in stages_run:
      lines.append(f"- {s}")
    lines.append("")
    lines.append("## Adoption Flags")
    for k, v in payload["adoption_flags"].items():
      lines.append(f"- {k}={v}")
    lines.append("")
    lines.append("## Artifacts")
    for k, v in payload["artifacts"].items():
      if isinstance(v, list):
        lines.append(f"- {k}: {len(v)} files")
      else:
        lines.append(f"- {k}: {v or '(missing)'}")
    lines.append("")
    lines.append("## Publish")
    pub = payload["summary"]["publish"]
    lines.append(f"- target_days: {','.join(pub.get('target_days', []))}")
    lines.append(f"- target_platforms: {','.join(pub.get('target_platforms', []))}")
    lines.append(f"- x_ready_count: {pub.get('x_ready_count', 0)}")
    lines.append(f"- youtube_ready_count: {pub.get('youtube_ready_count', 0)}")
    lines.append(f"- youtube_pending_asset_count: {pub.get('youtube_pending_asset_count', 0)}")
    lines.append(f"- gallery_apply_count: {pub.get('gallery_apply_count', 0)}")
    lines.append(f"- x_sent_target_count: {pub.get('x_sent_target_count', 0)}")
    lines.append(f"- youtube_sent_target_count: {pub.get('youtube_sent_target_count', 0)}")
    lines.append(f"- duplicate_target_count: {pub.get('duplicate_target_count', 0)}")
    lines.append(f"- blocked_target_count: {pub.get('blocked_target_count', 0)}")
    lines.append(f"- skipped_target_count: {pub.get('skipped_target_count', 0)}")
    lines.append(f"- external_send_executed: {pub.get('external_send_executed', False)}")
    lines.append(f"- batch_ids: {','.join(pub.get('batch_ids', []))}")
    lines.append("")
    lines.append("## Next Actions")
    lines.append("- control_tower -> next_batch_plan -> thesis_update_draft の順で確認")
    lines.append("- safe profile で継続し、安定後に balanced を試す")

    with open(out_md, "w", encoding="utf-8") as f:
      f.write("\n".join(lines) + "\n")

    print(f"[build_weekly_run_report] wrote: {rel(out_md, cdir)}")
    print(f"[build_weekly_run_report] wrote: {rel(out_json, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
