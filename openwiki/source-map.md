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
| `Renderable.swift`, `FineRenderer.swift`, `FineComposite.swift`, `FineResolvedRenderable.swift`, `FineStructural.swift` | 記述契約、primitive 解決（一度限りキャッシュ）、composite 型の署名記録、`if`/`for` 構造スロット、再利用判定 | [レンダリングランタイムの構造](architecture/overview.md) |
| `FineNode.swift`, `UIView+Fine.swift`, `FineIdentityScopedView.swift` | UIView に付随する identity・状態・世代、記述 scoped の view 状態（キーボード/scroll/lifecycle） | [UI 合成と状態](domain/ui-composition.md) |
| `FineNodeScheduler.swift`, `FineRenderContext.swift` | ノード局所観測と context 伝播（セル専用 scheduler 含む） | [レンダリングワークフロー](workflows/rendering.md) |
| `FineUI.swift`, `FineRenderGate.swift`, `FineObservedScope.swift`, `FineHotReload.swift`(DEBUG) | root render、停止・復帰、navigation 用観測、コード注入の backend seam（`FineHotReloadBackend`、`FineUI` は internal） | [レンダリングワークフロー](workflows/rendering.md) |
| `FineContent.swift`, `FineContentController.swift` | Public なエントリ: `FineContent`/`FineNavigating` プロトコルと `FineContentController` | [UI 合成と状態](domain/ui-composition.md) |
| `FineNodeHost.swift` | List/Grid セルと supplementary view の局所レンダー、行バウンド lifecycle と identity 破棄 | [UIKit 統合とコレクション](integrations/uikit-collections.md) |
| `FineDiagnostics.swift`, `FineDebugHighlight.swift`, `FineDebugToast.swift`, `FineSignpost.swift`, `UIView+FineDebug.swift` | レンダリング計測、ハイライト、注入トースト、signpost、更新理由/所要時間、デバッガ内省 | [レンダリング計測とデバッグ診断](operations/diagnostics.md) |

## DSL、状態、スタイル

| ファイル群 | 担当 | 詳細 |
|---|---|---|
| `FineBuilder.swift`, `FineKeyed.swift`, `FineBinding.swift` | 合成、identity、双方向 binding、`buildEither`/`buildOptional`/`buildArray` の構造スロット割当 | [UI 合成と状態](domain/ui-composition.md) |
| `FineState.swift`, `FineEnvironment.swift` | 局所状態と環境値 | [UI 合成と状態](domain/ui-composition.md) |
| `FineStyled.swift`, `FinePadded.swift`, `FineFramed.swift`, `FineConstrained.swift`, `RenderableModifiers.swift` | transparent / host 型モディファイア（`FineResolvedRenderable` で primitive をキャッシュ） | [UI 合成と状態](domain/ui-composition.md) |
| `FineLifecycle.swift`, `FineAnimation.swift`, `FineAnimated.swift`, `FineTransformed.swift` | appearance、task、transaction、宣言的 `.animation(_:)`、`.scale`/`.offset`/`.rotation` | [UI 合成と状態](domain/ui-composition.md) |
| `FineViewRepresentable.swift` | 組み込み外 UIView の拡張点 | [UIKit 統合とコレクション](integrations/uikit-collections.md) |

## UIKit コンポーネントと画面統合

