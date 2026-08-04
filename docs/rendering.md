# レンダリングの挙動

何がいつ再レンダリングされるか — keyed diff、trait 変化、ライフサイクル、画面が隠れている間の停止、アニメーションをまとめます。

---

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

**生き残った行の再構築**: リスト / グリッドが再レンダリングされたとき、ID が生き残った行の content は**要素が変化した行だけ**再実行されます。

この最適化が成立する条件は「**比較の両辺が独立した値のスナップショットであること**」です。要素が `Equatable` でない場合と、要素が**参照型**(class)の場合は、安全側に倒して生き残った全行を再実行します。参照型で比較をスキップさせたい場合だけ `.reconfiguringOnlyChangedRows()` を明示してください。

> **既存コードからの移行**: 以前は生き残った行を毎回すべて再実行していました。値型で `Equatable` な要素を使い、かつ行 content が「要素にも `@Observable` にも含まれない値」(`body` で読んだ素の `let` をキャプチャしている等)を表示している場合、**コンパイルエラーなしで表示が古いまま**になります。該当する場合は `.reconfiguringAllRows()` / `.reconfiguringAllItems()` を付けてください。

⚠️ **値型でも、内部に可変な参照(class)を持っている場合は変化を検出できません**。`struct Row { let model: SomeClass }` のような要素は、比較の両辺が同じインスタンスを指すため、どんな `==` でも「等しい」と答えます。この場合は次のどちらかにしてください。

- モデルを `@Observable` にする(セル単位の observation が変化を拾います。FineUIKit ではこちらが素直です)
- `.reconfiguringAllRows()` / `.reconfiguringAllItems()` で毎回再実行させる

`.reconfiguringOnlyChangedRows()` / `.reconfiguringOnlyChangedItems()` は値型では既定と同じ動作の明示形で、参照型では「同一インスタンスの比較でもスキップする」というオプトインになります(「表示に使う全プロパティを `==` が反映する」ことが前提)。

要素にも `@Observable` にも含まれない値(row content がキャプチャしただけの素の `Bool` など)を表示している場合は、変化を知らせる経路がないため `.reconfiguringAllRows()` / `.reconfiguringAllItems()` で毎回再実行させてください。

行 / item content が読んだ `@Observable` プロパティは、リスト / グリッド全体の再 render なしにセル単位で自動更新されます。ヘッダー・フッターも同様にセル単位の observation で更新されます。観測起因の更新で高さが変わった場合は、リスト / グリッド単位で1回に合流(coalesce)された高さ再計算が自動で走ります(ヘッダー・フッターも対象)。

`.environment(_:_:)` で注入した値はセル・ヘッダー・フッターの content にも伝播します。環境値の変更は observation 経由で可視セルにも自動反映されるため、`.reconfiguringOnlyChangedRows()` 使用時も取り残されません。環境値には `Equatable` な型を推奨します(非 `Equatable` の値は毎レンダー「変更あり」とみなされ、可視セルの再描画が増えます)。

---

## Dynamic Type と trait

`FineLabel` は Dynamic Type に追従します。`.font(.preferredFont(forTextStyle:))` を渡しておけば、文字サイズ設定の変更でラベルが拡大縮小します。

さらにランタイムは、記述が分岐しうる trait の変化で**ツリーを再評価**します。`UIFont.preferredFont(forTextStyle:)` は「記述を作った時点」のカテゴリで解決されるため、再評価しないと古いサイズの記述が残るからです。観測している trait は次の7つです。

`preferredContentSizeCategory` / `userInterfaceStyle` / `horizontalSizeClass` / `verticalSizeClass` / `layoutDirection` / `accessibilityContrast` / `legibilityWeight`

trait は environment から読めるので、記述の中で分岐できます。

```swift
FineEnvironmentReader { environment in
    environment.traitCollection.horizontalSizeClass == .compact
        ? FineStack.vertical { … }
        : FineStack.horizontal { … }
}
```

`traitCollection` は environment 値なので、リスト / グリッドの可視セルにも既存の伝播経路でそのまま届きます(要素が変化していない行も更新されます)。画面が隠れている間の trait 変化は、他の変更と同じく再表示時の catch-up にまとまります。

上記7つ以外の trait も `environment.traitCollection` から読めますが、その変化では自動で再レンダリングされません。

---

## ライフサイクルと非同期処理

`.onAppear` / `.onDisappear` はビューが window に載った / 外れたタイミングで発火します。`.task` は表示時に async 処理を起動し、非表示になると自動でキャンセルします。

```swift
FineLabel(text: viewModel.status)
    .task { await viewModel.load() }   // 表示で開始、非表示でキャンセル

FineLabel(text: detail.title)
    .task(id: viewModel.selectedID) { await viewModel.loadDetail() }  // id が変わると再起動
```

再レンダリングで実行中の task が再起動されることはありません(再起動は `id` の変化時のみ)。`.onAppear` は window への着脱のたびに発火します。

---

## 画面が隠れている間のレンダリング

`FineContentController` は、画面が隠れている間(push で覆われた、タブが切り替わった)は再レンダリングを止めます。その間に届いた状態変更は記録され、再表示時(`viewIsAppearing`)に**1回の catch-up レンダリング**でまとめて反映されます。共有ストアを持つ画面スタックで、見えていない画面が変更ごとに再差分されることはありません。

ナビゲーションは止まりません。覆われた画面のタイトルは上の画面の戻るボタンとして見えているためです。

```swift
override var suspendsWhenDisappeared: Bool { false }   // 隠れている間も更新し続ける
```

`FineUI` を直接使う場合は `suspend()` / `resume()` を呼びます。`build(to:)` の初回レンダリングは止まりません。また catch-up レンダリングはアニメーションしません(画面外で起きた変化をアニメーションする意味がないため)。

判定は `viewDidDisappear` / `viewIsAppearing` に基づくため、次の2つは自動では止まりません。必要なら `suspendRendering()` / `resumeRendering()` を手動で呼んでください(`FineUI` を直接使う場合は `suspend()` / `resume()`)。

- **`.overFullScreen` / `.overCurrentContext` でモーダルを被せた場合** — UIKit は下の画面に `viewDidDisappear` を送りません(部分的に見えている可能性があるため)。通常の `.fullScreen` presentation なら送られるので自動で止まります
- **ロードしたが一度も表示していない画面** — 表示前は動き続けます。`loadViewIfNeeded()` してから状態を流し込み、表示せずにビュー階層を検証する使い方(テストなど)を壊さないための意図的な選択です

`viewIsAppearing(_:)` / `viewDidDisappear(_:)` を override する場合は **`super` の呼び出しが必須**です。呼ばないと初回表示のあと再開されず、画面が黙って更新されなくなります。

---

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

---

## 参考

- 再レンダリングの粒度と内部の仕組み: [内部アーキテクチャ](architecture.md)
- 意図しない作り直しを調べる: [診断](diagnostics.md)
