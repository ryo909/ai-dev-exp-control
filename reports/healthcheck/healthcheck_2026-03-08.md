# Healthcheck (2026-03-08)

## 今週の healthcheck 総評
- overall_status: warn
- repo_cleanliness: dirty
- manual_attention_count: 2

## 実行前に見ておくべき warning
- repo_status: dirty_count=2; untracked_count=0; working tree has tracked modifications
- browser_dependency: python playwright not installed; use manual import fallback

## launch / export / feedback のつながり
- 問題なし

## manual import backlog
- なし

## 未コミット差分
- dirty (tracked=2, untracked=0)

## すぐ直すべき点
- Playwright 依存回収が難しい場合は manual import 運用を先に固定する

## 週次実行目安
- 実行可能だが warning を確認してから進行推奨