| ファイル群 | 担当 | 詳細 |
|---|---|---|
| `FineContent.swift`, `FineContentController.swift`, `FineNavigation.swift` | `FineContent`/`FineNavigating` プロトコル、画面ホスト、bar button | [UIKit 統合とコレクション](integrations/uikit-collections.md) |
| `Components/FineStack.swift`, `FineLabel.swift`, `FineButton.swift`, `FineImage.swift` | 基本レイアウト・表示・操作 | [UI 合成と状態](domain/ui-composition.md) |
| `Components/FineTextField.swift`, `FineTextView.swift`, `FineToggle.swift`, `FineSlider.swift`, `FineStepper.swift` | binding、focus、入力制御 | [UI 合成と状態](domain/ui-composition.md) |
| `Components/FineSegmentedControl.swift`, `FineDatePicker.swift`, `FinePageControl.swift` | binding ベースの選択コントロール | [UI 合成と状態](domain/ui-composition.md) |
| `Components/FineProgressView.swift`, `FineActivityIndicator.swift`, `FineDivider.swift`, `FineSpacer.swift` | 表示・区切り・余白（autoclosure または非 binding） | [UI 合成と状態](domain/ui-composition.md) |
| `Components/FineList.swift`, `FineGrid.swift`, `FineCollection.swift` | diffable data source、sections、セル、layout、共有コーディネータと `FineSection` | [UIKit 統合とコレクション](integrations/uikit-collections.md) |
| `Components/FineCarousel.swift`, `FineShelf.swift` | 横ページング / 横スクロール 1 列、`FineFlatCollectionCoordinator` ベースの flat コレクション | [UIKit 統合とコレクション](integrations/uikit-collections.md) |
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
- `FineCompositeTests.swift`: composite 型の identity。同じ型なら in-place、別の型なら作り直し、組み込みだけのツリーには composite 署名が付かないこと。
- `FineCompositeObservationTests.swift`: root 直下の composite が読む observable が正しくトラッキングされること（解決を `withObservationTracking` の内側に保つ回帰）。
- `FineStructuralIdentityTests.swift`: `if`/`for` の構造スロット。分岐消滅でも兄弟 view と `FineState` 保持、key が reorder を追う、switch/else-if の同一スロット共用、生成 slot 衝突の非 assert、transparent modifier が隠したスロットの子区別。
- `FineMakeViewObservationTests.swift`(DEBUG): `makeView()` 内の状態読み取り報告。renderer / scheduler 両経路、両場所読み取りの報告、`updateView` 読み取りの非報告、無読み取りツリーの無音。`@Suite(.serialized)`（handler がプロセス単位のため）。
- `FineResolutionTests.swift`: 透過モディファイアが 1 render で primitive を一度だけ解決すること、root prime による root 直下 composite の観測。
- `FineCellGranularityTests.swift`: セル内ノード局所観測（1 値変更が 1 ノードだけ更新）、ホストスコープ停止値の resume 復帰。
- `FineCellReuseTests.swift`: `FineState` が行をまたがない、同一行再 render は状態保持。
- `FineLifecycleIdentityTests.swift`: 行バウンド lifecycle。行切替で appear/disappear/.task が切替、再利用前でも前行の task をキャンセル、可視コンテナへ追加した子の `onAppear`。
- `FineCellReuseViewStateTests.swift`: 再利用でのキーボード/scroll/focus binding 書き戻し。handover で全解放、park で scroll 位置保持。
- `FineUpdateReasonTests.swift`: `UpdateReason`（`.initial`/`.parent`/`.observation`/`.injection`）、catch-up とセルの自己復帰、子へ理由が漏れない、理由が次回 render に漏れない、所要時間記録、`fineFormatted` 単位選択、`fineDebugDescription` の `because` 含有。
- `FineDeclarativeAnimationTests.swift`: `.animation(_:)` の観測起因 animate、disabled 優先、catch-up 非アニメ、reuse 新行非 animate、継承 duration 上書き、`hasBeenUpdated` 順序、transform 合成と値変化の署名非依存。
- `FineHotReloadTests.swift`(DEBUG): `FineHotReloadBackend` seam、shipping 後端の通知名固定、全ツリー到達、解放で登録解放。
- `FineCollectionSharingTests.swift`: 1 つの `FineSection` 値が List/Grid 両方に描画、`FineSupplementaryKind` の elementKind 往復、header/footer identity 区別。
- `FineCollectionPrefetchTests.swift`: List/Grid の `.onPrefetch` / `.onCancelPrefetch`。ハンドラがあるときだけ prefetchDataSource 設定、cancel 単独は何もしない、reorder 後の要素解決、離脱要素の忘却、reorder 後 cancel の無関係行除外、解決不能 index の非報告。
- `FineCarouselShelfTests.swift`: carousel のページング・双方向 binding・範囲外 clamp 報告・pending page・ジェスチャ中書き込み遅延・diff。shelf の幅・fractional peek・幅変更 relays・select・prefetch 転送。

テストの実行方法と変更別選択は[テストと運用](operations/testing.md)が正本です。内部設計のより詳細な一次資料は [`docs/architecture.md`](../docs/architecture.md)、公開 API の形状に至った判断と根拠は [`docs/api-design.md`](../docs/api-design.md)、公開 API の例は [`README.md`](../README.md) と [`docs/getting-started.md`](../docs/getting-started.md) にあります。
