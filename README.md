# FineUIKit

UIKit の上に宣言的 UI とホットリロードをもたらす実験的ライブラリ。

Rust の [Dioxus](https://dioxuslabs.com) と同じ設計方針 — 「UI を記述(データ)として扱い、ランタイムが差分適用する」 — を UIKit に適用したものです。UI 記述と UIView を分離しているため、状態変化・コード注入のどちらでも「記述を作り直して差分適用する」だけで画面が更新されます。

## クイックスタート

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

`body` 内で読んだ `@Observable` プロパティが変化すると自動で再レンダリングされます。ビューは作り直されず、互換なビューは in-place 更新されます。ハンドラが `self`(content)をキャプチャして構いません — 循環しないからです([メモリ管理](docs/memory.md))。

続きは [はじめかた](docs/getting-started.md) へ。

## コンポーネント

`FineLabel` / `FineButton` / `FineImage` / `FineStack` / `FineScrollView` / `FineSpacer` / `FineDivider`、コレクション系の `FineList` / `FineGrid`、入力系の `FineTextField` / `FineTextView` / `FineToggle` / `FineSlider` / `FineStepper` / `FineSegmentedControl` / `FineDatePicker`、表示系の `FinePageControl` / `FineProgressView` / `FineActivityIndicator` があります。

対応する UIKit クラスと使えるモディファイアの一覧は [コンポーネント](docs/components.md) にまとめてあります。組み込みにないビューは `FineViewRepresentable` で任意の `UIView` をラップできます。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [はじめかた](docs/getting-started.md) | `FineContent` の書き方、`FineContentController` でのマウント、ナビゲーション |
| [コンポーネント](docs/components.md) | 組み込みコンポーネント一覧、`FineViewRepresentable`、キーボード |
| [状態とバインディング](docs/state.md) | `FineBinding`、フォーカス、`FineState`、Environment |
| [モディファイアとレイアウト](docs/layout.md) | 外観・レイアウト・インタラクションのモディファイア、Auto Layout ネイティブな制約 API |
| [レンダリングの挙動](docs/rendering.md) | keyed diff、Dynamic Type と trait、ライフサイクル、画面が隠れている間の停止、アニメーション |
| [メモリ管理](docs/memory.md) | キャプチャの安全性、守るべきルール、状態の置き場所、入れ子 |
| [診断](docs/diagnostics.md) | ビューが作り直された理由のログ、レンダリング回数、ハイライト、ツリーダンプ、signpost |
| [ホットリロード](docs/hot-reload.md) | コード注入のセットアップ、`-Xlinker -interposable`、既知の問題 |
| [内部アーキテクチャ](docs/architecture.md) | 記述層 / `FineNode` / `UIView` の三層、差分適用、observation の粒度 |
| [公開 API の設計判断](docs/api-design.md) | この API 形状に至った判断とその根拠 |

## アーキテクチャ

- `Renderable` — UI 記述の公開プロトコル。アプリ側は `body` で組み込みコンポーネントを合成する
- 内部プリミティブ — 組み込みコンポーネントが持つ `_makeView()` / `_canUpdate(_:)` / `_update(_:context:)` 契約。署名や全プロパティ書き戻しの規則は公開 API ではない
- `FineRenderer` — 差分適用層。`body` を内部プリミティブへ解決し、「ビュー型互換 + モディファイア署名一致 + key 一致」のときだけ in-place 更新、それ以外は作り直す
- `FineNode` — 各ビューに紐づく永続「要素」(Flutter の Element 相当)。モディファイア署名・key・ノード局所の観測状態(scheduler の generation / context)に加え、`FineState` のローカル状態を所有する。ビューと同寿命なので、状態は再レンダリングをまたいで保持される
- `FineUI`(internal) — `withObservationTracking` で差分適用を駆動するランタイム。`body()` は構造、コンテナの builder はそのノード、`FineLabel.text` はラベルノード単位で再評価される。画面が隠れている間は `suspend()` で観測起因のレンダリングを止め、`resume()` で1回だけ catch-up する。マウントは `FineContentController` が行うので公開していない
- `FineContent` — 状態を持ち `body()` でビューツリーを記述するオブジェクト。`@Observable` なクラスとして書く。画面とは限らず、任意のビューにマウントできる
- `FineNavigating` — `FineContent` に `navigation()` を足したもの。画面として使うときだけ適合する
- `FineContentController` — 画面をマウントする view controller。`body()` と `navigation()` を別の observation スコープで追跡し、表示状態に応じて `FineUI` を suspend / resume する。手動で止めたいときの公開 API は `suspendRendering()` / `resumeRendering()`。`open` なので継承してよい

内部構造は [内部アーキテクチャ](docs/architecture.md)、**この API 形状に至った判断とその根拠**は [公開 API の設計判断](docs/api-design.md) にまとめてあります。

## 動作要件

- iOS 17+(Observation フレームワーク前提)
- Swift 6 / ホットリロードはシミュレータ + DEBUG ビルド限定

## テスト

```sh
xcodebuild -scheme FineUIKit -destination 'platform=iOS Simulator,name=iPhone 17' test
```

性能比較テストだけを実行する場合:

```sh
xcodebuild -scheme FineUIKit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FineUIKitTests/RenderingPerformanceTests test
```

性能値の絶対値は実機 + Release 構成でないと意味を持ちにくく、シミュレータ結果は傾向把握用です。
