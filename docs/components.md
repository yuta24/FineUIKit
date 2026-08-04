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
| `FineList` | `UITableView` | diffable data source(`Identifiable`)。セクション / ヘッダー・フッター / `.onRefresh` / `.reconfiguringOnlyChangedRows()` / `.onSelect` / `.onDelete` / `.keyboardDismissMode`。行の高さは観測起因の変化に自動追従 |
| `FineGrid` | `UICollectionView` | compositional layout。`columns: .count(n)` / `.adaptive(minimum:)`、セクション / ヘッダー・フッター / `.onRefresh` / `.reconfiguringOnlyChangedItems()` / `.onSelect` / `.keyboardDismissMode` |
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
