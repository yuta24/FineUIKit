---
type: "Testing Runbook"
title: "ビルド、CI、変更別テスト指針"
description: "FineUIKit の Swift Package・iOS Simulator CI と、レンダリング、UIKit 統合、List/Grid の変更に対応するテスト選択ガイド。"
tags: [testing, ci, operations, swift]
---

# ビルド、CI、変更別テスト指針

FineUIKit は iOS 17 を deployment floor とする Swift Package です。`Package.swift` は Swift 6.2 tools、Swift 6 language mode、`ApproachableConcurrency` を library と test target に設定しています（[Package.swift](../../Package.swift)）。このページは、[レンダリングワークフロー](../workflows/rendering.md)および[UIKit 統合とコレクション](../integrations/uikit-collections.md)を変更した際に、どのテストで不変条件を確認するかを示します。

## ローカル確認

CI と同じ形式で iOS Simulator に対して実行します。利用可能な Simulator の UDID を選んでください。

```sh
xcodebuild -scheme FineUIKit \
  -destination "platform=iOS Simulator,id=SIMULATOR_UDID" \
  test
```

Swift Testing の振る舞いテストが大半を占めます。`RenderingPerformanceTests.swift` は XCTest の計測ケースで、性能の絶対値ではなく、変更前後の傾向を把握する用途です。

## CI の前提

[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) は `main` への push と pull request で macOS 26 を使い、iOS 26 runtime の利用可能な iPhone Simulator を JSON から明示選択します。指定 runtime がなければ、別 runtime へ暗黙に fallback せず失敗します。iOS 17 の対応下限は、Xcode 26/27 に iOS 17 runtime が同梱されないため、runtime 実行ではなく compile-time availability により維持します。

テスト実行ステップは二重のタイムアウト境界を持ちます（`4b877b5`）。ステップの `timeout-minutes: 12` は、シミュレータが起動しない、XPC 接続が切断されるなど、テスト機構が捕捉できないハングを含むあらゆる停止の最後の砦です。`xcodebuild -test-timeouts-enabled -default-test-execution-time-allowance 120` は XCTest 機構で個別テストを 120 秒で打ち切り、ハングしたテストを名前付きで報告しつつ残りのスイートを継続させます。Swift Testing の時間制限は別の opt-in trait であるため、このフラグだけでは不十分であり、ステップタイムアウトが補完します。allowance は XCTest が 1 分を下限として切り上げるため、120 が意図通りに読める最初の値です。

個別テストの allowance が意味を持つため、テストは `-parallel-testing-enabled NO` で直列実行します（`f65f125`）。Swift Testing は既定で in-process 並列化しますが、本スイートはほぼ全体が `@MainActor` かつ `await Task.yield()` のポーリングループで構成されるため、並列時は各テストが main actor の順番待ちにほとんどの時間を費やし、最後に一斉に完了します。結果として各テストの報告時間が実行全体の時間に収束し、allowance が「実際には問題ないテスト」を誤判定します。直列化することで各テストの duration が自身の処理時間を反映し、ハングしたテストだけが allowance に到達します。

## ドキュメント更新 CI

[`.github/workflows/openwiki-update.yml`](../../.github/workflows/openwiki-update.yml) は毎日 08:00 UTC および手動実行で OpenWiki を起動し、`openwiki/update` ブランチへ更新 PR を作成します。実行の要点は次の通りです。

- `fetch-depth: 0` で全履歴を取得し、OpenWiki が `openwiki/.last-update.json` の gitHead から差分を判定できるようにします。
- `persist-credentials: false` でトークンを `.git/config` に残しません。PR 作成ステップだけが `github.token` で認証します。
- `concurrency` で重複実行をキューに並べ、キャンセルではなく完了待ちにします。
- `add-paths` で `openwiki`、`AGENTS.md`、`CLAUDE.md` のみを PR 対象とし、ワークフローファイル自体は含みません。

このワークフローが生成したドキュメントは手動編集せず、ソースコードまたは既存ドキュメントを更新して OpenWiki に再生成させてください。

## 変更別のテスト選択

| 変更領域 | まず確認するテスト | 主な保護対象 |
|---|---|---|
| renderer、key、modifier、基本コンポーネント | `FineUIKitTests.swift` | 差分適用、再利用、基本 API |
| root/node/navigation の観測粒度、suspend/resume | `FineRenderScopeTests.swift` | 局所更新、非表示ツリーの停止と一回の catch-up |
| `FineState`、environment | `FineStateTests.swift`、`FineEnvironmentTests.swift` | identity をまたぐ状態、注入と伝播 |
| trait、Dynamic Type、診断 | `FineTraitTests.swift`、`FineDiagnosticsTests.swift` | trait 起因再描画、再構築理由 |
| レンダリング計測、デバッグ説明、ハイライト、トースト、signpost | `FineDebugTests.swift`、`FineDiagnosticsTests.swift` | レンダリング回数、コンポーネント名解決、注入トースト、`_viewProvider` 透過 |
| input、focus、action handler、grid math | `FineInteractionTests.swift` | 双方向 binding、target-action の再利用、境界条件 |
| UIKit コントロール（stepper、segmented、date picker、page control、progress、activity indicator、divider、text view） | `FineComponentTests.swift`、`FineSliderTests.swift` | in-place 差分適用、クランプ書き戻し、modifier リセット、placeholder 描画、focus binding |
| List/Grid の section、header/footer、行高、セル更新 | `FineListBehaviorTests.swift`、`FineUIKitTests.swift` | diffable、supplementary identity、layout 再計測 |
| `FineUI.build(to:)`、制約、container 移動 | `FineUIHostingTests.swift` | root の再親子付け、制約、trait registration |
| 性能回帰 | `RenderingPerformanceTests.swift` | 大量 list と changed-row-only の比較傾向 |

## 実装変更のチェックリスト

- `Renderable.body` を変更する: 副作用を入れず、再評価回数・メタデータ参照順序に依存しないことを確認します。`044f24d` が示すように、description 解決の余分な繰り返しは性能退化につながります。
- List/Grid を変更する: 無変更 snapshot apply を復活させないこと、header/footer を snapshot 外の補助要素として更新すること、section index ではなく identity を使うことを確認します。`8a2f4e9` と `3cb909e` がこの経緯です。
- ホストを変更する: 別コンテナへの再 build で旧制約と trait registration を残さないことを確認します。根拠は `e56854e` と `FineUIHostingTests.swift` です。
- handler を変更する: UIKit の再利用時に action や gesture を二重登録せず、最新 closure に置換することを確認します。
- 可視性ゲートを変更する: root とセルで異なる復帰経路が必要です。`FineRenderScopeTests` と List の振る舞いテストをセットで実行します。
- 計測・診断を変更する: 計測は `_update` の実行点で行うことでノード局所再レンダリングを取りこぼさない点を確認します。詳しくは[レンダリング計測とデバッグ診断](diagnostics.md)を参照してください。

関連する実装領域は[ソースマップ](../source-map.md)、設計上の処理経路は[レンダリングランタイムの構造](../architecture/overview.md)を参照してください。
