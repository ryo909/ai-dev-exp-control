# Weekly Run Preview (2026-03-08)

## current weekly_run summary
# Weekly Run
## 基本手順
- まず `DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh` で計画確認。
- 問題なければ `ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh` を実行。
## 今週の運用方針
- adoption profile: safe

## 推奨 adoption profile
- safe

## 推奨 complexity mix
- small=4 / medium=3 / large=0

## 推奨 source bias
- buttondown.com
- github.com
- blog.katanaquant.com

## 推奨 component bias
- 冒頭1文で結論、2文目で根拠を示す『主張+証拠』導入を固定化する
- CTAを『すぐ試す』と『背景を読む』の2導線に分けて離脱を減らす

## 今週の見せ玉スロット
- slot 5: 見た目と差分訴求が強い1本にする
- showcaseだけ aggressive寄り運用候補: yes
- fallback_tier_if_needed: small

## 今週の実行例コマンド
```bash
DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh
ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh
```

## weekly_run に追記/置換すべき候補
### 今週の運用方針
- adoption profile: safe
- tier mix: small=4 medium=3 large=0
- showcase slot: 5（必要ならこの1本だけ aggressive 寄り）
- control_tower -> next_batch_plan -> thesis_update_draft -> weekly_run_report の順で確認
### 推奨コマンド例
- DRY_RUN=1 ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh
- ADOPTION_PROFILE=safe STAGE=all bash scripts/weekly_orchestrator.sh
