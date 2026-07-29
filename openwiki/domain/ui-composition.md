---
type: "Domain Guide"
title: "UI 合成、状態、environment"
description: "FineUIKit の Renderable DSL、モディファイア、FineState、FineEnvironment、ライフサイクル、UIView 拡張の利用と保守上の契約。"
tags: [api, state, environment, components, uikit]
---

# UI 合成、状態、environment

FineUIKit の利用者は `Renderable` を合成し、状態と UIKit の更新を宣言的に接続します。この DSL は[レンダリングランタイムの構造](../architecture/overview.md)の primitive・node モデルの上に成り立ち、実際にどの範囲が再描画されるかは[レンダリングワークフロー](../workflows/rendering.md)が説明します。

## コンポーネントとモディファイア

主な primitive は `FineLabel`、`FineButton`、`FineImage`、`FineStack`、`FineScrollView`、`FineTextField`、`FineToggle`、`FineSlider`、`FineList`、`FineGrid` です（[Components](../../Sources/FineUIKit/Components/)）。`FineStack` は key 付きの子を key、key なしの子を位置で再利用します。繰り返し・並べ替えをまたいで identity を維持するには `FineForEach` または `.key(_:)` を使います（[FineKeyed.swift](../../Sources/FineUIKit/FineKeyed.swift)）。

モディファイアは transparent な同一ビューへの適用と、padding/frame/lifecycle のようなホストビューを増やす適用を組み合わせます。順序は署名とビュー階層に影響するため意味を持ちます。構成を変えると再利用判定に失敗して再構築されます。

**実装時の契約:** `body` と `FineViewRepresentable.updateView` は、同じ入力から同じ UI を作り、管理するプロパティを毎回現在値へ戻してください。更新回数やメタデータ読み取り順序に依存する副作用は許容されません。

## `FineBinding` とローカル状態

`FineBinding<Value>` は `get` / `set` のペアです。`FineTextField`、`FineToggle`、`FineSlider` は UI イベントを binding へ書き戻し、レンダリング側は値が変わるときだけ UIKit に設定するため、入力カーソルの不要な破壊を避けます（[FineBinding.swift](../../Sources/FineUIKit/FineBinding.swift)、各コンポーネント実装）。

`FineState` は一時的な UI 状態をコンポーネント内に閉じ込める手段です。storage は記述値ではなく `FineNode.localState` に置かれるため、親の再レンダリングをまたいで保持されます。ただしビュー型、モディファイア署名、key のいずれかが変われば別 identity として初期化されます（[FineState.swift](../../Sources/FineUIKit/FineState.swift)）。この identity 規則は renderer の再利用条件そのものです。

## environment と trait

`FineEnvironmentValues` は型を key とする値コンテナです。`.environment(_:_:)` は子 context に値を注入し、`FineEnvironmentReader` がその値を読んでサブツリーを作ります。内側の注入が優先され、transparent なラッパーなので単独の UIView は増えません（[FineEnvironment.swift](../../Sources/FineUIKit/FineEnvironment.swift)）。

`traitCollection` も environment で渡されます。Dynamic Type、外観、サイズクラス、レイアウト方向など定義済みの 7 trait は変化で root を再評価します。それ以外の trait は読めますが、変化だけでは自動再描画されません（[FineUI.swift](../../Sources/FineUIKit/FineUI.swift)）。List/Grid は environment storage を通じ、行データが変わらなくても可視セルへ環境を反映します。セル側の実装上の注意は[UIKit 統合とコレクション](../integrations/uikit-collections.md)を参照してください。

## ライフサイクル、task、アニメーション

`.onAppear` / `.onDisappear` は window への着脱に対応し、`.task` は表示中に非同期処理を開始し、非表示時にキャンセルします。`.task(id:)` は id の変化で再起動します（[FineLifecycle.swift](../../Sources/FineUIKit/FineLifecycle.swift)）。画面単位での非表示時停止は lifecycle modifier ではなく runtime の render gate が担うため、[レンダリングワークフロー](../workflows/rendering.md)の規則に従います。

`withFineAnimation` は Task-local transaction を設定し、root、ノード、セルの更新がその transaction を参照します（[FineAnimation.swift](../../Sources/FineUIKit/FineAnimation.swift)）。停止からの catch-up は明示的に animation 無効です。

## 任意の UIKit view を接続する

組み込み外の UIView は `FineViewRepresentable` でラップします。`makeView()` は identity ごとの生成、`updateView(_:environment:)` は現在の記述を実体へ反映する場所です。representable の具象型・モディファイア署名・key が一致する場合だけ再利用されるため、別の wrapper 型で UIView を共有することはありません（[FineViewRepresentable.swift](../../Sources/FineUIKit/FineViewRepresentable.swift)）。

画面レベルの入口は `FineViewController` と `FineUI` です。コンテナ制約、キーボード回避、navigation、再ホストの振る舞いは[UIKit 統合とコレクション](../integrations/uikit-collections.md)へ、対象ファイルの一覧は[ソースマップ](../source-map.md)へ進んでください。
