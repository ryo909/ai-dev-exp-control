# Healthcheck (2026-03-08)

## 今週の healthcheck 総評
- overall_status: attention
- repo_cleanliness: dirty
- manual_attention_count: 4

## 実行前に見ておくべき warning
- repo_status: dirty_count=3; untracked_count=29; working tree has tracked modifications
- launch_chain: tool_id coverage is incomplete across launch/export/feedback
- feedback_continuity: normalized jsonl exists but currently empty
- browser_dependency: python playwright not installed; use manual import fallback

## launch / export / feedback のつながり
- tool_id coverage is incomplete across launch/export/feedback

## manual import backlog
- なし

## 未コミット差分
- dirty (tracked=3, untracked=29)

## すぐ直すべき点
- launch/export/feedback の ID 充足率を上げる
- feedback raw->normalized->digest chain を再生成する
- Playwright 依存回収が難しい場合は manual import 運用を先に固定する

## 週次実行目安
- 実行は可能だが先に warning の解消を推奨
