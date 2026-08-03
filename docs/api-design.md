# 公開 API の設計判断

`FineContent` / `FineNavigating` / `FineContentController` という現在の公開 API が、なぜこの形なのかを記録します。内部構造そのものは [内部アーキテクチャ](architecture.md)、使い方は [README](../README.md) を参照してください。

ここに書いてあるのは**判断とその根拠**です。実測で確かめた事実には、確かめ方も併記しています。同じ問いが再び出たときに、議論をやり直さずに済むように。

---

## 0. 出発点となった問題

ランタイムは、記述が抱えたクロージャをビューの生存期間ずっと保持します。

- `FineNode.primitive` が、そのビューを最後にレンダリングした記述を持つ（`FineNodeScheduler.renderChild`）
- `FineList` / `FineGrid` の coordinator が `content` / `onSelect` / `onDelete` / `onRefresh` を持つ
- `FineTapHandlerBox`、`FineLifecycleView`、`FineNodeHost`、representable の adapter も同様

そしてビューは、それをマウントしたコントローラのものです。したがって記述がコントローラをキャプチャすると、

```
controller → view → node → closure → controller
```

という循環ができ、**外から切る契機がありません**。コントローラの `view` はコントローラ自身が所有しているので、誰かが解放してくれることがない。

かつての API は `FineViewController<State>` を継承して `body(_ state:)` を override する形だったため、`self` が常にスコープにあり、この循環は「普通に書くと起きる」ものでした。README は「`self` を最初にキャプチャする最も外側の escaping クロージャに `[weak self]`」という規律で対処していましたが、規律で守るものは破られます（実際 `Example/ToDo` が破っていました）。

---

## 1. 記述をコントローラから引き剥がす

**決定**: `body()` はコントローラではなく、状態を持つ別のオブジェクト（`FineContent`）のメソッドにする。

```swift
@Observable
final class ToDoList: FineContent {
    var items: [ToDo] = []
    func add() { ... }

    func body() -> any Renderable {
        FineButton(title: "Add") { self.add() }   // capture list は不要
    }
}
```

**なぜ安全か**: キャプチャされるのが content になり、コントローラが content とツリーの**両方**を所有し、content はどちらも所有しません。グラフは循環せず DAG です。

**実測**: content の `body` が `self` を強参照キャプチャした状態で、コントローラと content の両方が解放されることを確認しています。逆に content が controller を強参照すると `controller → content → controller` で循環します（`FineLeakTests.aContentHoldingItsControllerLeaks` が境界として固定）。

### 検討して採らなかった案

**型メソッド化**（`open class func body(_ state:_ host:)`）。`self` をスコープから消せるので、キャプチャは**コンパイル時に不可能**になります。保証としてはこちらが強い。

採らなかった理由は、これが「`body` をコントローラに置いた」ことへの対症療法だったからです。置き場所を変えれば、型メソッドも weak proxy も compile fixture も不要になり、さらに**インスタンス状態とメソッドが戻ってきます**。型メソッド案は既に「振る舞いは State に置け」と要求していたので、その State に `body` を移すだけの差でした。

失ったのはコンパイル時の保証です。残るルールは 1 つだけになりました。

> **content は自分の controller を強参照で保持してはいけない。**

**runtime 側の teardown**（画面が閉じたら保持を解く）も検討しましたが、破棄の契機を appearance コールバックから推測する方法が **iPadOS で破綻します**。`isMovingFromParent` は「消える」ではなく「親から外れる」しか意味しないため、`UISplitViewController` の collapse / expand（再親付け）や `UIPageViewController` の先読みと区別がつきません。回転しただけで生きているコントローラの teardown が走ります。

---

## 2. `body()` はメソッドであり、クロージャではない

**決定**: `FineContent` は `body()` を要求するプロトコルにする。クロージャを受け取る初期化子を公開 API に置かない。

**理由はホットリロード**です。ストアドクロージャは生成時に記述が確定するため、コード注入では差し替えられません。メソッドなら vtable 経由で差し替わります。

**実測（Swift 6.4 / Xcode 27）**:

