# scripts

## new-scenario.ps1
Issue で受け付けたシナリオ要件に合わせて、最小構成の雛形を生成します。

実行例:

```powershell
pwsh ./infra/scripts/new-scenario.ps1 -RequestType standard -ScenarioName hub-and-spoke-extended -ScenarioCode csa02
```

出力先:
- standard: `infra/scenarios/<ScenarioName>`
- adhoc: `infra/custom/<ScenarioName>`

## review-avm-versions.ps1
Bicep の AVM 参照バージョンを確認し、必要なら更新します。

実行例（確認のみ）:

```powershell
pwsh ./infra/scripts/review-avm-versions.ps1
```

実行例（自動更新）:

```powershell
pwsh ./infra/scripts/review-avm-versions.ps1 -Apply
```

レポート出力先:
- `docs/operations/avm-version-review.md`
