# improvements/backlog.md
# 改善バックログ（System / Engine / Promo / Ideation 統合）

このバックログはAIが「次に何を改善するか」を自走で選ぶためのもの。
必ずメタ情報（tier/impact/risk/effort/area/success_metric）を付ける。

---

## 運用ルール（重要）
- 週1バッチの最後に System Council がレビューする
- 通常は tier0-1 の中から **1件だけ** PR化して提案する（マージは人間）
- tier2-3 は「人間の明示GO」がある場合のみ着手

---

## 優先度の目安（自動選定用）
- まず tier が低いものを優先（0 → 1 → 2 → 3）
- 同tier内では、下の簡易スコアが高いものを優先：
  - priority_score = (impact * 2) - risk - effort_penalty
  - effort_penalty：S=0 / M=1 / L=2

---

## 記入テンプレ（これをコピペして追加）

- id: IMP-000
  title: ""
  area: ideation|build|packaging|promo|system
  tier: 0|1|2|3
  impact: 1-5
  risk: 1-5
  effort: S|M|L
  success_metric: ""
  rationale: ""
  proposal: ""
  files_touched: []
  status: todo|doing|proposed|done|dropped
  notes: ""

---

## Backlog Items
（ここに新フォーマットで追記していく）

---

## Legacy Backlog (pre-metadata)
- 既存レガシー項目がある場合はこのセクションへ移して温存する。
