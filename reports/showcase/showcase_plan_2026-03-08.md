# Showcase Plan (2026-03-08)

## 今週の見せ玉候補一覧
- slot 5 (tier=medium, score=0.683): components=reason_panel, sample_inputs
- slot 6 (tier=medium, score=0.683): components=reason_panel, sample_inputs
- slot 7 (tier=medium, score=0.683): components=reason_panel, sample_inputs
- slot 1 (tier=small, score=0.601): components=reason_panel
- slot 2 (tier=small, score=0.601): components=reason_panel
- slot 3 (tier=small, score=0.601): components=reason_panel
- slot 4 (tier=small, score=0.601): components=reason_panel

## 各候補の採点理由
### slot 5
- scores: novelty=0.715, showcase_potential=0.45, implementation_risk=0.67, component_fit=1.0, competitor_signal_strength=0.888, quality_confidence=0.55, total=0.683
- tier=medium, components=reason_panel, sample_inputs
- showcase_potential=0.45, implementation_risk=0.67
- competitor_signal_strength=0.888, quality_confidence=0.55
### slot 6
- scores: novelty=0.715, showcase_potential=0.45, implementation_risk=0.67, component_fit=1.0, competitor_signal_strength=0.888, quality_confidence=0.55, total=0.683
- tier=medium, components=reason_panel, sample_inputs
- showcase_potential=0.45, implementation_risk=0.67
- competitor_signal_strength=0.888, quality_confidence=0.55
### slot 7
- scores: novelty=0.715, showcase_potential=0.45, implementation_risk=0.67, component_fit=1.0, competitor_signal_strength=0.888, quality_confidence=0.55, total=0.683
- tier=medium, components=reason_panel, sample_inputs
- showcase_potential=0.45, implementation_risk=0.67
- competitor_signal_strength=0.888, quality_confidence=0.55
### slot 1
- scores: novelty=0.438, showcase_potential=0.2, implementation_risk=0.85, component_fit=1.0, competitor_signal_strength=0.888, quality_confidence=0.55, total=0.601
- tier=small, components=reason_panel
- showcase_potential=0.2, implementation_risk=0.85
- competitor_signal_strength=0.888, quality_confidence=0.55
### slot 2
- scores: novelty=0.438, showcase_potential=0.2, implementation_risk=0.85, component_fit=1.0, competitor_signal_strength=0.888, quality_confidence=0.55, total=0.601
- tier=small, components=reason_panel
- showcase_potential=0.2, implementation_risk=0.85
- competitor_signal_strength=0.888, quality_confidence=0.55
### slot 3
- scores: novelty=0.438, showcase_potential=0.2, implementation_risk=0.85, component_fit=1.0, competitor_signal_strength=0.888, quality_confidence=0.55, total=0.601
- tier=small, components=reason_panel
- showcase_potential=0.2, implementation_risk=0.85
- competitor_signal_strength=0.888, quality_confidence=0.55
### slot 4
- scores: novelty=0.438, showcase_potential=0.2, implementation_risk=0.85, component_fit=1.0, competitor_signal_strength=0.888, quality_confidence=0.55, total=0.601
- tier=small, components=reason_panel
- showcase_potential=0.2, implementation_risk=0.85
- competitor_signal_strength=0.888, quality_confidence=0.55

## 選定された showcase slot
- slot: 5

## その1本に推奨する構成
- target tier: medium
- component bias: reason_panel, sample_inputs, comparison_view
- adopt competitor enhancement: True
- goal: 見た目と差分訴求が強い1本にする

## なぜ他のスロットではないのか
- total score が最も高いスロットを採用（同点時は showcase_potential -> implementation_risk の順で比較）。
- quality/fallback/blocked signal を加味し、映えと実装安定性のバランスを優先。

## fallback 方針
- fallback_tier_if_needed: small
- 自動再試行は行わず、quality report / fallback plan / showcase plan を見て人手判断する。
