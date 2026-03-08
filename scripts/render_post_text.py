#!/usr/bin/env python3
"""Render post text from fixed header/body/footer templates."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PLACEHOLDER_RE = re.compile(r"{{([A-Z0-9_]+)}}")


def read_template(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        raise RuntimeError(f"template not found: {path}")


def render_text(text: str, values: dict[str, str]) -> str:
    def replace(match: re.Match[str]) -> str:
        key = match.group(1)
        return values.get(key, match.group(0))

    rendered = PLACEHOLDER_RE.sub(replace, text)
    unresolved = PLACEHOLDER_RE.findall(rendered)
    if unresolved:
        unresolved_keys = ",".join(sorted(set(unresolved)))
        raise RuntimeError(f"unresolved placeholders: {unresolved_keys}")
    return rendered


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render post text from templates")
    parser.add_argument("--templates-dir", default="templates/posts")
    parser.add_argument("--day", required=True)
    parser.add_argument("--tool-name", required=True)
    parser.add_argument("--pages-url", required=True)
    parser.add_argument("--body-id", default="A")
    parser.add_argument("--one-liner", default="")
    parser.add_argument("--use-case", default="")
    parser.add_argument("--scene-line", default="")
    parser.add_argument("--solution-line", default="")
    parser.add_argument("--experiment-name", default="")
    parser.add_argument("--observed-result", default="")
    parser.add_argument("--joke-hook", default="")
    parser.add_argument("--min-spec-line", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    control_dir = script_dir.parent
    templates_dir = (control_dir / args.templates_dir).resolve()

    body_id = args.body_id.upper()
    if body_id not in {"A", "B", "C", "D"}:
        print(f"invalid body id: {args.body_id}", file=sys.stderr)
        return 1

    values = {
        "DAY": str(args.day),
        "TOOL_NAME": args.tool_name,
        "PAGES_URL": args.pages_url,
        "ONE_LINER": args.one_liner,
        "USE_CASE": args.use_case,
        "SCENE_LINE": args.scene_line,
        "SOLUTION_LINE": args.solution_line,
        "EXPERIMENT_NAME": args.experiment_name,
        "OBSERVED_RESULT": args.observed_result,
        "JOKE_HOOK": args.joke_hook,
        "MIN_SPEC_LINE": args.min_spec_line,
    }

    try:
        header = read_template(templates_dir / "header.txt")
        body = read_template(templates_dir / f"body_{body_id}.txt")
        footer = read_template(templates_dir / "footer.txt")

        rendered_parts = [
            render_text(header, values),
            render_text(body, values),
            render_text(footer, values),
        ]
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    output = "\n".join(part for part in rendered_parts if part).strip()
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
