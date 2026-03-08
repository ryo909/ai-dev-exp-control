# Enhancement Policy

- 初期は安全優先で、`competitor_scan_*_shortlist.json` から候補生成のみ行う。
- 候補は `plans/candidates/dayNNN_enhanced_candidates.json` に保存し、既存企画を自動上書きしない。
- 採用は `ADOPT_ENHANCED_PLAN=1` のときだけ行い、recommended candidate のみ適用する。
- 採用時も `original_twist` / `original_one_sentence` を保持する。
- competitor由来提案は差分強化のみとし、既存企画の軸を壊さない。
- blocked/failed target は根拠に含めない。
- `idea_bank/shortlist.json` がない場合は先に以下を実行する。
  - `bash scripts/research_refresh.sh`
  - `bash scripts/idea_shortlist.sh`

## Control Tower連携
- enhancement candidate は control tower の day decision summary で `enhance` 判断時の優先候補として使う。
