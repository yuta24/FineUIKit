# モディファイアとレイアウト

外観・レイアウト・インタラクションを付けるモディファイアと、Auto Layout をそのまま宣言するレイアウト API を扱います。

---

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
- ライフサイクル系: `.onAppear` / `.onDisappear` / `.task` / `.task(id:)`([レンダリングの挙動](rendering.md#ライフサイクルと非同期処理))
- 順序に意味があります(`.backgroundColor().padding()` は背景の外に余白、逆は余白ごと背景)
- コンポーネント固有モディファイアは具体型を返すため、**汎用モディファイアより先に**書きます(型消去後は呼べません。これは意図的な設計で、不正な組み合わせをコンパイルエラーにします)

**残留しない仕組み**: 各記述はモディファイア構成の「署名」を持ち、レンダラーは署名が一致するビューだけを in-place 更新します。値の変更(色・inset 等)は高速に反映され、モディファイアの有無・順序が変わったときはビューを作り直すため、古いスタイルが残りません。

---

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

---

## 参考

- 署名とビュー再利用の内部: [内部アーキテクチャ](architecture.md#6-モディファイアシステム)
- 作り直しの原因を調べる: [診断](diagnostics.md)
