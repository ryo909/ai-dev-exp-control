#!/usr/bin/env python3
import argparse
import glob
import json
import os
from collections import Counter, defaultdict
from datetime import date, datetime, timezone
from typing import Any, Dict, List


def latest_file(pattern: str) -> str:
    files = glob.glob(pattern)
    if not files:
        return ""
    files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return files[0]


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def safe_float(v: Any) -> float:
    if isinstance(v, (int, float)):
        return float(v)
    return 0.0


def load_records(norm_dir: str, notes: List[str]) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    jsonl_path = os.path.join(norm_dir, "post_metrics.jsonl")
    if os.path.exists(jsonl_path):
        try:
            with open(jsonl_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    row = json.loads(line)
                    if isinstance(row, dict):
                        records.append(row)
        except Exception as e:
            notes.append(f"failed to parse jsonl: {e}")

    if not records:
        latest_daily = latest_file(os.path.join(norm_dir, "post_metrics_*.json"))
        if latest_daily:
            try:
                daily = read_json(latest_daily)
                recs = daily.get("records", []) if isinstance(daily, dict) else []
                if isinstance(recs, list):
                    records.extend([x for x in recs if isinstance(x, dict)])
            except Exception as e:
                notes.append(f"failed to parse daily normalized metrics: {e}")

    if not records:
        notes.append("no normalized feedback records available")
    return records


def top_bottom(scores: Dict[str, List[float]], top_n: int = 3) -> Dict[str, List[str]]:
    avg = []
    for k, vals in scores.items():
        if not vals:
            continue
        avg.append((k, sum(vals) / len(vals), len(vals)))
    avg.sort(key=lambda x: x[1], reverse=True)
    best = [f"{k}:{round(v,4)}(n={n})" for k, v, n in avg[:top_n]]
    weak = [f"{k}:{round(v,4)}(n={n})" for k, v, n in avg[-top_n:]] if avg else []
    return {"best": best, "weak": weak}


def main() -> int:
    parser = argparse.ArgumentParser(description="Build post-launch feedback digest")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)
    norm_dir = os.path.join(cdir, "data", "feedback", "normalized")
    out_dir = os.path.join(cdir, "reports", "feedback")
    os.makedirs(out_dir, exist_ok=True)

    notes: List[str] = []
    records = load_records(norm_dir, notes)

    # summarize by post identity
    by_post: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for r in records:
        key = (r.get("post_url") or r.get("launch_id") or f"{r.get('tool_day','')}-{r.get('channel','')}-{r.get('post_type','')}")
        by_post[str(key)].append(r)

    by_tool: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    hook_scores: Dict[str, List[float]] = defaultdict(list)
    cta_scores: Dict[str, List[float]] = defaultdict(list)
    post_type_scores: Dict[str, List[float]] = defaultdict(list)
    channel_set = set()

    for key, snaps in by_post.items():
        for s in snaps:
            tool_key = f"{s.get('tool_day','')}-{s.get('repo_name','')}-{s.get('channel','')}-{s.get('post_type','')}"
            by_tool[tool_key].append(s)
            channel_set.add(s.get("channel", ""))
            er = s.get("engagement_rate_simple")
            if isinstance(er, (int, float)):
                hook_scores[s.get("hook_family") or "unknown"].append(float(er))
                cta_scores[s.get("cta_family") or "unknown"].append(float(er))
                post_type_scores[s.get("post_type") or "unknown"].append(float(er))

    hook_tb = top_bottom(hook_scores)
    cta_tb = top_bottom(cta_scores)
    post_type_tb = top_bottom(post_type_scores)

    by_tool_rows = []
    for tkey, snaps in sorted(by_tool.items()):
        best = sorted(
            snaps,
            key=lambda x: (
                safe_float(x.get("impressions")),
                safe_float(x.get("engagement_rate_simple")),
                safe_float(x.get("engagement_simple")),
            ),
            reverse=True,
        )[0]
        by_tool_rows.append(
            {
                "tool_day": best.get("tool_day", ""),
                "tool_id": best.get("tool_id", ""),
                "repo_name": best.get("repo_name", ""),
                "channel": best.get("channel", ""),
                "post_type": best.get("post_type", ""),
                "launch_id": best.get("launch_id", ""),
                "post_id": best.get("post_id", ""),
                "best_snapshot": {
                    "post_url": best.get("post_url"),
                    "impressions": best.get("impressions"),
                    "engagement_simple": best.get("engagement_simple"),
                    "engagement_rate_simple": best.get("engagement_rate_simple"),
                    "click_through_like": best.get("click_through_like"),
                    "age_hours": best.get("age_hours"),
                },
                "performance_notes": best.get("notes", [])[:5],
                "recommended_future_actions": [
                    "hookを勝ちファミリーに寄せる",
                    "CTAを短く1アクションに絞る",
                ],
            }
        )

    launch_feedback = {
        "hero_outcomes": [x for x in by_tool_rows if x.get("post_type") == "hero"][:5],
        "secondary_outcomes": [x for x in by_tool_rows if x.get("post_type") == "secondary"][:8],
        "quiet_catalog_outcomes": [x for x in by_tool_rows if x.get("post_type") == "quiet"][:8],
        "hold_validation_notes": [
            "hold対象は投稿実績が薄い場合が多く、導線改善後に再評価",
        ],
    }

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "records_considered": len(records),
            "posts_considered": len(by_post),
            "channels_considered": sorted([x for x in channel_set if x]),
            "best_hook_families": hook_tb.get("best", []),
            "best_post_types": post_type_tb.get("best", []),
            "best_tool_patterns": [f"{x.get('tool_day')}:{x.get('post_type')}" for x in by_tool_rows[:5]],
            "notes": notes,
        },
        "launch_feedback": launch_feedback,
        "growth_feedback": {
            "winning_hooks": hook_tb.get("best", []),
            "weak_hooks": hook_tb.get("weak", []),
            "winning_ctas": cta_tb.get("best", []),
            "weak_ctas": cta_tb.get("weak", []),
            "positioning_notes": [
                "hookとone-lineの整合がある投稿の反応を優先採用",
                "CTAを1つに絞るとクリック誘導が安定しやすい",
            ],
        },
        "strategy_feedback": {
            "winning_tool_shapes": post_type_tb.get("best", []),
            "weak_tool_shapes": post_type_tb.get("weak", []),
            "complexity_notes": [
                "post_type別の反応を次バッチのcomplexity配分判断に反映する",
            ],
            "showcase_notes": [
                "hero投稿の反応が弱い場合はshowcase選定条件を再評価する",
            ],
            "portfolio_visibility_notes": [
                "導線URLが明確な投稿はclick_through_likeが改善しやすい",
            ],
        },
        "by_tool": by_tool_rows,
        "recommended_feedback_actions": [
            "勝ちhook_familyを次週のx_queueテンプレに反映",
            "弱いCTAをlaunch_export段階で置換候補化",
            "hero判定が弱い週はlaunch_with_notes基準を厳格化",
        ],
        "learned_rules_candidates": [
            "hero投稿は用途が一文で伝わるhookを優先する",
            "CTAはdemo導線1つに絞る",
            "quiet対象はgallery/caption最適化を優先しX投稿は縮小する",
        ],
    }

    out_json = os.path.join(out_dir, f"post_launch_feedback_{args.date}.json")
    out_md = os.path.join(out_dir, f"post_launch_feedback_{args.date}.md")
    write_json(out_json, payload)

    lines: List[str] = []
    lines.append(f"# Post-Launch Feedback ({args.date})")
    lines.append("")
    lines.append("## 今週の post-launch 総評")
    lines.append(f"- records/posts: {payload['summary']['records_considered']}/{payload['summary']['posts_considered']}")
    lines.append(f"- channels: {', '.join(payload['summary']['channels_considered']) or 'n/a'}")
    lines.append("")
    lines.append("## hero の当たり外れ")
    hero_out = payload["launch_feedback"]["hero_outcomes"]
    if hero_out:
        for row in hero_out:
            b = row.get("best_snapshot", {})
            lines.append(f"- Day{row.get('tool_day')} {row.get('repo_name')} / ER={b.get('engagement_rate_simple')} / imp={b.get('impressions')}")
    else:
        lines.append("- データ不足")
    lines.append("")
    lines.append("## secondary / quiet の妥当性")
    lines.append(f"- secondary records: {len(payload['launch_feedback']['secondary_outcomes'])}")
    lines.append(f"- quiet records: {len(payload['launch_feedback']['quiet_catalog_outcomes'])}")
    lines.append("")
    lines.append("## 勝ち hook / 弱い hook")
    for x in payload["growth_feedback"]["winning_hooks"]:
        lines.append(f"- winning: {x}")
    for x in payload["growth_feedback"]["weak_hooks"]:
        lines.append(f"- weak: {x}")
    lines.append("")
    lines.append("## 勝ち CTA / 弱い CTA")
    for x in payload["growth_feedback"]["winning_ctas"]:
        lines.append(f"- winning: {x}")
    for x in payload["growth_feedback"]["weak_ctas"]:
        lines.append(f"- weak: {x}")
    lines.append("")
    lines.append("## launch 判定の当たり外れ")
    for x in payload["strategy_feedback"]["showcase_notes"]:
        lines.append(f"- {x}")
    lines.append("")
    lines.append("## 次週への示唆")
    for x in payload["recommended_feedback_actions"]:
        lines.append(f"- {x}")
    lines.append("")
    lines.append("## learned_rules 候補")
    for x in payload["learned_rules_candidates"]:
        lines.append(f"- {x}")

    with open(out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[build_post_launch_feedback_digest] wrote: {os.path.relpath(out_json, cdir)}")
    print(f"[build_post_launch_feedback_digest] wrote: {os.path.relpath(out_md, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
