---
type: "Domain Guide"
title: "UI 合成、状態、environment"
description: "FineUIKit の Renderable DSL、モディファイア、FineState、FineEnvironment、ライフサイクル、UIView 拡張の利用と保守上の契約。"
tags: [api, state, environment, components, uikit]
---

# UI 合成、状態、environment

FineUIKit の利用者は `Renderable` を合成し、状態と UIKit の更新を宣言的に接続します。この DSL は[レンダリングランタイムの構造](../architecture/overview.md)の primitive・node モデルの上に成り立ち、実際にどの範囲が再描画されるかは[レンダリングワークフロー](../workflows/rendering.md)が説明します。

## コンポーネントとモディファイア

主な primitive は `FineLabel`、`FineButton`、`FineImage`、`FineStack`、`FineScrollView`、`FineTextField`、`FineTextView`、`FineToggle`、`FineSlider`、`FineStepper`、`FineSegmentedControl`、`FineDatePicker`、`FinePageControl`、`FineProgressView`、`FineActivityIndicator`、`FineDivider`、`FineSpacer`、`FineList`、`FineGrid` です（[Components](../../Sources/FineUIKit/Components/)）。各コンポーネントの API と対応 UIKit クラスの一覧は [`README.md`](../../README.md) が正本です。`FineStack` は key 付きの子を key、key なしの子を位置で再利用します。繰り返し・並べ替えをまたいで identity を維持するには `FineForEach` または `.key(_:)` を使います（[FineKeyed.swift](../../Sources/FineUIKit/FineKeyed.swift)）。

`FineLabel`、`FineProgressView`、`FineActivityIndicator` は表示値を `@autoclosure` で受け取ります。値の読み取りはノードの `_update` 内で起きるため、表示内容の変化はそのノードだけを更新し、`body` は再評価されません（[レンダリングワークフロー](../workflows/rendering.md)のノード局所更新と同じ経路）。

モディファイアは transparent な同一ビューへの適用と、padding/frame/lifecycle のようなホストビューを増やす適用を組み合わせます。順序は署名とビュー階層に影響するため意味を持ちます。構成を変えると再利用判定に失敗して再構築されます。

**実装時の契約:** `body` と `FineViewRepresentable.updateView` は、同じ入力から同じ UI を作り、管理するプロパティを毎回現在値へ戻してください。更新回数やメタデータ読み取り順序に依存する副作用は許容されません。UIKit が例外を投げるか Auto Layout を破壊する値は、`_update` 内で拒否して既定値へフォールバックし、debug ビルドで報告します（`FineStepper` の `step` は正の有限値、`FineDivider` の `thickness` は非負有限値、`FineDatePicker` の `minuteInterval` は 60 の約数）。`FineDatePicker` は `.countDownTimer` モードをサポートしません（`Date` binding では duration を表現できないため）。

## `FineBinding` とローカル状態

`FineBinding<Value>` は `get` / `set` のペアです。`FineTextField`、`FineTextView`、`FineToggle`、`FineSlider`、`FineStepper`、`FineSegmentedControl`、`FineDatePicker`、`FinePageControl` は UI イベントを binding へ書き戻し、レンダリング側は値が変わるときだけ UIKit に設定するため、入力カーソルの不要な破壊を避けます（[FineBinding.swift](../../Sources/FineUIKit/FineBinding.swift)、各コンポーネント実装）。

UIKit が値をクランプまたは丸めるコントロール（`FineSlider`、`FineStepper`、`FineDatePicker`、`FinePageControl`）は、適用後の値を binding へ書き戻します。これにより「状態が UI に表示できない値のまま残り、毎レンダリングで再書き込みされる」ことを防ぎます。範囲の移動は上限を先に広げてから下限を狭める順序で行い、範囲全体が上へ移動したときに上限・下限が一時的に逆転しないようにします。`FineSegmentedControl` はこのパターンの例外で、範囲外の選択インデックスを破棄せず `noSegment` として表示します — 到着前のセグメントを意図として保持するためです。

`FineState` は一時的な UI 状態をコンポーネント内に閉じ込める手段です。storage は記述値ではなく `FineNode.localState` に置かれるため、親の再レンダリングをまたいで保持されます。ただしビュー型、モディファイア署名、key のいずれかが変われば別 identity として初期化されます（[FineState.swift](../../Sources/FineUIKit/FineState.swift)）。この identity 規則は renderer の再利用条件そのものです。

## environment と trait

`FineEnvironmentValues` は型を key とする値コンテナです。`.environment(_:_:)` は子 context に値を注入し、`FineEnvironmentReader` がその値を読んでサブツリーを作ります。内側の注入が優先され、transparent なラッパーなので単独の UIView は増えません（[FineEnvironment.swift](../../Sources/FineUIKit/FineEnvironment.swift)）。

