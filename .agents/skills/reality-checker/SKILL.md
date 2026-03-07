---
name: reality-checker
description: "quality/portfolio/evidence を統合して PASS / PASS_WITH_NOTES / HOLD を返す release gate 支援。"
---

# Purpose
- 公開可否判断を明文化し、showstopper と non-blocker を分離する。

# Inputs
- `reports/quality/day*_quality.json`
- `reports/portfolio/portfolio_eval_*.json`
- `reports/evidence/evidence_*.json`
- `STATE.json`

# Output
- `reports/reality/reality_gate_<YYYY-MM-DD>.json`
- `reports/reality/reality_gate_<YYYY-MM-DD>.md`

# Workflow
1) `bash scripts/build_reality_gate.sh`
2) HOLD案件の showstoppers を修正優先へ渡す
3) PASS_WITH_NOTES は次週改善に送る

# Guardrails
- 自動ブロックしない
- 根拠を3点以上残す
- 入力欠損でも gate 全体は生成する
