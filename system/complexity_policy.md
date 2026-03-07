# Complexity Policy

## 目的
- 7本バッチで成功率を維持しつつ、見せ玉の作り込みを増やす。

## 配分
- 1バッチ7本の既定配分: `small x4`, `medium x2`, `large x1`
- day_index_in_batch を基準に決定する（決定的で再現可能）。

## 指針
- small: 余計な複数機能を足さず単機能に絞る。
- medium: 安全な部品を1〜3個追加する。
- large: 見せ場のある部品を複数追加する。

## 安全な追加部品
- `history_panel`
- `comparison_view`
- `local_storage`
- `sample_inputs`
- `export_suite`
- `reason_panel`
- `step_ui`

- 複雑度はコード量ではなく、再利用可能な部品数で上げる。
