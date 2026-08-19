---
type: "Domain Guide"
title: "UI 合成、状態、environment"
description: "FineUIKit の Renderable DSL、モディファイア、FineState、FineEnvironment、ライフサイクル、UIView 拡張の利用と保守上の契約。"
tags: [api, state, environment, components, uikit]
---

# UI 合成、状態、environment

FineUIKit の利用者は `Renderable` を合成し、状態と UIKit の更新を宣言的に接続します。この DSL は[レンダリングランタイムの構造](../architecture/overview.md)の primitive・node モデルの上に成り立ち、実際にどの範囲が再描画されるかは[レンダリングワークフロー](../workflows/rendering.md)が説明します。

## コンポーネントとモディファイア

主な primitive は `FineLabel`、`FineButton`、`FineImage`、`FineStack`、`FineScrollView`、`FineTextField`、`FineTextView`、`FineToggle`、`FineSlider`、`FineStepper`、`FineSegmentedControl`、`FineDatePicker`、`FinePageControl`、`FineProgressView`、`FineActivityIndicator`、`FineDivider`、`FineSpacer`、`FineList`、`FineGrid`、`FineCarousel`、`FineShelf` です（[Components](../../Sources/FineUIKit/Components/)）。各コンポーネントの API と対応 UIKit クラスの一覧は [`docs/components.md`](../../docs/components.md) が正本です。`FineStack` は key 付きの子を key、key なしの子を位置で再利用します。繰り返し・並べ替えをまたいで identity を維持するには `FineForEach` または `.key(_:)` を使います（[FineKeyed.swift](../../Sources/FineUIKit/FineKeyed.swift)）。`FineCarousel`（横ページング）と `FineShelf`（横スクロール 1 列）はセクションを持たない flat コレクションで、[UIKit 統合とコレクション](../integrations/uikit-collections.md)がその基盤（`FineFlatCollectionCoordinator`）と振る舞いを説明します。

`FineLabel`、`FineProgressView`、`FineActivityIndicator` は表示値を `@autoclosure` で受け取ります。値の読み取りはノードの `_update` 内で起きるため、表示内容の変化はそのノードだけを更新し、`body` は再評価されません（[レンダリングワークフロー](../workflows/rendering.md)のノード局所更新と同じ経路）。

モディファイアは transparent な同一ビューへの適用と、padding/frame/lifecycle のようなホストビューを増やす適用を組み合わせます。順序は署名とビュー階層に影響するため意味を持ちます。構成を変えると再利用判定に失敗して再構築されます。

**実装時の契約:** `body` と `FineViewRepresentable.updateView` は、同じ入力から同じ UI を作り、管理するプロパティを毎回現在値へ戻してください。更新回数やメタデータ読み取り順序に依存する副作用は許容されません。UIKit が例外を投げるか Auto Layout を破壊する値は、`_update` 内で拒否して既定値へフォールバックし、debug ビルドで報告します（`FineStepper` の `step` は正の有限値、`FineDivider` の `thickness` は非負有限値、`FineDatePicker` の `minuteInterval` は 60 の約数）。`FineDatePicker` は `.countDownTimer` モードをサポートしません（`Date` binding では duration を表現できないため）。

## 記述の分割（`Renderable` 型）

`body` が長くなったら、`Renderable` に適合した型（典型的には struct）へ切り出せます。引数を受け取って記述を返すだけの部品で、状態やメソッドは持たないのが `FineContent`（class）との使い分けです。コード注入の差し替え単位はシンボルであり、computed property の getter も対象なので、struct へ切り出してもホットリロードは維持されます（[Renderable.swift](../../Sources/FineUIKit/Renderable.swift) のドキュメントコメント、[`docs/components.md`](../../docs/components.md) の分割節）。

```swift
struct ToDoRow: Renderable {
    let item: ToDo
    let onToggle: @MainActor () -> Void

    var body: any Renderable {
        FineStack.horizontal(spacing: 8) {
            FineButton(title: self.item.isDone ? "☑" : "☐") { self.onToggle() }
            FineLabel(text: self.item.title)
        }
    }
}
```

分割に関する二つの実行時の振る舞いを知っておく必要があります。

