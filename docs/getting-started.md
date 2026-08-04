# はじめかた

`FineContent` の書き方、画面へのマウント、`navigationItem` の宣言までを扱います。コンポーネントの一覧は [コンポーネント](components.md)、状態の扱いは [状態とバインディング](state.md) を参照してください。

---

## content を書く

`FineContent` に適合した `@Observable` なクラスを書きます。そのオブジェクトが状態を持ち、状態から自分のビューツリーを記述します。

```swift
import FineUIKit
import Observation

@Observable
final class ToDoList: FineContent {
    var draft: String = ""
    var items: [ToDo] = []

    func add() {
        items.append(.init(title: draft))
        draft = ""
    }

    func body() -> any Renderable {
        FineStack.vertical(spacing: 8) {
            FineLabel(text: "\(self.items.count) items")
                .font(.preferredFont(forTextStyle: .headline))
                .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
            FineStack.horizontal(spacing: 8) {
                FineTextField(text: .init(self, \.draft), placeholder: "New task")
                FineButton(title: "Add") { self.add() }
                    .hugging(.defaultHigh, axis: .horizontal)
            }
            .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
            FineList(self.items) { item in
                FineLabel(text: item.title)
            }
            .onDelete { item in self.items.removeAll { $0.id == item.id } }
        }
    }
}

// 画面として使う
navigationController.pushViewController(FineContentController(ToDoList()), animated: true)
```

ハンドラが `self` をキャプチャして構いません。マウントしたコントローラが content とビューツリーの両方を所有し、content はどちらも所有しないので、循環しないからです([メモリ管理](memory.md)を参照)。

`body` 内で読んだ `@Observable` プロパティが変化すると自動で再レンダリングされます。ビューは作り直されず、互換なビューは in-place 更新されます。

```swift
FineList(sections: [
    FineListSection(id: "active", header: "Active", items: activeItems),
    FineListSection(id: "done", header: "Completed", items: completedItems),
]) { item in
    FineLabel(text: item.title)
}
.onRefresh { await viewModel.reload() }
```

---

## マウントする

マウントは `FineContentController` を通します。表示状態に応じた suspend / resume と `navigationItem` の更新を繋ぐのがこのクラスの仕事です。

既に自前のコントローラがある場合は、子コントローラとして足してください。`addChild(_:)` は親子関係を結ぶだけでビューは足さないので、UIKit の手順どおり 4 段階が要ります。

```swift
let child = FineContentController(content)
addChild(child)
containerView.addSubview(child.view)
child.view.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    child.view.topAnchor.constraint(equalTo: containerView.topAnchor),
    child.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
    child.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
    child.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
])
child.didMove(toParent: self)
```

この形なら appearance の転送も効くので、画面が隠れている間のレンダリング停止もそのまま働きます([レンダリングの挙動](rendering.md#画面が隠れている間のレンダリング))。

---

## ナビゲーション

`navigation()` を実装したいときだけ `FineContent` ではなく `FineNavigating` に適合します。`navigationItem` は画面レベルの関心事なので、区画として使う content には生えません。

`FineNavigating` に適合して `navigation()` を実装すると、`body()` と同じ observation / hot reload の流れで `navigationItem` を宣言できます。`nil` を返せば `navigationItem` には触れないので、手動管理もそのまま使えます。

ナビゲーションは `body()` とは**別の observation スコープ**で追跡されます。`navigation()` だけが読んだ値(タイトル、ボタンの `.enabled` など)が変わったときは `navigationItem` だけが更新され、ツリーの再評価・再差分は起きません。下の例で `draft` が1文字変わるたびに全画面が再差分されることはありません。

```swift
func navigation() -> FineNavigation? {
    FineNavigation(title: "ToDo (\(items.count))")
        .trailing(
            FineBarButton(systemItem: .add) { self.add() }
                .enabled(!draft.isEmpty)
        )
}
```

これは**遷移ではなく chrome の記述**です。画面遷移そのものは FineUIKit の対象外で、content は「何が起きたか」を外へ伝えるだけにします。

```swift
protocol ToDoListDelegate: AnyObject {
    func toDoList(_ list: ToDoList, didSelect item: ToDo)
}

@Observable
final class ToDoList: FineContent {
    @ObservationIgnored weak var delegate: (any ToDoListDelegate)?

    func body() -> any Renderable {
        FineList(self.items) { ... }
            .onSelect { self.delegate?.toDoList(self, didSelect: $0) }
    }
}
```

遷移を行うのは content を組み立てた側です。`Example/Counter` の `SettingsForm` と `CounterTabs.Coordinator` がこの形の実例です。

---

## 参考

- コンポーネント一覧: [コンポーネント](components.md)
- 状態・バインディング: [状態とバインディング](state.md)
- 循環参照を作らないための規則: [メモリ管理](memory.md)
- この API 形状に至った判断: [公開 API の設計判断](api-design.md)