| 確かめたこと | 結果 | 確かめ方 |
|---|---|---|
| `class func` は vtable スロットに載るか | 載る。instance method と同じ `sil_vtable`、呼び出しは `class_method` | `swiftc -emit-sil` |
| injection は IsInstance で弾かないか | 弾かない。スロットを位置で総なめし、injectable 接尾辞に `Z`(static) を含む | InjectionLite `Reloader.swift` |
| class が protocol に適合した場合 | **protocol witness thunk 自身が `class_method` を発行**する。`any FineContent` 経由でも vtable に落ちる | `swiftc -emit-sil` |
| struct のメソッドは | `function_ref` / `witness_method`。interposition 依存（`-Xlinker -interposable`）になる | `swiftc -emit-sil` |

3 行目が `FineContent` を protocol にできる根拠です。値型で設計していたら、利用者にリンカフラグを要求することになっていました。

---

## 3. 画面遷移はライブラリの対象外

**決定**: push / present をライブラリが扱わない。content は「何が起きたか」を外へ伝えるだけにする。

**理由**:

- UIKit の遷移面（presentation style の適応、`UISplitViewController`、popover、detent、interactive dismissal、state restoration）はレンダリングランタイム本体より大きい
- 遷移を所有すると、既存アプリの 1 画面だけに導入することができなくなる
- エコシステムに合意がない（coordinator / router / TCA / `NavigationStack`）。SwiftUI 自身、navigation が最も作り直されている領域

**代わりに推奨する形**: `weak var delegate`。

```swift
protocol ToDoListDelegate: AnyObject {
    func toDoList(_ list: ToDoList, didSelect item: ToDo)
}

@Observable
final class ToDoList: FineContent {
    @ObservationIgnored weak var delegate: (any ToDoListDelegate)?
}
```

`weak` が**宣言側に 1 回**書かれるだけで、利用側にキャプチャの規律が残りません。クロージャプロパティでも書けますが、その場合は合成のルートで `[weak controller]` を守る必要が出ます — コンパイル時の保証を捨てた直後に、同じ種類の規律を再導入することになるので、既定にはしていません。

**観測可能な状態で遷移意図を表す形**（`var selected: Item?` を外から observe する）は、宣言的な表示状態には向きますが**イベントには向きません**。状態はイベントではないので、遷移後に手動でリセットが要り、observation は同値の変更を合体させます。

### 境界線として再考の余地があるもの

「シートが出ている」のような**状態駆動のモーダル表示**は、フローではなく画面の宣言的な状態です。ライブラリが表現できないと「状態はあるが表示は手続き的に出す」コードになり、状態と表示がずれるバグ — FineUIKit が存在して防いでいるバグそのもの — を招きます。ただし `.sheet(item:)` 相当は dismiss まで面倒を見て初めて価値が出るため、現時点では扱っていません。

---

## 4. `navigation()` を `FineNavigating` に分離

**決定**: `navigation()` は `FineContent` ではなく、それを継承した `FineNavigating` に置く。

`navigationItem` は画面レベルの関心事です。サブビューへレンダリングされた content には書き込む先の bar がないので、`FineContent` に置くと「実装しても黙って何も起きないメソッド」を生やせてしまいます。分離すれば、そもそも生えません。

**なお適合は禁止されていません**。適合したうえで画面でない位置にマウントすることは可能で、その場合 `navigation()` が効かないだけです。分離は「意味を持てない場所にメソッドを生やさない」ためであって、適合を防ぐためではありません。

**遷移との切り分け**: `navigation()` は chrome の**記述**であって遷移ではありません。バーボタンの action は他のハンドラと同じく意図を外へ伝えるだけです。

**実測**: `navigation()` を content に置いても、`body()` とは別の observation スコープが保たれます。タイトルだけの変更で `body()` は再評価されません。

---

## 5. `FineUI` は internal

**決定**: ランタイムを公開しない。マウントは `FineContentController` だけ。

**理由 1 — 可逆性の非対称**: `internal → public` は source-compatible、逆は破壊的。現時点で `FineUI` の利用者は `FineContentController` とテストだけなので、閉じておくのが可逆な選択です。

**理由 2 — ガードレールのない罠**: 手でマウントすると suspend / resume の配線も自分で持つことになり、忘れると**画面が隠れても黙って再差分され続けます**。その配線が正しく書かれている唯一の場所が `FineContentController` です。

