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
| `FineButton` | `UIButton` | `action` クロージャ。`.image` / `.configuration(UIButton.Configuration)` / `.enabled` |
| `FineImage` | `UIImageView` | |
| `FineStack` | `UIStackView` | `vertical` / `horizontal`、`spacing` / `alignment` / `distribution`。子は keyed + 位置ベースで差分適用 |
| `FineList` | `UITableView` | diffable data source(`Identifiable`)。セクション / ヘッダー・フッター / `.onRefresh` / `.reconfiguringOnlyChangedRows()` / `.onSelect` / `.onDelete` / `.keyboardDismissMode`。行の高さは観測起因の変化に自動追従 |
| `FineGrid` | `UICollectionView` | compositional layout。`columns: .count(n)` / `.adaptive(minimum:)`、セクション / ヘッダー・フッター / `.onRefresh` / `.reconfiguringOnlyChangedItems()` / `.onSelect` / `.keyboardDismissMode` |
| `FineTextField` | `UITextField` | `FineBinding<String>` で双方向。`.keyboardType` / `.returnKeyType` / `.secureTextEntry` / `.onSubmit` / `.enabled` / `.focused` |
| `FineToggle` | `UISwitch` | `FineBinding<Bool>`。`.enabled` |
| `FineSlider` | `UISlider` | `FineBinding<Float>` + `in:` レンジ。`.enabled` |
| `FineSpacer` | — | スタック内の余白吸収(`minLength:`) |
| `FineScrollView` | `UIScrollView` | 縦横対応。`.keyboardDismissMode`。`FineList` / `FineGrid` は自身がスクロールするので入れないこと |

組み込みにないビューは `FineViewRepresentable` で任意の `UIView` をラップできます(後述)。

## ナビゲーション

`FineViewController.navigation(_:)` を override すると、`body(_:)` と同じ observation / hot reload の流れで `navigationItem` を宣言できます。`nil` を返す既定実装では `navigationItem` に触らないため、手動管理もそのまま使えます。

```swift
override func navigation(_ state: ToDoListViewModel) -> FineNavigation? {
    FineNavigation(title: "ToDo (\(state.items.count))")
        .trailing(
            FineBarButton(systemItem: .add) { [unowned self] in
                addTask(state)
            }
            .enabled(!state.draft.isEmpty)
        )
}
```

画面遷移 DSL は持たず、従来どおり action 内で手続き的に書きます。

```swift
FineBarButton(title: "Detail") { [weak self] in
    self?.navigationController?.pushViewController(DetailViewController(), animated: true)
}
```

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

## フォーカス管理

`FineTextField` の `.focused(_:)` に `FineBinding<Bool>` を渡すと、first responder を状態から駆動できます。`true` を書くとフォーカス(キーボード表示)、`false` を書くと解除。ユーザー操作によるフォーカスの出入りもバインディングへ書き戻されます。

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

## ライフサイクルと非同期処理

`.onAppear` / `.onDisappear` はビューが window に載った / 外れたタイミングで発火します。`.task` は表示時に async 処理を起動し、非表示になると自動でキャンセルします。

```swift
FineLabel(text: viewModel.status)
    .task { await viewModel.load() }   // 表示で開始、非表示でキャンセル

FineLabel(text: detail.title)
    .task(id: viewModel.selectedID) { await viewModel.loadDetail() }  // id が変わると再起動
```

再レンダリングで実行中の task が再起動されることはありません(再起動は `id` の変化時のみ)。`.onAppear` は window への着脱のたびに発火します。

## キーボード

ルートビューの下端は既定で `keyboardLayoutGuide` に追従するため、キーボード表示中はコンテンツがその上に詰まり、隠れません(キーボード非表示時は safe area 下端と一致し、レイアウトは従来どおり)。無効にする場合は `FineViewController` の `avoidsKeyboard` を override します(`FineUI` 直接利用なら `init(_:avoidsKeyboard:body:)`)。

```swift
override var avoidsKeyboard: Bool { false }
```

スクロールでキーボードを閉じるには `.keyboardDismissMode` を使います(`FineList` / `FineGrid` / `FineScrollView`)。

```swift
FineList(viewModel.items) { item in
    FineLabel(text: item.title)
}
.keyboardDismissMode(.onDrag)
```

## アニメーション

`withFineAnimation` で状態変更を包むと、その変更で発生する次の再レンダリングが `UIView.animate` 内で差分適用されます。引数省略時は `.easeInOut(duration: 0.3)` です。

```swift
withFineAnimation {
    viewModel.isExpanded.toggle()
}

withFineAnimation(.spring(duration: 0.5, bounce: 0.2)) {
    viewModel.padding = 32
}

withFineAnimation(nil) {
    viewModel.resetAll()
}
```

対象は同じ `UIView` への in-place なプロパティ変更と、制約 constant の変更です。`opacity` / `backgroundColor` / `tintColor` / `cornerRadius` などは UIKit の通常のアニメーションとして動き、`padding` / `width` / `height` などのレイアウト変更は `layoutIfNeeded()` による frame アニメーションになります。

ビューの作り直し、スタックへの挿入・削除、テキスト差し替えのクロスフェードは行いません。動かしたい変化は、同じビューに対する値変更として表現してください。

