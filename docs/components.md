# コンポーネント

組み込みコンポーネントの一覧と、組み込みにないビューの組み込み方(`FineViewRepresentable`)、キーボードまわりの挙動をまとめます。

---

## 一覧

| コンポーネント | ベース | 特記事項 |
|---|---|---|
| `FineLabel` | `UILabel` | 型付きモディファイア: `.font` / `.textColor` / `.textAlignment` / `.numberOfLines` |
| `FineButton` | `UIButton` | `action` クロージャ。`.image` / `.configuration(UIButton.Configuration)` / `.enabled` |
| `FineImage` | `UIImageView` | |
| `FineStack` | `UIStackView` | `vertical` / `horizontal`、`spacing` / `alignment` / `distribution`。子は keyed + 位置ベースで差分適用 |
| `FineList` | `UITableView` | diffable data source(`Identifiable`)。セクション / ヘッダー・フッター / `.onRefresh` / `.reconfiguringOnlyChangedRows()` / `.onSelect` / `.onDelete` / `.onPrefetch` / `.onCancelPrefetch` / `.keyboardDismissMode`。行の高さは観測起因の変化に自動追従 |
| `FineGrid` | `UICollectionView` | compositional layout。`columns: .count(n)` / `.adaptive(minimum:)`、セクション / ヘッダー・フッター / `.onRefresh` / `.reconfiguringOnlyChangedItems()` / `.onSelect` / `.onPrefetch` / `.onCancelPrefetch` / `.keyboardDismissMode` |
| `FineTextField` | `UITextField` | `FineBinding<String>` で双方向。`.keyboardType` / `.returnKeyType` / `.secureTextEntry` / `.onSubmit` / `.enabled` / `.focused` |
| `FineTextView` | `UITextView` | 複数行入力。`FineBinding<String>` + placeholder(UIKit にないので独自描画)。既定でスクロール無効=内容に合わせて伸びる。`.font` / `.textColor` / `.textAlignment` / `.editable` / `.scrollEnabled` / `.keyboardType` / `.focused` |
| `FineToggle` | `UISwitch` | `FineBinding<Bool>`。`.enabled` |
| `FineSlider` | `UISlider` | `FineBinding<Float>` + `in:` レンジ。`.enabled` |
| `FineStepper` | `UIStepper` | `FineBinding<Double>` + `in:` レンジ / `step:`。`.enabled` |
| `FineSegmentedControl` | `UISegmentedControl` | `FineBinding<Int>` で選択。タイトル / 画像セグメント。セグメントの増減・差し替えは in-place 差分適用。`.enabled` |
| `FineDatePicker` | `UIDatePicker` | `FineBinding<Date>` + `in:` レンジ。`.datePickerMode` / `.preferredDatePickerStyle` / `.minuteInterval` / `.enabled`。`.countDownTimer` は非対応(`Date` では duration を表現できないため。debug ビルドでは assert) |
| `FinePageControl` | `UIPageControl` | `FineBinding<Int>` + `numberOfPages`(範囲外はクランプ)。`.hidesForSinglePage` / `.pageIndicatorTintColor` / `.currentPageIndicatorTintColor` |
| `FineProgressView` | `UIProgressView` | `value:` / `total:`(0...1 にクランプ)。`.progressViewStyle` / `.progressTintColor` / `.trackTintColor` |
| `FineActivityIndicator` | `UIActivityIndicatorView` | `isAnimating:` で開始・停止。`.style` / `.color` / `.hidesWhenStopped` |
| `FineSpacer` | — | スタック内の余白吸収(`minLength:`) |
| `FineDivider` | — | 区切り線。既定は1物理ピクセルのヘアライン(display scale 追従)。`FineDivider()` = 横線 / `FineDivider.vertical()` = 縦線、`.thickness` / `.color` |
| `FineScrollView` | `UIScrollView` | 縦横対応。`.keyboardDismissMode`。`FineList` / `FineGrid` は自身がスクロールするので入れないこと |