公開しないことで失うのは「任意のビューへのマウント」ですが、自前のコントローラがある場合は `FineContentController` を子として足せます（containment の 4 段階が必要）。

---

## 6. 命名

| 変更 | 理由 |
|---|---|
| `FineScreen`(proxy) → `FineHost` → 廃止 | 当初コントローラへの weak proxy を `FineScreen` と呼んでいたが、画面そのものを表す型が必要になったため改名。遷移を対象外にした時点で proxy 自体が不要になり削除 |
| `FineScreen`(protocol) → `FineContent` | 「1 画面 = 1 インスタンス」を含意してしまう。実際には任意のビューにマウントでき、入れ子にもできる |
| `FineScreenController` → `FineContentController` | ランタイムが internal になり唯一のマウント手段となった以上、用途の一方だけを名乗るのは恣意的。さらに「自前のコントローラに子として足す」という**画面でない使い方を自ら文書化している**ため |

結果として、公開 API から `Screen` という語は消えました。状態の寿命は「マウントされている間」であって「画面である間」ではない、という結論と一致します。

---

## 7. 入れ子と identity

**ランタイムが管理するもの**: ビューとノードの identity。型 + モディファイア署名 + `key` が一致したときだけ in-place 更新し、それ以外は作り直す。`FineState` はノードに紐づくので、identity が変われば捨てられます。

**ランタイムが管理しないもの**: 入れ子にした content オブジェクトの identity。親が stored property として所有し、`child.body()` を自分の記述に差し込むだけです。

**子は `FineContent` に適合する必要がありません**。ランタイムは子オブジェクトの存在を知らず、`child.body()` はただのメソッド呼び出しだからです。適合が要るのはマウント点だけ。

**実測した非対称**: 親が `if showsChild { child.body() }` で子を出し入れすると、

```
初期            → "child 7 local 1"   （子の taps=7、FineState の counter=1）
showsChild=false → 消える
showsChild=true  → "child 7 local 0"   ← 子オブジェクトの状態は残り、FineState は破棄される
```

同じサブツリーの中で 2 種類の状態が別の運命をたどります。子の状態を捨てたければ、親が子を差し替えてください（そのため `let` ではなく `var` にしておく必要があります）。

**粒度は階層を貫通します**。observation の追跡スコープは「どのオブジェクトを読んだか」ではなく「**どこで読んだか**」で決まるので、子の状態変更で親の `body()` は再評価されません。

---

## 8. 状態の置き場所

| | 寿命 | 用途 |
|---|---|---|
| store / model | 画面より長い。外から注入、共有可 | ドメイン状態 |
| **content** | マウントされている間 | その区画固有の UI 状態 |
| `FineState` | ビューの identity と同じ | 局所的な UI 状態（行の展開など） |

content が store を持つかどうかは、ただのプロパティの持ち方です。FineUIKit は「model」という概念を持ちません。

「メソッドが要るか」が `FineState` と入れ子オブジェクトの実用的な分岐点です。`FineState` はバインディングしか渡せないので、`clear()` のような操作を持たせたいなら入れ子にします。

---

## 9. 残る限界

**第三者オブジェクト経由の循環**: コントローラを所有する coordinator や router をクロージャがキャプチャすれば、同じ循環は作れます。Swift はクロージャのキャプチャを制限できないため、ここは原理的な限界です。デフォルトが安全になっただけで、絶対の封じ込めではありません。

**`.task` による解放の遅延**: task は content をキャプチャしたまま実行されるので、キャンセルを尊重しない task は content の解放を遅らせます（循環ではありません）。`FineLeakTests.controllerShownInAWindowIsReleasedAfterTheWindowLetsGo` が、即座ではなく数ターン後に解放されることを前提に書かれているのはこのためです。

---

## 参考

- 使い方: [README](../README.md)
- 内部構造: [内部アーキテクチャ](architecture.md)
- 検証: `Tests/FineUIKitTests/FineLeakTests.swift` — ランタイムが保持するすべての形（builder / button / tap / lifecycle / bar button / list と grid のセル content と行コールバック / environment reader / `FineState` サブツリー / representable adapter）を押さえています