`FineList` / `FineGrid` の diff は従来どおり window 上では自動アニメーションします。`withFineAnimation(nil)` の中で行った変更では、diff 適用のアニメーションも抑止されます。

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
- インタラクション系: `.onTap`(任意のビューにタップハンドラを付ける。ラベルや画像でも `isUserInteractionEnabled` を自動で有効化。タッチはビューにも届くため、コントロール自身のアクションと共存する。チェーンした `.onTap` は全て順に実行。`nil` を渡すとビューの identity を保ったままハンドラだけ外せる — 条件付きタップは `.onTap(cond ? handler : nil)` と書く)
- アクセシビリティ系: `.accessibilityLabel` / `.accessibilityValue` / `.accessibilityHint` / `.accessibilityTraits` / `.accessibilityIdentifier` / `.accessibilityHidden`
- ライフサイクル系: `.onAppear` / `.onDisappear` / `.task` / `.task(id:)`
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
`FineList` の `.reconfiguringOnlyChangedRows()` と `FineGrid` の `.reconfiguringOnlyChangedItems()` は値型要素向けの最適化で、表示に使う全プロパティを `==` が正確に反映することが前提です。
行 / item content が読んだ `@Observable` プロパティは、リスト / グリッド全体の再 render なしにセル単位で自動更新されます。ヘッダー・フッターも同様にセル単位の observation で更新されます。観測起因の更新で高さが変わった場合は、リスト / グリッド単位で1回に合流(coalesce)された高さ再計算が自動で走ります(ヘッダー・フッターも対象)。
`.environment(_:_:)` で注入した値はセル・ヘッダー・フッターの content にも伝播します。環境値の変更は observation 経由で可視セルにも自動反映されるため、`.reconfiguringOnlyChangedRows()` 使用時も取り残されません。環境値には `Equatable` な型を推奨します(非 `Equatable` の値は毎レンダー「変更あり」とみなされ、可視セルの再描画が増えます)。

## 任意の UIView のラップ(FineViewRepresentable)

組み込みコンポーネントにないビュー(`WKWebView`、`MKMapView`、自作ビューなど)は `FineViewRepresentable` で宣言的ツリーに組み込めます。SwiftUI の `UIViewRepresentable` に相当します。

```swift
struct ProgressBar: FineViewRepresentable {
    let progress: Float

    func makeView() -> UIProgressView {
        UIProgressView(progressViewStyle: .default)
    }

    func updateView(_ view: UIProgressView, environment: FineEnvironmentValues) {
        if view.progress != progress {
            view.progress = progress
        }
    }
}

// 通常のコンポーネントと同じように合成・修飾できる
ProgressBar(progress: viewModel.progress)
    .padding(16)
```

- `makeView()` はビューの identity が新しくなるときに1回だけ呼ばれ、以降の再レンダリングでは同じインスタンスに `updateView(_:environment:)` が呼ばれます
- `updateView` は記述が管理する全プロパティを毎回書き戻してください(別の状態のあとに再利用されるため)。setter が重いプロパティは「現在値と異なるときだけ書く」ガードを推奨します
- 再利用の判定は組み込みと同じ「型 + モディファイア署名 + key」です。`ViewType` が同じでも representable の型が異なればビューは共有されません

## クロージャのキャプチャとメモリ管理

`FineButton` の `action` などのクロージャは、node 単位の再レンダリングのためにビュー側(`FineNode`)に保持されます。このため **view controller の `self` を強参照でキャプチャすると循環参照になり、コントローラがリークします**(self → view → FineNode → クロージャ → self)。

```swift
// ❌ リーク: self を強参照キャプチャ
FineButton(title: "Add") { self.addTask() }

// ✅ 状態オブジェクトのキャプチャは安全(state は self を参照しない)
FineButton(title: "Add") { viewModel.add() }

// ✅ self のメソッドを呼ぶなら weak / unowned で
FineButton(title: "Add") { [unowned self] in addTask() }
```

原則: **クロージャには状態(`@Observable` モデル)だけをキャプチャし、view controller 自身をキャプチャする場合は `[weak self]` / `[unowned self]` を付けてください。**

## アーキテクチャ

- `Renderable` — UI 記述の公開プロトコル。アプリ側は `body` で組み込みコンポーネントを合成する
- 内部プリミティブ — 組み込みコンポーネントが持つ `_makeView()` / `_canUpdate(_:)` / `_update(_:context:)` 契約。署名や全プロパティ書き戻しの規則は公開 API ではない
- `FineRenderer` — 差分適用層。`body` を内部プリミティブへ解決し、「ビュー型互換 + モディファイア署名一致 + key 一致」のときだけ in-place 更新、それ以外は作り直し
- `FineNode` — 各ビューに紐づく永続「要素」(Flutter の Element 相当)。モディファイア署名・key・ノード局所の観測状態(scheduler の generation / context)に加え、`FineState` のローカル状態を所有する。ビューと同寿命なので、状態は再レンダリングをまたいで保持される
- `FineUI` — `withObservationTracking` で差分適用を駆動するランタイム。root の `body` は構造、コンテナの `content` はそのノード、`FineLabel.text` はラベルノード単位で再評価される
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

性能比較テストだけを実行する場合:

```sh
xcodebuild -scheme FineUIKit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FineUIKitTests/RenderingPerformanceTests test
```

性能値の絶対値は実機 + Release 構成でないと意味を持ちにくく、シミュレータ結果は傾向把握用です。
