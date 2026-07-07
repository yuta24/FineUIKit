# FineUIKit

UIKit の上に宣言的 UI とホットリロードをもたらす実験的ライブラリ。

Rust の [Dioxus](https://dioxuslabs.com) と同じ設計方針 — 「UI を記述(データ)として扱い、ランタイムが差分適用する」 — を UIKit に適用したものです。UI 記述と UIView を分離しているため、状態変化・コード注入のどちらでも「記述を作り直して差分適用する」だけで画面が更新されます。

## 使い方

`FineViewController` を継承し、`@Observable` な状態を渡して `body(_:)` を override します。

```swift
import FineUIKit
import Observation

@Observable
final class ToDoListViewModel {
    var draft: String = ""
    var items: [ToDo] = []
}

final class ToDoListViewController: FineViewController<ToDoListViewModel> {
    init() {
        super.init(state: .init())
    }

    override func body(_ viewModel: ToDoListViewModel) -> any Renderable {
        FineStack.vertical(spacing: 8) {
            FineLabel(text: "\(viewModel.items.count) items")
                .font(.preferredFont(forTextStyle: .headline))
                .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
            FineStack.horizontal(spacing: 8) {
                FineTextField(text: .init(viewModel, \.draft), placeholder: "New task")
                FineButton(title: "Add") { viewModel.add() }
                    .hugging(.defaultHigh, axis: .horizontal)
            }
            .padding(.init(top: 8, leading: 16, bottom: 0, trailing: 16))
            FineList(viewModel.items) { item in
                FineLabel(text: item.title)
            }
            .onDelete { viewModel.remove($0) }
        }
    }
}
```

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

## コンポーネント

| コンポーネント | ベース | 特記事項 |
|---|---|---|
| `FineLabel` | `UILabel` | 型付きモディファイア: `.font` / `.textColor` / `.textAlignment` / `.numberOfLines` |
| `FineButton` | `UIButton` | `action` クロージャ。`.image` / `.configuration(UIButton.Configuration)` |
| `FineImage` | `UIImageView` | |
| `FineStack` | `UIStackView` | `vertical` / `horizontal`、`spacing` / `alignment` / `distribution`。子は keyed + 位置ベースで差分適用 |
| `FineList` | `UITableView` | diffable data source(`Identifiable`)。セクション / ヘッダー・フッター / `.onRefresh` / `.onSelect` / `.onDelete` |
| `FineGrid` | `UICollectionView` | compositional layout。`columns: .count(n)` / `.adaptive(minimum:)`、`.onSelect` |
| `FineTextField` | `UITextField` | `FineBinding<String>` で双方向。`.keyboardType` / `.returnKeyType` / `.secureTextEntry` / `.onSubmit` |
| `FineToggle` | `UISwitch` | `FineBinding<Bool>` |
| `FineSlider` | `UISlider` | `FineBinding<Float>` + `in:` レンジ |
| `FineSpacer` | — | スタック内の余白吸収(`minLength:`) |
| `FineScrollView` | `UIScrollView` | 縦横対応。`FineList` / `FineGrid` は自身がスクロールするので入れないこと |

## 双方向バインディング

```swift
FineTextField(text: .init(viewModel, \.draft))   // ReferenceWritableKeyPath から生成
FineToggle(isOn: .init(item, \.completed))
FineSlider(value: .init(settings, \.volume), in: 0...10)

FineTextField(text: .init(viewModel, \.draft), placeholder: "New task")
    .returnKeyType(.done)
    .onSubmit { viewModel.add() }
```

`FineBinding` は `get` / `set` のペアです。`get` はレンダリング中(observation スコープ内)に評価されるため、バインド先の変更で自動的に再レンダリングされます。UI 側の変更は `set` を通じて状態へ書き戻され、「現在値と異なるときだけビューに書く」ガードにより入力中のカーソルは保持されます。

## モディファイア

```swift
FineLabel(text: title)
    .font(.preferredFont(forTextStyle: .headline))  // コンポーネント固有(型付き)
    .padding(16)                                     // レイアウト(ラッパー)
    .backgroundColor(.systemGray6)                   // 外観(同一ビューへ適用)
    .cornerRadius(8)

FineButton(title: "Add") { viewModel.add() }
    .configuration(.filled())
```

- 外観系: `.backgroundColor` / `.cornerRadius` / `.border` / `.opacity` / `.tintColor`
- レイアウト系: `.padding` / `.frame(width:height:alignment:)`
- アクセシビリティ系: `.accessibilityLabel` / `.accessibilityValue` / `.accessibilityHint` / `.accessibilityTraits` / `.accessibilityIdentifier` / `.accessibilityHidden`
- 順序に意味があります(`.backgroundColor().padding()` は背景の外に余白、逆は余白ごと背景)
- コンポーネント固有モディファイアは具体型を返すため、**汎用モディファイアより先に**書きます(型消去後は呼べません。これは意図的な設計で、不正な組み合わせをコンパイルエラーにします)

**残留しない仕組み**: 各記述はモディファイア構成の「署名」を持ち、レンダラーは署名が一致するビューだけを in-place 更新します。値の変更(色・inset 等)は高速に反映され、モディファイアの有無・順序が変わったときはビューを作り直すため、古いスタイルが残りません。

## レイアウト API(Auto Layout ネイティブ)

SwiftUI 風の近似ではなく、`NSLayoutConstraint` の概念をそのまま宣言します。

```swift
FineImage(image: icon)
    .width(.equal, 44)          // ビュー自身への実制約。constant 変更は in-place
    .aspectRatio(1)

FineLabel(text: title)
    .compressionResistance(.required, axis: .horizontal)

FineTextField(text: binding)
    .hugging(.defaultLow, axis: .horizontal)

FineLabel(text: "badge")
    .frame(width: 80, height: 44, alignment: .center)  // 枠内配置が必要なときだけラッパー

FineImage(image: photo).constraints(id: "photo") { view in   // エスケープハッチ
    [view.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.75)]
}
```

寸法制約のデフォルト priority は `999` で、コンテナ(fill 揃えのスタック等)が課す required 制約と矛盾しないようになっています。必要なら `.required` を明示できます。

## keyed diff

`FineStack` の子は既定では位置ベースで照合されますが、`FineForEach` / `.key(_:)` で安定した identity を与えると、挿入・並び替え・削除で**同じ論理項目のビューが同一インスタンスのまま移動**します(フォーカス・スクロール位置などビューローカル状態の保持)。

```swift
FineStack.vertical(spacing: 8) {
    FineLabel(text: "Header")
    FineForEach(items) { item in
        FineTextField(text: .init(item, \.title))
    }
}
```

`if/else` と `for-in` は位置ベースで照合されます。安定した identity が必要な子には `FineForEach` か `.key(_:)` を使ってください。
従来の配列リテラル構文(`{ [a, b] }` や配列連結)もそのまま動きます。

`FineList` / `FineGrid` は `Identifiable` の ID で常に keyed です。

## アーキテクチャ

- `Renderable` — UI 記述のプロトコル。`_makeView()`(生成)/ `_canUpdate(_:)`(再利用可否)/ `_update(_:)`(適用)を実装する値型
- `FineRenderer` — 差分適用層。「ビュー型互換 + モディファイア署名一致 + key 一致」のときだけ in-place 更新、それ以外は作り直し
- `FineUI` — `withObservationTracking` で「body 再評価 → 差分適用」のループを回すランタイム
- `FineViewController` — 上記をまとめた推奨インターフェース

## ホットリロード

DEBUG ビルドでは、コード注入(InjectionLite / InjectionIII / InjectionNext)の完了通知を `FineUI` が受け取り、自動で再レンダリングします。

`FineViewController` の `body` は vtable 経由で動的ディスパッチされるメソッドなので、注入によって実装が差し替わると、次の再レンダリングから新しいコードが使われます。**アプリ側にホットリロード用のコードは一切不要です。** 状態は `@Observable` オブジェクトに住んでいるため、リロードをまたいで保持されます。

Example アプリでは [InjectionLite](https://github.com/johnno1962/InjectionLite)(GUI アプリ不要)を利用しています。セットアップ:

1. InjectionLite を SPM で追加(またはビルドマシンで InjectionIII.app を起動)
2. Debug 構成の Other Linker Flags に `-Xlinker -interposable` を追加
3. シミュレータでアプリを起動し、ソースを編集・保存すると数秒で画面に反映される

### 注意: `body` の外に書いたコードの差し替え

Xcode の新リンカ(chained fixups)環境では、`private` メソッドへの直接呼び出しなど静的ディスパッチされるコードは注入で差し替わりません。確実に差し替わるのは、クラスの vtable 経由(`FineViewController.body` の override)か ObjC ディスパッチ(`@objc dynamic`)のコードです。ホットリロードで書き換えたいロジックはできるだけ `body` から辿れる位置に置いてください。

### 既知の問題(Xcode 27 beta + InjectionLite 1.2.x)

1. **Xcode 27 の SLF ログ形式との非互換** — InjectionLite がビルドログから抽出するコンパイルコマンドの行頭にゴミ(不均衡な引用符)が混入し、`sh: unexpected EOF while looking for matching '"'` で再コンパイルに失敗する。GUI ビルドでも発生する(InjectionLite 側の対応待ち)
2. **注入 dylib の rpath に `/usr/lib/swift` が含まれない** — `libswift_Concurrency.dylib` が見つからず dlopen に失敗することがある
3. **CLI ビルドのみ**: `xcodebuild` には `EMIT_FRONTEND_COMMAND_LINES=YES` を付けないとログに `swift-frontend` の行が残らない。対象ファイルが実際に再コンパイルされたビルドのログにしか行は残らない

1 と 2 は `Scripts/injectionlite-xcode27-fix.sh` で回避できます。クリーンなコマンドだけを含むログを DerivedData に生成し、`PackageFrameworks/` に dylib の symlink を張ります:

```sh
Scripts/injectionlite-xcode27-fix.sh ToDo   # ビルドのたびに実行(スキームの post-action 推奨)
```

新しいビルドを行うと壊れたログが最新になってしまうため、**ビルド後に毎回実行**が必要です。Xcode の Edit Scheme → Build → Post-actions に Run Script として登録しておくと自動化できます。

## 動作要件

- iOS 17+(Observation フレームワーク前提)
- Swift 6 / ホットリロードはシミュレータ + DEBUG ビルド限定

## テスト

```sh
xcodebuild -scheme FineUIKit -destination 'platform=iOS Simulator,name=iPhone 17' test
```
