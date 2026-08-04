---
type: "Source Map"
title: "FineUIKit ソースマップ"
description: "FineUIKit のランタイム、DSL、UIKit コンポーネント、テスト、既存設計資料へ短時間で移動するための領域別地図。"
tags: [source-map, navigation, swift, uikit]
---

# FineUIKit ソースマップ

このページは実装へ戻るための案内です。概念と判断は[クイックスタート](quickstart.md)から各ページへ進み、ここでは重複説明をせず担当境界を示します。

## ランタイムと再調停

| ファイル群 | 担当 | 詳細 |
|---|---|---|
| `Renderable.swift`, `FineRenderer.swift` | 記述契約、primitive 解決、再利用判定 | [レンダリングランタイムの構造](architecture/overview.md) |
| `FineNode.swift`, `UIView+Fine.swift` | UIView に付随する identity・状態・世代 | [UI 合成と状態](domain/ui-composition.md) |
| `FineNodeScheduler.swift`, `FineRenderContext.swift` | ノード局所観測と context 伝播 | [レンダリングワークフロー](workflows/rendering.md) |
| `FineUI.swift`, `FineRenderGate.swift`, `FineObservedScope.swift` | root render、停止・復帰、navigation 用観測（`FineUI` は internal） | [レンダリングワークフロー](workflows/rendering.md) |
| `FineContent.swift`, `FineContentController.swift` | Public なエントリ: `FineContent`/`FineNavigating` プロトコルと `FineContentController` | [UI 合成と状態](domain/ui-composition.md) |
| `FineNodeHost.swift` | List/Grid セルと supplementary view の局所レンダー | [UIKit 統合とコレクション](integrations/uikit-collections.md) |
| `FineDiagnostics.swift`, `FineDebugHighlight.swift`, `FineDebugToast.swift`, `FineSignpost.swift`, `UIView+FineDebug.swift` | レンダリング計測、ハイライト、注入トースト、signpost、デバッガ内省 | [レンダリング計測とデバッグ診断](operations/diagnostics.md) |

## DSL、状態、スタイル

| ファイル群 | 担当 | 詳細 |
|---|---|---|
| `FineBuilder.swift`, `FineKeyed.swift`, `FineBinding.swift` | 合成、identity、双方向 binding | [UI 合成と状態](domain/ui-composition.md) |
| `FineState.swift`, `FineEnvironment.swift` | 局所状態と環境値 | [UI 合成と状態](domain/ui-composition.md) |
| `FineStyled.swift`, `FinePadded.swift`, `FineFramed.swift`, `FineConstrained.swift`, `RenderableModifiers.swift` | transparent / host 型モディファイア | [UI 合成と状態](domain/ui-composition.md) |
| `FineLifecycle.swift`, `FineAnimation.swift` | appearance、task、transaction | [UI 合成と状態](domain/ui-composition.md) |
| `FineViewRepresentable.swift` | 組み込み外 UIView の拡張点 | [UIKit 統合とコレクション](integrations/uikit-collections.md) |

## UIKit コンポーネントと画面統合

| ファイル群 | 担当 | 詳細 |
|---|---|---|
| `FineContent.swift`, `FineContentController.swift`, `FineNavigation.swift` | `FineContent`/`FineNavigating` プロトコル、画面ホスト、bar button | [UIKit 統合とコレクション](integrations/uikit-collections.md) |
| `Components/FineStack.swift`, `FineLabel.swift`, `FineButton.swift`, `FineImage.swift` | 基本レイアウト・表示・操作 | [UI 合成と状態](domain/ui-composition.md) |
| `Components/FineTextField.swift`, `FineTextView.swift`, `FineToggle.swift`, `FineSlider.swift`, `FineStepper.swift` | binding、focus、入力制御 | [UI 合成と状態](domain/ui-composition.md) |
| `Components/FineSegmentedControl.swift`, `FineDatePicker.swift`, `FinePageControl.swift` | binding ベースの選択コントロール | [UI 合成と状態](domain/ui-composition.md) |
| `Components/FineProgressView.swift`, `FineActivityIndicator.swift`, `FineDivider.swift`, `FineSpacer.swift` | 表示・区切り・余白（autoclosure または非 binding） | [UI 合成と状態](domain/ui-composition.md) |
| `Components/FineList.swift`, `FineGrid.swift` | diffable data source、sections、セル、layout | [UIKit 統合とコレクション](integrations/uikit-collections.md) |
| `UIControl+FineHandlers.swift`, `FineTapGesture.swift` | 再利用可能な `@MainActor` イベント handler | [テストと運用](operations/testing.md) |

## テストと既存資料

- `Tests/FineUIKitTests/FineUIKitTests.swift`: 基本レンダリング、コンポーネント、List/Grid の広範な回帰テスト。
- `FineRenderScopeTests.swift`: root・node・navigation・セルの観測スコープと render gate。
- `FineListBehaviorTests.swift`: section、supplementary view、環境、セル高の振る舞い。
- `FineUIHostingTests.swift`: `build(to:)`、container 移動、制約、trait。
- `FineInteractionTests.swift`: binding、focus、handler、Grid の計算。
- `FineStateTests.swift`、`FineEnvironmentTests.swift`、`FineTraitTests.swift`、`FineDiagnosticsTests.swift`: 専用のドメイン回帰。
- `FineDebugTests.swift`: レンダリング回数、デバッグ説明、ハイライト、注入トースト、`_viewProvider` のモディファイア透過。
- `FineComponentTests.swift`: UIKit コントロール（stepper、segmented、date picker、page control、progress、activity indicator、divider、text view）の in-place 差分適用、クランプ書き戻し、modifier リセット。
- `FineSliderTests.swift`: slider のクランプ書き戻しと範囲移動。
- `RenderingPerformanceTests.swift`: 性能の傾向確認。
- `FineLeakTests.swift`: handler/builder のキャプチャ形状による保持サイクル(リーク)と解放の検証。

テストの実行方法と変更別選択は[テストと運用](operations/testing.md)が正本です。内部設計のより詳細な一次資料は [`docs/architecture.md`](../docs/architecture.md)、公開 API の形状に至った判断と根拠は [`docs/api-design.md`](../docs/api-design.md)、公開 API の例は [`README.md`](../README.md) にあります。
