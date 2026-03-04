# AGENTS.md — ai-dev-exp-control

## Non-destructive policy
- 破壊的変更（削除/上書き/大量改修）は禁止。最小差分で追加する。
- 変更前に必ず `git status -sb` と `git diff` を確認。

## Run policy
- スクリプト変更時は必ず `bash -n` を通す。
- best-effort な補助タスク（digest生成等）は失敗しても止めない。
- 失敗時は logs/DayXXX.summary.md を優先して原因と最短復旧を示す。

## Artifacts of truth
- STATE.json が唯一の真実。schemasで検証し、壊れた状態をコミットしない。
- weekly prompt の最新版は system/prompts/weekly_run.md のみ。