- **型はビューの identity に入ります。** 解決は `body` を辿って primitive に至り、通り過ぎた型を `FineComposite` がモディファイア署名へ記録します（[レンダリングランタイムの構造](../architecture/overview.md)の差分適用の契約）。したがって `Header` と `Footer` がどちらも `FineLabel` に解決される場合でも、入れ替えればビューは作り直され、ノードの `FineState` も破棄されます。同じ型どうしなら in-place 更新です。
- **observation の粒度は切り出しても細かくなりません。** `body` は「解決される位置」で評価されるので、そこで読んだ observable の変化は解決した側のスコープを再実行します — コンテナの子なら親ノードの `_update` と builder、ルート直下なら `FineUI` のルートスコープ、セルの中なら `FineNodeHost` のスコープです。ノード単位に閉じたいときは、`FineLabel(text:)` のように値を `@autoclosure` で受け取る組み込みか、builder クロージャの内側で読んでください。上の例のように値を引数で渡す形なら、読み取りは呼び出し元で起きるのでこの問題を回避できます（[レンダリングワークフロー](../workflows/rendering.md)の root とノード局所のスコープ規則）。

状態やメソッドを持たせたくなったら、それは `Renderable` ではなく入れ子の content（`@Observable` なクラス）の役目です（[保持とキャプチャ](#保持とキャプチャ)の入れ子 content）。

## `FineBinding` とローカル状態

`FineBinding<Value>` は `get` / `set` のペアです。`FineTextField`、`FineTextView`、`FineToggle`、`FineSlider`、`FineStepper`、`FineSegmentedControl`、`FineDatePicker`、`FinePageControl` は UI イベントを binding へ書き戻し、レンダリング側は値が変わるときだけ UIKit に設定するため、入力カーソルの不要な破壊を避けます（[FineBinding.swift](../../Sources/FineUIKit/FineBinding.swift)、各コンポーネント実装）。

UIKit が値をクランプまたは丸めるコントロール（`FineSlider`、`FineStepper`、`FineDatePicker`、`FinePageControl`）は、適用後の値を binding へ書き戻します。これにより「状態が UI に表示できない値のまま残り、毎レンダリングで再書き込みされる」ことを防ぎます。範囲の移動は上限を先に広げてから下限を狭める順序で行い、範囲全体が上へ移動したときに上限・下限が一時的に逆転しないようにします。`FineSegmentedControl` はこのパターンの例外で、範囲外の選択インデックスを破棄せず `noSegment` として表示します — 到着前のセグメントを意図として保持するためです。

`FineState` は一時的な UI 状態をコンポーネント内に閉じ込める手段です。storage は記述値ではなく `FineNode.localState` に置かれるため、親の再レンダリングをまたいで保持されます。ただしビュー型、モディファイア署名、key のいずれかが変われば別 identity として初期化されます（[FineState.swift](../../Sources/FineUIKit/FineState.swift)）。この identity 規則は renderer の再利用条件そのものです。

## environment と trait

`FineEnvironmentValues` は型を key とする値コンテナです。`.environment(_:_:)` は子 context に値を注入し、`FineEnvironmentReader` がその値を読んでサブツリーを作ります。内側の注入が優先され、transparent なラッパーなので単独の UIView は増えません（[FineEnvironment.swift](../../Sources/FineUIKit/FineEnvironment.swift)）。

`traitCollection` も environment で渡されます。Dynamic Type、外観、サイズクラス、レイアウト方向など定義済みの 7 trait は変化で root を再評価します。それ以外の trait は読めますが、変化だけでは自動再描画されません（[FineUI.swift](../../Sources/FineUIKit/FineUI.swift)）。List/Grid は environment storage を通じ、行データが変わらなくても可視セルへ環境を反映します。セル側の実装上の注意は[UIKit 統合とコレクション](../integrations/uikit-collections.md)を参照してください。

## ライフサイクル、task、アニメーション

`.onAppear` / `.onDisappear` は**表示している対象**のライフサイクルに対応します（`693bb45` 以降、window の着脱ではなく記述の適用に結びます）。`.task` は表示中に対象の非同期処理を開始し、対象が終わるとキャンセルします。`.task(id:)` は id の変化で再起動します（[FineLifecycle.swift](../../Sources/FineUIKit/FineLifecycle.swift)）。セル再利用経路との関係は[UIKit 統合とコレクション](../integrations/uikit-collections.md)の行バウンド lifecycle 節が、画面単位での非表示時停止は runtime の render gate が[レンダリングワークフロー](../workflows/rendering.md)で扱います。

`withFineAnimation` は Task-local transaction を設定し、root、ノード、セルの更新がその transaction を参照します（[FineAnimation.swift](../../Sources/FineUIKit/FineAnimation.swift)）。停止からの catch-up は明示的に animation 無効です。

### 宣言的アニメーション（`.animation(_:)`）

`c634ea3` 以降、記述側で「ある状態への遷移は見る価値がある」を宣言できます（[FineAnimated.swift](../../Sources/FineUIKit/FineAnimated.swift)）。

```swift
FineImage(image: poster)
    .scale(self.isFocused ? 1.08 : 1.0)
    .animation(.spring())   // isFocused を変える経路（tap/gesture/network）すべてで animate
```

`withFineAnimation` は「mutation する側」で、`.animation(_:)` は「記述する側」で宣言します。カードが focus で膨らむなどの state-driven 動画は、変更起因を問わないため `.animation(_:)` が自然です。実アニメーションは UIKit に委ね、`_update` を `UIView.animate` 内で実行します（animatable なプロパティは動き、text/image などは即時切り替わります）。アニメーション要求は `FineRenderContext.animation` 経由で子孫へ伝播し、scheduler の別 job になる子にも届きます（`21d5fa0`）。ノード局所再描画は `FineNode.context` を再利用するため、独立した観測変更でも宣言通り animate します（[レンダリングワークフロー](../workflows/rendering.md)のノード局所更新節）。

**記述は呼び出し側の「今はやるな」に逆らえません**（`21d5fa0`）。`withFineAnimation(nil)` と `resume()` 後の catch-up render は `.disabled` となり、`.animation(_:)` を無効にします — 前者は呼び出し側の意図、後者は「画面外で起きた変化を.slide-in させない」ためです。`.animation(nil)` は包囲中のアニメーションからサブツリーを外す明示的手段で、`UIView.performWithoutAnimation` で実現します（nil でも放っておけばアニメーションしないとは限らないため）。初回描画は前の値がないため animate しません（`hasBeenUpdated` で初回かを区別、`1dca181` はアニメーションしなかった書き込みも書き込みとして数える修正です）。アニメ化されたセルの reuse は、行 identity が変わった clamp で `hasBeenUpdated` を `false` に戻し、前の行のサイズから.animate しない設計です（[UIKit 統合とコレクション](../integrations/uikit-collections.md)のセルと identity 節）。

### transform 系モディファイア（`.scale` / `.offset` / `.rotation`）

`FineTransformed`（[FineTransformed.swift](../../Sources/FineUIKit/FineTransformed.swift)）はレイヤ上で animate する composers-friendly な変形を提供します。`.scale(_:)`（中心周り）、`.scale(width:height:)`、`.offset(x:y:)`（レイアウトを崩さず移動）、`.rotation(_:)`（ラジアン）です。3 つの変形は `FineTransformSpec` に集約され、**offset → rotation → scale** の順で合成します（先に scale すると offset が scale 倍されてしまうため）。

透過ラッパを挟んで書いても互いに上書きしないよう、`_transformSpec` は `_viewProvider` と同様に全 transparent wrapper を伝播し最後に書いたものが全体を書きます（`21d5fa0`）。**値はモディファイア署名に入りません** — 署名は `transform.s/o/r`（どの変形を要求したか）だけで、値を変えても再構築しません。さもなければ animate の各フレームでビューが再構築されるためです（`aChangedTransformIsWrittenWithoutRebuildingTheView`）。変形を外すと署名が変わるため再構築され、残留しません（`addingATransformRebuildsSoTheOldOneCannotLinger`）。位置を変えてレイアウトを流したいときは `.scale`/`.offset` ではなく `padding` / `frame` を使います。

| いつ使うか | `withFineAnimation` | `.animation(_:)` |
|---|---|---|
| 宣言位置 | mutation する側 | 記述する側 |
| 起因 | 呼び出し側が制御する1回の mutation | サブツリーに触れる任意の変更（tap / gesture / network / 観測） |
| 範囲 | 1つの mutation block | 対するサブツリーの存続期間 |

## 任意の UIKit view を接続する

組み込み外の UIView は `FineViewRepresentable` でラップします。`makeView()` は identity ごとの生成、`updateView(_:environment:)` は現在の記述を実体へ反映する場所です。representable の具象型・モディファイア署名・key が一致する場合だけ再利用されるため、別の wrapper 型で UIView を共有することはありません（[FineViewRepresentable.swift](../../Sources/FineUIKit/FineViewRepresentable.swift)）。具象型の identity は `FineRepresentableAdapter` が自前で署名に入れるのではなく、解決が `FineViewRepresentable.body` を経由する時点で `FineComposite` に記録される仕組みに一本化されています（[レンダリングランタイムの構造](../architecture/overview.md)の差分適用の契約）。

**`makeView()` で `@Observable` な状態を読まないでください。** `makeView()` は identity ごとに1回しか呼ばれず、再レンダリングを起こす観測スコープの外で実行されるため、ここでの読み取りは追跡されず、値が変わってもビューは最初の値のまま更新されません。DEBUG ビルドでは [レンダリング計測とデバッグ診断](../operations/diagnostics.md) の makeView 観測診断が、値が実際に変化した時点でこれを警告します。状態は毎レンダリング呼ばれ観測スコープの内側である `updateView(_:environment:)` で読んでください。

## 保持とキャプチャ

`Renderable` の記述は使い捨ての値ですが、ノードが管理する UIView には[レンダリングランタイムの構造](../architecture/overview.md)の `FineNode` が付随し、最後に描画した primitive(記述) を保持します。`FineStack` などの `@FineBuilder` クロージャは `@escaping` で記述値に保持され、ノードがその記述を持つため、node 単位の再レンダリングが content を再評価できます。

保持サイクルは、**保持されたクロージャがマウントしたコントローラをキャプチャしたとき**に閉じます: `controller → view → node → primitive → closure → controller`。コントローラの `view` はコントローラ自身が所有しているため、外から切る契機がありません。かつての `FineViewController<State>` を継承して `body(_:)` を override する API では `self` が常にコントローラだったため、この循環は「普通に書くと起きる」ものでした。

現在の `FineContent` API は `body()` をコントローラではなく content オブジェクトのメソッドに置くことで、これを既定で安全にします。`body()` 内の `self` は **content であってコントローラではありません**。コントローラが content とツリーの両方を所有し、content はどちらも所有しないため、グラフは循環せず DAG になります。したがって `body()` や builder の中で **`self`(content)を強参照キャプチャしてもリークしません** — capture list は不要です。

```swift
@Observable
final class ToDoList: FineContent {
    var items: [ToDo] = []
    func add() { items.append(.init(title: "New")) }

    func body() -> any Renderable {
        FineStack.vertical {
            FineButton(title: "Add") { self.add() }   // self は content。強参照で安全
        }
    }
}
```

残るルールは **1 つだけ**: content は自分の controller を強参照で保持してはいけません。content が外へ伝えるもの(画面遷移の意図を含む)は `weak var delegate` に置きます。これにより、循環を閉じる参照が capture list の暗黙の規律ではなく**宣言で弱参照**になります。

```swift
protocol ToDoListDelegate: AnyObject {
    func toDoList(_ list: ToDoList, didSelect item: ToDo)
}

@Observable
final class ToDoList: FineContent {
    @ObservationIgnored weak var delegate: (any ToDoListDelegate)?
}
```

これらの判断と根拠(型メソッド化の不採用理由、hot reload のため `body()` をクロージャではなくメソッドにした理由、`FineUI` を internal にした理由、命名変更)は [`docs/api-design.md`](../../docs/api-design.md) が正本です。

### 残る限界

強参照キャプチャの安全性は content が controller へ戻らない限り成り立ちます。原理的な限界が二つあり、どちらも未修正です([`docs/api-design.md`](../../docs/api-design.md) §11)。

- **第三者オブジェクト経由の循環**: コントローラを所有する coordinator や router をクロージャがキャプチャすれば、同じ循環が作れます。Swift はクロージャのキャプチャを制限できないため、既定が安全になっただけで絶対の封じ込めではありません。
- **`.task` による解放の遅延**: task は content をキャプチャしたまま実行されるため、キャンセルを尊重しない task は content の解放を遅らせます(循環ではありません)。

各キャプチャ形状が実際に解放されるかは `FineLeakTests` が検証しています — content が `self` をすべてのハンドラ形状(builder / button / tap / lifecycle / bar button / list と grid のセル content と行コールバック / environment reader / `FineState` サブツリー / representable adapter)で強キャプチャして解放されること(`aContentCapturingItselfEverywhereIsReleased`)、content が controller を強参照するとリークすること(`aContentHoldingItsControllerLeaks`)、weak delegate であれば解放されること(`aWeakDelegatePointingAtTheControllerIsReleased`)を固定しています。テストの選択と確認方法は[テストと運用](../operations/testing.md)を参照してください。

画面レベルの入口は `FineContent` プロトコルと `FineContentController` です。`@Observable final class` を `FineContent` に適合させて `body() -> any Renderable` を実装し、`FineContentController(content)` でマウントします。`FineNavigating` に適合した content だけが `navigation() -> FineNavigation?` で画面の navigationItem を宣言します。`FineUI` は意図的に非公開で、mounting ライフサイクルは `FineContentController` を経由します。コンテナ制約、キーボード回避、navigation、ホスティングの振る舞いは[UIKit 統合とコレクション](../integrations/uikit-collections.md)へ、対象ファイルの一覧は[ソースマップ](../source-map.md)へ進んでください。
