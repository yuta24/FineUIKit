# 状態とバインディング

双方向バインディング、フォーカス管理、コンポーネント内のローカル状態、サブツリーへ暗黙に伝播する environment を扱います。

---

## 双方向バインディング

```swift
FineTextField(text: .init(viewModel, \.draft))   // ReferenceWritableKeyPath から生成
FineToggle(isOn: .init(item, \.completed))
FineSlider(value: .init(settings, \.volume), in: 0...10)
FineStepper(value: .init(settings, \.servings), in: 1...20, step: 1)
FineSegmentedControl(titles: ["All", "Active", "Done"], selection: .init(viewModel, \.filter))
FineDatePicker(selection: .init(item, \.dueDate), in: .now ... .distantFuture)
    .datePickerMode(.date)
FinePageControl(numberOfPages: viewModel.pages.count, currentPage: .init(viewModel, \.page))

FineTextField(text: .init(viewModel, \.draft), placeholder: "New task")
    .returnKeyType(.done)
    .onSubmit { viewModel.add() }

FineTextView(text: .init(item, \.memo), placeholder: "Memo")   // 複数行。内容に合わせて伸びる
```

`FineBinding` は `get` / `set` のペアです。`get` はレンダリング中(observation スコープ内)に評価されるため、バインド先の変更で自動的に再レンダリングされます。UI 側の変更は `set` を通じて状態へ書き戻され、「現在値と異なるときだけビューに書く」ガードにより入力中のカーソルは保持されます。

**クランプ・丸めの書き戻し**: `FineSlider` / `FineStepper` / `FineDatePicker` / `FinePageControl` は、UIKit 側で値がクランプ(レンジ外)・丸め(`minuteInterval` など)されたとき、**適用後の値をバインディングへ書き戻します**。状態は常に「画面に出ている値」と一致するため、範囲外の値が状態にだけ残り続けることはありません(例: `pages` が減ったあとの `page` が末尾を超えたままにならない)。書き戻しは1回で収束し、以降の再レンダリングは発生しません。

`FineSegmentedControl` だけは例外で、`selection` がセグメント範囲外のときは「未選択」を表示するだけで状態は書き換えません(セグメントを後から流し込む間、選択の意図を消さないため)。

---

## フォーカス管理

`FineTextField` / `FineTextView` の `.focused(_:)` に `FineBinding<Bool>` を渡すと、first responder を状態から駆動できます。`true` を書くとフォーカス(キーボード表示)、`false` を書くと解除。ユーザー操作によるフォーカスの出入りもバインディングへ書き戻されます。

```swift
@Observable
final class FormModel {
    var name = ""
    var isNameFocused = false
}

FineTextField(text: .init(model, \.name), placeholder: "Name")
    .focused(.init(model, \.isNameFocused))

FineButton(title: "Edit") { model.isNameFocused = true }
```

ビューが window に載る前の描画では、載った直後にフォーカスが適用されます。

---

## ローカル状態

外部の `@Observable` に持たせるまでもない一過性の UI 状態(開閉トグル、ローカルな下書きなど)は `FineState` でコンポーネント内に閉じ込められます。SwiftUI の `@State` / React の `useState` に相当します。

```swift
FineState(false) { isExpanded in
    FineStack.vertical(spacing: 8) {
        FineButton(title: isExpanded.value ? "Collapse" : "Expand") {
            isExpanded.value.toggle()
        }
        if isExpanded.value {
            FineLabel(text: "Details")
        }
    }
}
```

状態は `FineBinding` として渡されます。`get` は読んだノードの observation スコープで追跡されるため、`value` を書き換えるとそのノードだけが再レンダリングされ、`body` 全体は再評価されません。

状態はツリー(ビューを所有する `FineNode` 要素)に生き、**親の再レンダリングをまたいで保持**されます。`.key(_:)` / `FineForEach` で安定した identity を与えれば、並び替え・挿入・削除をまたいでも同じ論理項目の状態が追従します。ビューが作り直される(ビュー型・モディファイア署名・key のいずれかが変わる)ときは初期値から作り直されます。

---

## Environment

テーマ・ロケール・依存オブジェクトのようなアンビエントな値は、`body` の引数で配り歩かずに `.environment(_:_:)` でサブツリーへ暗黙に伝播できます。SwiftUI の `@Environment` / React Context に相当します。

まず値のキーを定義し、`FineEnvironmentValues` に読み書き用のプロパティを生やします。

```swift
private struct ThemeKey: FineEnvironmentKey {
    static let defaultValue = Theme.light
}

extension FineEnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
```

`.environment(\.theme, value)` で注入し、`FineEnvironmentReader` で読みます。

```swift
FineEnvironmentReader { environment in
    FineLabel(text: environment.theme.title)
}
.environment(\.theme, currentTheme)
```

`.environment` は透過ラッパーでビューを増やさず、内側の記述の描画コンテキストへ値を差し込むだけです。ネストすると内側の注入が優先されます。注入元が `@Observable` プロパティなら、値の変化で `FineEnvironmentReader` が再レンダリングされます。

trait も environment 値として読めます([レンダリングの挙動](rendering.md#dynamic-type-と-trait))。

---

## 状態の置き場所

| | 寿命 | 用途 |
|---|---|---|
| store / model | 画面より長い。外から注入、共有可 | ドメイン状態 |
| **content** | マウントされている間 | その区画固有の UI 状態 |
| `FineState` | ビューの identity と同じ | 局所的な UI 状態（行の展開など） |

content が store を持つかどうかは、ただのプロパティの持ち方です。FineUIKit は「model」という概念を持ちません。所有関係と解放の詳細は [メモリ管理](memory.md) を参照してください。