組み込みにないビューは `FineViewRepresentable` で任意の `UIView` をラップできます(後述)。

## 表示される前に知る(prefetch)

行の記述はセルが構成されるとき — つまり**見えるようになる瞬間**に組み立てられます。その中に遅いもの(リモート画像、デコードの要るアセット)があると、開始が遅すぎて行がポップインします。`.onPrefetch` は UIKit の予告(`UITableViewDataSourcePrefetching` / `UICollectionViewDataSourcePrefetching`)を受け取る入口です。

```swift
FineGrid(photos, columns: .adaptive(minimum: 120)) { photo in
    FinePhotoCell(photo)
}
.onPrefetch { photos in
    for photo in photos { ImageLoader.shared.start(photo.url) }
}
.onCancelPrefetch { photos in
    for photo in photos { ImageLoader.shared.cancel(photo.url) }
}
```

**ランタイムは何も先読みしません。** 高い処理はアプリの content クロージャの中にあるので、できるのは予告を転送することだけです。渡されるのは index path ではなく**要素**で、これは差分適用で index が意味を失うためです(このライブラリの他の部分と同じく identity ベース)。

- スクロール中にメインアクターで呼ばれます。**ここで処理を行わず、投げてください**。UIKit がどれだけ先を読むかは UIKit が決め、同じ行を複数回要求することもあります
- `.onCancelPrefetch` は**対応関係のある呼び出しではありません**。表示された行は単に使われるだけで報告されず、要素がコレクションから消えた行も報告されません(それを知っているのは削除したコード自身なので)。**開始していない処理の中止を求められることはありません**が、既に終わった処理について呼ばれることはあるので冪等に書いてください
- キャンセルは index で届きます。**index は差分適用で意味が変わる**ため、このライブラリは「実際に予告した要素」だけを報告します。並べ替えの後に届いたキャンセルが無関係な行を指していた場合、それは無視されます
- `.onPrefetch` が無い場合、`prefetchDataSource` は設定されません。**`.onCancelPrefetch` だけを書いても何も起きません** — キャンセルは「始まった処理」の話なので、開始を報告する者がいなければ正直にキャンセルできるものもありません
- グリッドで特に効きます。リストの1行は1セルですが、グリッドの1行は列数ぶんのセルです

---

`FineList` と `FineGrid` のセクションは**同じ型**です。`FineSection<Element>`(id・任意のヘッダー / フッター・items)が本体で、`FineListSection` / `FineGridSection` はその別名なので、1 つ組み立てたセクション値をどちらにも渡せます。両者は差分の取り方(どのセクションが増減したか、生き残った要素のうちどれが古いか、データソースに渡すことがそもそも有るか)を1つの実装で共有しており、セクション型が別々である理由はありませんでした。

`FineProgressView(value:)` / `FineActivityIndicator(isAnimating:)` は表示値を `@autoclosure` で受け取ります(`FineLabel(text:)` と同じ)。読み取りはそのノードの `_update` 内で起きるため、進捗やローディングの変化では**そのビューだけ**が更新され、`body` は再評価されません。`total:` は素の値なので、これが変わったときは `body` から再評価されます。

```swift
FineStack.vertical(spacing: 12) {
    FineProgressView(value: viewModel.downloaded, total: viewModel.totalBytes)
    FineDivider()
    FineStack.horizontal(spacing: 8) {
        FineActivityIndicator(isAnimating: viewModel.isLoading)
        FineLabel(text: viewModel.status)
    }
}
```

---

## Renderable で記述を分割する

`body` が長くなったら、`Renderable` に適合した型へ切り出せます。引数を受け取って記述を返すだけの部品なので、struct が向いています。

```swift
struct ToDoRow: Renderable {
    let item: ToDo
    let onToggle: @MainActor () -> Void

    var body: any Renderable {
        FineStack.horizontal(spacing: 8) {
            FineButton(title: self.item.isDone ? "☑" : "☐") { self.onToggle() }
            FineLabel(text: self.item.title)
                .font(.preferredFont(forTextStyle: .body))
        }
    }
}

// content の body から使う
FineList(self.items) { item in
    ToDoRow(item: item) { self.toggle(item) }
}
```

