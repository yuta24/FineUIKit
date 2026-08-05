# メモリ管理

キャプチャの安全性、守るべき唯一のルール、状態の置き場所、入れ子、残る限界を扱います。

---

## 何がクロージャを保持するか

`FineButton` の `action` や `FineStack` の builder といったクロージャは、node 単位の再レンダリングのためにビュー側(`FineNode`)に保持されます。`FineList` / `FineGrid` の coordinator も cell content や `onSelect` を保持します。**つまり記述が抱えたクロージャは、ビューが生きている間ずっと生き続けます。**

ビューは hosting controller のものです。ここから 2 つのことが導かれます。

- **content をキャプチャするのは安全**。controller が content とツリーの両方を所有し、content はどちらも所有しないので、グラフは循環しません
- **controller をキャプチャすると循環します**。`controller → view → node → クロージャ → controller` を切るものがありません

```swift
func body() -> any Renderable {
    FineStack.vertical {
        // ✅ self は content。capture list は要りません
        FineButton(title: "Add") { self.add() }
        FineLabel(text: "\(self.items.count)")
    }
}
```

`[weak self]` を書く必要はありません。書く場所がないからです。`body()` は escaping なクロージャの中で `self.` を明示するよう Swift が要求するので、**何をキャプチャしているかは常に目に見えます**。

---

## 守るべきルールは 1 つ

> **content は自分の controller を強参照で保持してはいけない。**

外へ何かを伝えるときは、クロージャプロパティではなく **`weak var delegate`** を使ってください。`weak` が宣言側に 1 回書かれるだけで、利用側にキャプチャのルールが残りません。

```swift
// ✅ 推奨: weak が宣言に 1 回だけ
@Observable
final class ToDoList: FineContent {
    @ObservationIgnored weak var delegate: (any ToDoListDelegate)?
}

// ⚠️ クロージャでも書けますが、合成する側が毎回 [weak] を守る必要があります
screen.onSelect = { [weak controller] item in controller?.push(...) }
// これを忘れると controller → content → クロージャ → controller で循環します
```

---

## 状態の置き場所

| | 寿命 | 用途 |
|---|---|---|
| store / model | 画面より長い。外から注入、共有可 | ドメイン状態 |
| **content** | マウントされている間 | その区画固有の UI 状態 |
| `FineState` | ビューの identity と同じ | 局所的な UI 状態（行の展開など） |

content が store を持つかどうかは、ただのプロパティの持ち方です。FineUIKit は「model」という概念を持ちません。

---

## 入れ子

content は入れ子にできます。**子は `FineContent` に適合する必要すらありません** — ランタイムは子オブジェクトの存在を知らず、`child.body()` はただのメソッド呼び出しだからです。親が子を所有し、自分の記述に差し込みます。細粒度の再レンダリングは階層を貫通します（子の状態変更で親の `body()` は再評価されません）。

ランタイムが管理するのはビューとノードの identity です。そのため**条件付きで隠したサブツリーの `FineState` は捨てられますが、子オブジェクト自身の状態は親が持っているので残ります**。リセットしたければ親が子を差し替えてください。

記述だけを切り出した `Renderable` の struct（[コンポーネント](components.md#renderable-で記述を分割する)）は、この所有関係に何も足しません。ランタイムは struct 自身を identity として持ちませんが、**その `body` が作ったクロージャは他の記述と同じくビューの寿命ぶん保持されます**（冒頭の一覧のとおり）。切り出したからといって早く解放されるわけではない、という意味です。`ToDoRow(item:) { self.toggle(item) }` のように content の `self` をキャプチャして構いません — 循環しない理由も上と同じで、キャプチャされるのが content だからです。

---

## 残る限界

**controller を所有する第三者のオブジェクト**（coordinator、router）をクロージャがキャプチャすれば、同じ循環は作れます。Swift はクロージャのキャプチャを制限できないため、ここは原理的な限界です。

`.task` は content をキャプチャしたまま実行されるので、**キャンセルを尊重しない task は content の解放を遅らせます**（循環ではありません）。

各パターンが実際に解放されるかは `FineLeakTests` が検証しています。「content が controller を持つとリークする」という境界も、テストとして固定してあります。

---

## 参考

- この所有関係を選んだ理由: [公開 API の設計判断](api-design.md)
