# `FineList` を `UICollectionView` に載せ替えるか

ブリーフ Phase 3 が挙げていた検討事項の記録です。**結論は「今はやらない」**で、その理由と、やるとしたら何が要るかを残します。

---

## 何が提案されていたか

`FineList` は `UITableView`、`FineGrid` は `UICollectionView` の上に立っています。`FineList` も `UICollectionView`(list configuration)に載せ替えれば、コレクション系が1つの土台に揃う、という案です。

---

## 前提が変わりました

提案時点では、両者は差分適用・supplementary・reconfigure 判定を**約 250 行にわたってほぼ丸ごと重複実装**していました。「土台を揃えれば重複が消える」というのが最大の動機です。

**その重複は既に解消済みです**([#49](https://github.com/yuta24/FineUIKit/pull/49))。`FineCollectionCoordinator` が両者の共通部分を持ち、`FineList` に残るテーブル固有のコードは **509 行中およそ 75 行**です。内訳:

| 残っているテーブル固有の要素 | `UICollectionView` での代替 |
|---|---|
| `UITableViewDiffableDataSource` サブクラス(`canEditRowAt`) | list configuration の swipe actions provider |
| `UITableViewDelegate` の header / footer 供給 | boundary supplementary items(グリッド側と同形) |
| `sectionHeaderHeight` / `estimatedSectionHeaderHeight` / `sectionHeaderTopPadding` | list configuration の `headerMode` |
| `UITableViewCell.SelectionStyle` の掃き出し | `UICollectionViewListCell` の背景設定 |
| swipe-to-delete(`trailingSwipeActionsConfigurationForRowAt`) | `trailingSwipeActionsConfigurationProvider` |
| `beginUpdates` / `endUpdates` による行高の再計測 | `invalidateLayout`(共有基底に既にある) |

**つまり移行しても消える重複はもうほとんどありません。** 動機の大部分は別の手段で既に回収されています。

---

## 壊れるもの

### public API は壊れません

`FineList` の公開シグネチャに `UITableView` は現れません。唯一の UIKit 型は `UIScrollView.KeyboardDismissMode` で、これは `UICollectionView` でも同じ型です。`FineListView` も internal です。

つまり**コンパイルは通り続けます**。壊れるのは見た目と振る舞いで、これは**コンパイラが教えてくれない類の破壊**です。この形の非互換がいちばん質が悪い。

### 見た目

- **セパレータ**: `UITableView.Style.plain` の既定セパレータと、list configuration の `.separatorConfiguration` は既定値もインセットの基準も異なります
- **セルの余白**: 現在は `contentView.layoutMarginsGuide` に content を貼っています。`UICollectionViewListCell` は独自の余白規則を持ちます
- **セクションヘッダーの追従**: `.plain` のヘッダーは既定でスクロールに追従して固定されます。list configuration では `headerMode` と `.plain`/`.insetGrouped` の選択で変わります
- **選択時のハイライト**: `UITableViewCell.SelectionStyle` と `UIBackgroundConfiguration` は色も遷移も別物です

### 振る舞い

- **swipe-to-delete のアニメーション**とアクションの当たり判定が変わります
- **`estimatedSectionHeaderHeight` に依存した初期レイアウト**の揺れ方が変わります

### テスト

`as? UITableView` を前提にしたアサーションが **51 箇所**あります(7 ファイル)。移行時はすべて書き換えが必要で、この書き換え自体が「テストが何を検証していたか」を薄める危険を持ちます。

---

## 段階分けするなら

ブリーフの要求どおり、やるとしたら次の順です。**各段階が独立してマージ可能で、途中で止められること**を条件にします。

1. **視覚的な差分を固定するテストを先に書く** — セパレータの有無、セルの余白、ヘッダーの固定挙動を、現在の `UITableView` 実装に対して assert する。これが無いまま移行すると、壊れたことに誰も気付けません
2. **`FineCollectionCoordinator` に残りのテーブル固有部分を引き上げる** — swipe actions と supplementary の供給を、両実装が呼べる形にする
3. **`UICollectionView` 版を別型として実装する**(`FineList` は据え置き)。1 のテストを新実装に対しても走らせ、差分を洗い出す
4. **差分を潰しきってから**、`FineList` の `_makeView` を差し替える

### 互換レイヤーについて

`_makeView` を差し替える段で、`FineList` に `.backingStore(.tableView)` のような逃げ道を用意する案があります。**採りません。** 2つの実装を並行して保守することになり、それは今回消したばかりの重複を別の形で作り直す行為です。移行するなら片道です。

---

## 今やらない理由

1. **重複解消という主目的は #49 で達成済み**。残るテーブル固有コードは 75 行で、これを消すために視覚的破壊とテスト 51 箇所の書き換えを引き受ける釣り合いが取れていません
2. **壊れ方がコンパイラに見えません**。見た目の破壊は利用者のスクリーンショットで初めて分かります
3. **`UITableView` が困っている具体的な問題がありません**。「揃っていないこと」自体は問題ではありません

**やる理由ができるとすれば**、`UITableView` では表現できない要求が出たときです。具体的には:

- リストのセクション内で**横スクロール**したい(orthogonal scrolling)
- セクションの背景に**装飾ビュー**を敷きたい(decoration items)
- リストとグリッドを**1つのスクロールビュー内で混在**させたい

いずれも `UICollectionViewCompositionalLayout` にしか無く、`FineShelf` を `FineList` の行に入れるだけでは解けません(別スクロールビューの入れ子になります)。**この要求が実際に来たら、上の段階分けで着手する価値があります。**

---

## 参考

- 共通化の実際: [#49](https://github.com/yuta24/FineUIKit/pull/49)、`Sources/FineUIKit/Components/FineCollection.swift`
- コレクションの現在の設計: [内部アーキテクチャ §13](architecture.md#13-リスト--グリッドセル内の観測)