**ホットリロードは効きます。** `body` は computed property ですが、注入の差し替え単位はシンボルであり、getter もその対象です([ホットリロード](hot-reload.md))。

- **再利用の判定に型が効きます**。`Header` と `Footer` がどちらも `FineLabel` に解決される場合でも、入れ替えればビューは作り直されます(作り直されたノードの `FineState` は破棄されます)。型は既存の判定に畳み込まれるので、in-place 更新になるのは「ビュー型互換 + モディファイア署名 + key」が揃い、**かつ**型も同じときです
- **observation の粒度は切り出しても細かくなりません**。`body` は「解決される位置」で評価されるので、そこで読んだ observable の変化は**解決した側のスコープ**を再実行します — `FineStack` の子ならその stack ノードの `_update` と builder、ルート直下なら `FineUI` のルートスコープ、セルの中なら `FineNodeHost` のスコープです。ノード単位に閉じたいときは、`FineLabel(text:)` のように値を `@autoclosure` で受け取る組み込みか、builder クロージャの内側で読んでください。上の例のように**値を引数で渡す**形なら、読み取りは呼び出し元で起きるので迷う必要はありません
- 状態やメソッドを持たせたくなったら、それは `Renderable` ではなく入れ子の content(`@Observable` なクラス)の役目です([状態とバインディング](state.md))

---

## 任意の UIView のラップ(FineViewRepresentable)

組み込みコンポーネントにないビュー(`WKWebView`、`MKMapView`、自作ビューなど)は `FineViewRepresentable` で宣言的ツリーに組み込めます。SwiftUI の `UIViewRepresentable` に相当します。

```swift
struct BlurBackground: FineViewRepresentable {
    let style: UIBlurEffect.Style

    func makeView() -> UIVisualEffectView {
        UIVisualEffectView(effect: nil)
    }

    func updateView(_ view: UIVisualEffectView, environment: FineEnvironmentValues) {
        let effect = UIBlurEffect(style: style)
        if view.effect != effect {
            view.effect = effect
        }
    }
}

// 通常のコンポーネントと同じように合成・修飾できる
BlurBackground(style: .systemMaterial)
    .padding(16)
```

- `makeView()` はビューの identity が新しくなるときに1回だけ呼ばれ、以降の再レンダリングでは同じインスタンスに `updateView(_:environment:)` が呼ばれます
- `updateView` は記述が管理する全プロパティを毎回書き戻してください(別の状態のあとに再利用されるため)。setter が重いプロパティは「現在値と異なるときだけ書く」ガードを推奨します
- 再利用の判定は組み込みと同じ「型 + モディファイア署名 + key」です。`ViewType` が同じでも representable の型が異なればビューは共有されません

---

## キーボード

ルートビューの下端は既定で `keyboardLayoutGuide` に追従するため、キーボード表示中はコンテンツがその上に詰まり、隠れません(キーボード非表示時は safe area 下端と一致し、レイアウトは従来どおり)。無効にする場合は `FineContentController(_:avoidsKeyboard:)` に `false` を渡します。

```swift
FineContentController(ToDoList(), avoidsKeyboard: false)
```

スクロールでキーボードを閉じるには `.keyboardDismissMode` を使います(`FineList` / `FineGrid` / `FineScrollView`)。

```swift
FineList(viewModel.items) { item in
    FineLabel(text: item.title)
}
.keyboardDismissMode(.onDrag)
```

フォーカス(first responder)を状態から駆動する方法は [状態とバインディング](state.md#フォーカス管理) を参照してください。

---

## 参考

- モディファイアとレイアウト: [モディファイアとレイアウト](layout.md)
- リスト / グリッドの行の再構築: [レンダリングの挙動](rendering.md#keyed-diff)
