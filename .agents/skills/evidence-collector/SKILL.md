---
name: evidence-collector
description: "公開物の visual evidence を best-effort 収集し、上部視認性/CTA発見性/崩れリスクを reports/evidence に残したいときに使う。"
---

# Purpose
- evidence report を生成し、quality/portfolioで拾いにくい視覚リスクを可視化する。

# Inputs
- `STATE.json`
- `catalog/catalog.json`
- pages_url / .workdays の README / dist

# Output
- `reports/evidence/evidence_<YYYY-MM-DD>.json`
- `reports/evidence/evidence_<YYYY-MM-DD>.md`

# Workflow
1) `bash scripts/build_evidence_report.sh` を実行
2) `capture_status` を確認（success/partial/failed）
3) `visual_issues` と `recommended_actions` を次の修正候補に渡す

# Guardrails
- ネットワーク/Playwright失敗で停止しない
- 推定で画像内容を断定しない
- 強みと問題を両方残す