`traitCollection` も environment で渡されます。Dynamic Type、外観、サイズクラス、レイアウト方向など定義済みの 7 trait は変化で root を再評価します。それ以外の trait は読めますが、変化だけでは自動再描画されません（[FineUI.swift](../../Sources/FineUIKit/FineUI.swift)）。List/Grid は environment storage を通じ、行データが変わらなくても可視セルへ環境を反映します。セル側の実装上の注意は[UIKit 統合とコレクション](../integrations/uikit-collections.md)を参照してください。

## ライフサイクル、task、アニメーション

`.onAppear` / `.onDisappear` は window への着脱に対応し、`.task` は表示中に非同期処理を開始し、非表示時にキャンセルします。`.task(id:)` は id の変化で再起動します（[FineLifecycle.swift](../../Sources/FineUIKit/FineLifecycle.swift)）。画面単位での非表示時停止は lifecycle modifier ではなく runtime の render gate が担うため、[レンダリングワークフロー](../workflows/rendering.md)の規則に従います。

`withFineAnimation` は Task-local transaction を設定し、root、ノード、セルの更新がその transaction を参照します（[FineAnimation.swift](../../Sources/FineUIKit/FineAnimation.swift)）。停止からの catch-up は明示的に animation 無効です。

## 任意の UIKit view を接続する

組み込み外の UIView は `FineViewRepresentable` でラップします。`makeView()` は identity ごとの生成、`updateView(_:environment:)` は現在の記述を実体へ反映する場所です。representable の具象型・モディファイア署名・key が一致する場合だけ再利用されるため、別の wrapper 型で UIView を共有することはありません（[FineViewRepresentable.swift](../../Sources/FineUIKit/FineViewRepresentable.swift)）。

## 保持とキャプチャ

`Renderable` の記述は使い捨ての値ですが、ノードが管理する UIView には[レンダリングランタイムの構造](../architecture/overview.md)の `FineNode` が付随し、最後に描画した primitive(記述) を保持します。`FineStack` などの `@FineBuilder` クロージャは `@escaping` で記述値に保持され、ノードがその記述を持つため、node 単位の再レンダリングが content を再評価できます。

ここから保持サイクルの制約が生まれます。クロージャがコントローラ(`self`)を強参照すると、`controller → view → node → primitive → closure → controller` が閉じ、コントローラが解放されません。重要なのは、**builder の中で `self` に一度でも触れると、内側のハンドラを `[weak self]` にしていても builder 自身が `self` を強参照**することです。実際の画面はほぼ必ず builder を経由するため、ハンドラだけを弱参照にしても足りません。

指針: クロージャには状態(`@Observable` モデル)だけをキャプチャし、`self` に触れる必要がある場合は **`self` を最初にキャプチャする最も外側の escaping クロージャ**に `[weak self]` / `[unowned self]` を付けます。`body` 直下のハンドラならそのハンドラ、builder に囲まれているならその builder です。内側のクロージャは弱参照になった `self` を引き継ぐため、重ねて capture list を書く必要はありません。

```swift
// ❌ builder が self を強参照キャプチャするためリーク
FineStack.vertical {
    FineButton(title: "Add") { [weak self] in self?.addTask() }
}

// ✅ 外側の builder に [weak self] を付けると内側は弱参照を引き継ぐ
FineStack.vertical { [weak self] in
    FineButton(title: "Add") { self?.addTask() }
}

// ✅ self に触れない(状態オブジェクトだけを読む)のが最も安全
FineStack.vertical {
    FineButton(title: "Add") { viewModel.add() }
}
```

**Swift 6.4(Xcode 27)以降**のコンパイラはこの取り違えを `#ImplicitStrongCapture`(`'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope`)として警告します。ただし**それより前のツールチェーン(Xcode 26 系を含む)では警告が出ない**ため、コンパイラ任せにせず builder 内で `self` に触れていないか自分で確認する必要があります。

各キャプチャ形状が実際に解放されるか・リークするかは `FineLeakTests` が検証しています。リークする形状は `withKnownIssue` で将来修正されたときに報告されるように書かれています。テストの選択と確認方法は[テストと運用](../operations/testing.md)を参照してください。

画面レベルの入口は `FineViewController` と `FineUI` です。コンテナ制約、キーボード回避、navigation、再ホストの振る舞いは[UIKit 統合とコレクション](../integrations/uikit-collections.md)へ、対象ファイルの一覧は[ソースマップ](../source-map.md)へ進んでください。
