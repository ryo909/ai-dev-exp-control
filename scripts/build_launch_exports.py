#!/usr/bin/env python3
import argparse
import glob
import json
import os
from datetime import date, datetime, timezone
from id_utils import (
    build_launch_id,
    build_post_id,
    normalize_cta_family,
    normalize_hook_family,
    normalize_post_type,
    normalize_tool_id,
)


def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def latest(pattern):
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


def build_x_entry(priority, launch_id, tool_day, tool_id, post_type, hook, body, cta, url, notes=None):
    n_post_type = normalize_post_type(post_type)
    n_tool_id = tool_id or normalize_tool_id(tool_day)
    return {
        "launch_id": launch_id,
        "post_id": build_post_id(launch_id, n_tool_id or "day000", "x", n_post_type, priority),
        "priority": priority,
        "tool_day": tool_day,
        "tool_id": n_tool_id,
        "channel": "x",
        "post_type": n_post_type,
        "hook": hook,
        "hook_family": normalize_hook_family(hook),
        "body": body,
        "cta": cta,
        "cta_family": normalize_cta_family(cta),
        "url": url,
        "decision_source": "launch_pack",
        "notes": notes or [],
    }


def main():
    parser = argparse.ArgumentParser(description="Build launch export artifacts from launch pack")
    parser.add_argument("--control-dir", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--date", default=date.today().isoformat())
    args = parser.parse_args()

    cdir = os.path.abspath(args.control_dir)

    p_launch = latest(os.path.join(cdir, "reports", "launch", "launch_pack_*.json"))
    p_growth = latest(os.path.join(cdir, "reports", "growth", "growth_brief_*.json"))
    p_strategy = latest(os.path.join(cdir, "reports", "strategy", "strategy_brief_*.json"))
    p_portfolio = latest(os.path.join(cdir, "reports", "portfolio", "portfolio_eval_*.json"))
    p_evidence = latest(os.path.join(cdir, "reports", "evidence", "evidence_*.json"))
    p_reality = latest(os.path.join(cdir, "reports", "reality", "reality_gate_*.json"))
    p_showcase = latest(os.path.join(cdir, "reports", "showcase", "showcase_plan_*.json"))
    p_tower = latest(os.path.join(cdir, "reports", "control_tower", "weekly_control_tower_*.json"))

    launch = read_json(p_launch) if p_launch else {}
    growth = read_json(p_growth) if p_growth else {}
    strategy = read_json(p_strategy) if p_strategy else {}
    portfolio = read_json(p_portfolio) if p_portfolio else {}
    evidence = read_json(p_evidence) if p_evidence else {}
    reality = read_json(p_reality) if p_reality else {}
    showcase = read_json(p_showcase) if p_showcase else {}
    tower = read_json(p_tower) if p_tower else {}

    inputs_used = {
        "launch_pack": bool(launch),
        "growth": bool(growth),
        "strategy": bool(strategy),
        "portfolio": bool(portfolio),
        "evidence": bool(evidence),
        "reality": bool(reality),
        "showcase": bool(showcase),
        "control_tower": bool(tower),
    }

    hero = (launch.get("launch_decisions", {}) or {}).get("hero_tool", {}) if isinstance(launch, dict) else {}
    hero_pack = (launch.get("hero_launch_pack", {}) or {}) if isinstance(launch, dict) else {}
    by_day = launch.get("by_day", []) if isinstance(launch.get("by_day", []), list) else []
    launch_id = (launch.get("launch_id") if isinstance(launch, dict) else "") or build_launch_id(args.date)

    secondary = []
    hold_tools = []
    quiet_tools = []
    for row in by_day:
        d = row.get("decision", "")
        if d in ("launch_now", "launch_with_notes") and row.get("day") != hero.get("day"):
            secondary.append(row)
        elif d == "hold":
            hold_tools.append(row)
        elif d == "quiet_catalog":
            quiet_tools.append(row)

    def enrich_row(row):
        if not isinstance(row, dict):
            return {}
        out = dict(row)
        out["launch_id"] = launch_id
        out["tool_id"] = out.get("tool_id") or normalize_tool_id(out.get("day", ""))
        out["decision_source"] = out.get("decision_source", "launch_pack")
        return out

    secondary = [enrich_row(x) for x in secondary]
    hold_tools = [enrich_row(x) for x in hold_tools]
    quiet_tools = [enrich_row(x) for x in quiet_tools]

    hero_day = hero.get("day", "")
    hero_title = hero.get("title") or hero.get("repo_name", "")
    hero_url = hero.get("pages_url", "")
    one_line = hero_pack.get("one_line_positioning") or hero.get("one_line_positioning", "")

    hooks = hero_pack.get("x_hooks", []) if isinstance(hero_pack.get("x_hooks", []), list) else []
    ctas = hero_pack.get("cta_candidates", []) if isinstance(hero_pack.get("cta_candidates", []), list) else []
    hero_msg = hero_pack.get("hero_message", "")
    dist_mix = (launch.get("summary", {}) or {}).get("recommended_distribution_mix", [])

    x_queue = []
    if hero:
        hero_tool_id = hero.get("tool_id") or normalize_tool_id(hero_day)
        primary_hook = hooks[0] if hooks else f"{hero_title} を公開しました"
        primary_cta = ctas[0] if ctas else "触って感想をもらえると助かります。"
        body = one_line or hero_msg or f"{hero_title} を今週の1本として公開"
        x_queue.append(build_x_entry(1, launch_id, hero_day, hero_tool_id, "hero", primary_hook, body, primary_cta, hero_url, ["hero candidate"]))
        if len(hooks) > 1:
            x_queue.append(build_x_entry(2, launch_id, hero_day, hero_tool_id, "hero", hooks[1], body, primary_cta, hero_url, ["alt hook"]))

    pri = 3
    for s in secondary[:3]:
        s_tool_id = s.get("tool_id") or normalize_tool_id(s.get("day", ""))
        hook = (s.get("hook_candidates", []) or [f"{s.get('title', s.get('repo_name', 'tool'))} も公開中"])[0]
        cta = (s.get("cta_candidates", []) or ["こちらも試してみてください"])[0]
        x_queue.append(
            build_x_entry(
                pri,
                launch_id,
                s.get("day", ""),
                s_tool_id,
                "secondary",
                hook,
                s.get("one_line_positioning", ""),
                cta,
                s.get("pages_url", ""),
                ["secondary candidate"],
            )
        )
        pri += 1

    note_seed = {
        "title_candidates": [
            f"{hero_title} を作った理由と設計メモ",
            f"{hero_title} の体験設計: 1分で価値を伝える方法",
            f"小さなツールを公開し続けるための実装メモ（{hero_title}編）",
        ],
        "target_tool": hero_day,
        "target_tool_id": hero.get("tool_id") or normalize_tool_id(hero_day),
        "angle": "hero tool の用途即時理解 + launch導線最適化",
        "intro_seed": (one_line or hero_msg or "今週のhero toolをどう押し出すかを整理した。"),
        "outline": hero_pack.get("note_outline", []) if isinstance(hero_pack.get("note_outline", []), list) else [
            "背景",
            "設計意図",
            "使い方",
            "今後の改善",
        ],
        "cta_candidates": ctas[:3] if ctas else ["触ってフィードバックをください。"],
    }

    gallery_entries = []
    for row in by_day:
        pr = "hero" if row.get("day") == hero_day else ("quiet" if row.get("decision") == "quiet_catalog" else ("hold" if row.get("decision") == "hold" else "secondary"))
        caps = []
        if row.get("day") == hero_day and isinstance(hero_pack.get("gallery_caption_candidates", []), list):
            caps = hero_pack.get("gallery_caption_candidates", [])[:3]
        if not caps:
            caps = [row.get("one_line_positioning", ""), f"{row.get('title', row.get('repo_name', 'tool'))} | {row.get('decision', '')}"]

        gallery_entries.append(
            {
                "day": row.get("day", ""),
                "tool_id": row.get("tool_id") or normalize_tool_id(row.get("day", "")),
                "title": row.get("title", row.get("repo_name", "")),
                "one_line": row.get("one_line_positioning", ""),
                "caption_candidates": caps[:3],
                "pages_url": row.get("pages_url", ""),
                "repo_url": row.get("repo_url", ""),
                "display_priority": pr,
            }
        )

    make_payload = {
        "launch_id": launch_id,
        "hero_tool": {
            "day": hero_day,
            "tool_id": hero.get("tool_id") or normalize_tool_id(hero_day),
            "title": hero_title,
            "pages_url": hero_url,
            "decision": hero.get("decision", "launch_with_notes"),
        },
        "secondary_tools": [{"day": x.get("day"), "tool_id": x.get("tool_id") or normalize_tool_id(x.get("day", "")), "title": x.get("title", x.get("repo_name", ""))} for x in secondary[:5]],
        "distribution_mix": dist_mix,
        "copy_assets": {
            "one_line": one_line,
            "hero_message": hero_msg,
            "hooks": hooks[:5],
            "ctas": ctas[:4],
        },
        "notes": [
            "manual review required before external send",
            "do not auto-post without final human check",
        ],
    }

    launch_export = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "launch_id": launch_id,
        "summary": {
            "hero_tool": hero_day,
            "secondary_count": len(secondary),
            "hold_count": len(hold_tools),
            "quiet_catalog_count": len(quiet_tools),
            "recommended_distribution_mix": dist_mix,
            "inputs_used": inputs_used,
        },
        "hero_tool": {
            "day": hero_day,
            "tool_id": hero.get("tool_id") or normalize_tool_id(hero_day),
            "repo_name": hero.get("repo_name", ""),
            "title": hero_title,
            "pages_url": hero_url,
            "repo_url": hero.get("repo_url", ""),
            "decision": hero.get("decision", "launch_with_notes"),
            "decision_source": hero.get("decision_source", "launch_pack"),
            "one_line_positioning": one_line,
            "hero_message": hero_msg,
            "preferred_channels": hero.get("preferred_channels", []),
            "proof_points": hero_pack.get("proof_points", []),
            "risk_notes": hero_pack.get("risk_notes", []),
            "required_fixes_before_push": hero.get("required_fixes_before_push", []),
        },
        "secondary_tools": secondary,
        "hold_tools": hold_tools,
        "quiet_catalog_tools": quiet_tools,
        "x_queue": x_queue,
        "note_seed": note_seed,
        "gallery_entries": gallery_entries,
        "make_payload": make_payload,
        "recommended_export_actions": [
            "hero 投稿文を最終確認してX/Bufferへ手動投入",
            "note seed を下書き化して見出しと導入を整える",
            "gallery entries を表示優先度に沿って反映",
            "hold対象は fixes 完了後に再export",
        ],
        "quality_signal_sources": [
            rel(p_launch, cdir),
            rel(p_growth, cdir),
            rel(p_strategy, cdir),
            rel(p_portfolio, cdir),
            rel(p_evidence, cdir),
            rel(p_reality, cdir),
            rel(p_showcase, cdir),
            rel(p_tower, cdir),
        ],
    }

    out_dir = os.path.join(cdir, "exports", "launch")
    os.makedirs(out_dir, exist_ok=True)

    p_export_json = os.path.join(out_dir, f"launch_export_{args.date}.json")
    p_export_md = os.path.join(out_dir, f"launch_export_{args.date}.md")
    p_make = os.path.join(out_dir, f"make_payload_{args.date}.json")
    p_note = os.path.join(out_dir, f"note_seed_{args.date}.md")
    p_gallery = os.path.join(out_dir, f"gallery_entries_{args.date}.json")
    p_xq = os.path.join(out_dir, f"x_queue_{args.date}.json")

    write_json(p_export_json, launch_export)
    write_json(p_make, make_payload)
    write_json(p_gallery, gallery_entries)
    write_json(p_xq, x_queue)

    note_lines = [
        f"# note seed ({args.date})",
        "",
        f"- target_tool: {note_seed['target_tool']}",
        f"- angle: {note_seed['angle']}",
        "",
        "## title_candidates",
    ]
    for t in note_seed["title_candidates"]:
        note_lines.append(f"- {t}")
    note_lines.append("")
    note_lines.append("## intro_seed")
    note_lines.append(note_seed["intro_seed"])
    note_lines.append("")
    note_lines.append("## outline")
    for o in note_seed["outline"]:
        note_lines.append(f"- {o}")
    note_lines.append("")
    note_lines.append("## cta_candidates")
    for c in note_seed["cta_candidates"]:
        note_lines.append(f"- {c}")
    write_text(p_note, "\n".join(note_lines) + "\n")

    md = []
    md.append(f"# Launch Export ({args.date})")
    md.append("")
    md.append("## 今週の export 総評")
    md.append(f"- hero_tool: {hero_day} {hero_title}")
    md.append(f"- secondary/quiet/hold: {len(secondary)}/{len(quiet_tools)}/{len(hold_tools)}")
    md.append(f"- distribution_mix: {', '.join(dist_mix) if dist_mix else 'n/a'}")
    md.append("")
    md.append("## hero tool の handoff")
    md.append(f"- decision: {hero.get('decision', 'launch_with_notes')}")
    md.append(f"- one_line: {one_line}")
    md.append(f"- pages: {hero_url}")
    md.append("")
    md.append("## secondary / quiet / hold")
    if secondary:
        for s in secondary:
            md.append(f"- secondary: {s.get('day')} {s.get('repo_name')} ({s.get('decision')})")
    if quiet_tools:
        for s in quiet_tools[:5]:
            md.append(f"- quiet: {s.get('day')} {s.get('repo_name')}")
    if hold_tools:
        for s in hold_tools[:5]:
            md.append(f"- hold: {s.get('day')} {s.get('repo_name')} / {', '.join(s.get('issues', [])[:2])}")
    if not (secondary or quiet_tools or hold_tools):
        md.append("- no additional candidates")
    md.append("")
    md.append("## X / Buffer 向け投稿候補")
    for q in x_queue[:6]:
        md.append(f"- [{q['priority']}] {q['tool_day']} {q['post_type']}: {q['hook']}")
    if not x_queue:
        md.append("- none")
    md.append("")
    md.append("## note 記事 seed")
    md.append(f"- target_tool: {note_seed['target_tool']}")
    md.append(f"- intro_seed: {note_seed['intro_seed']}")
    md.append("- outline:")
    for o in note_seed["outline"]:
        md.append(f"  - {o}")
    md.append("")
    md.append("## gallery / catalog 用短文")
    for g in gallery_entries[:5]:
        cap = (g.get("caption_candidates") or [""])[0]
        md.append(f"- {g.get('day')} {g.get('title')}: {cap}")
    md.append("")
    md.append("## Make へ渡す時の要点")
    md.append(f"- hero: {make_payload['hero_tool'].get('day')} {make_payload['hero_tool'].get('title')}")
    md.append("- manual review required before external send")
    md.append("")
    md.append("## 手動確認が必要な点")
    md.append("- hook/body/CTA の事実整合")
    md.append("- hold対象の修正完了")
    md.append("- URL と公開状態")
    md.append("")
    md.append("## すぐやるべき export 前修正")
    for a in launch_export["recommended_export_actions"]:
        md.append(f"- {a}")

    write_text(p_export_md, "\n".join(md) + "\n")

    print(f"[build_launch_exports] wrote: {rel(p_export_json, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_export_md, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_make, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_note, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_gallery, cdir)}")
    print(f"[build_launch_exports] wrote: {rel(p_xq, cdir)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
