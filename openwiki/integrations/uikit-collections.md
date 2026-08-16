---
type: "Integration Guide"
title: "UIKit 統合、ナビゲーション、List と Grid"
description: "FineUIKit が UIViewController、UIView、UIKit navigation、UITableView、UICollectionView と接続する際の振る舞いと保守上の注意。"
tags: [uikit, navigation, list, grid, hosting]
---

# UIKit 統合、ナビゲーション、List と Grid

FineUIKit は UIKit を置き換えず、`FineContentController` が `FineContent` を `UIViewController` へ、内部の `FineUI` が UIView 階層へ宣言的ツリーを設置します。更新粒度と停止・復帰の共通ルールは[レンダリングワークフロー](../workflows/rendering.md)、public DSL の状態・extension 規則は[UI 合成と状態](../domain/ui-composition.md)を参照してください。

## 画面とホスティング

画面として使う場合は `FineContentController` に `any FineContent` を渡します（`init(_ content:avoidsKeyboard:)`、`avoidsKeyboard` は既定で `true`）。`viewDidLoad` で内部の `FineUI` を生成し、自身の `view` へ `build(to:)` します（[FineContent.swift](../../Sources/FineUIKit/FineContent.swift)、[FineContentController.swift](../../Sources/FineUIKit/FineContentController.swift)、[FineUI.swift](../../Sources/FineUIKit/FineUI.swift)）。

`FineUI` は意図的に公開していません（`da73abc`）。mounting を自分で書くと suspend/resume のライフサイクル管理も自分で担うことになり、`suspend()` を忘れたツリーは画面外でも黙って再差分され続けます。`FineContentController` はそれを正しく行う唯一の場所です。公開 API の拡張は source-compatible ですが縮小は互換性を壊すため、必要が生じるまで閉じています（この判断の根拠は [`docs/api-design.md`](../../docs/api-design.md) §5）。自分のコントローラ内に埋め込む場合は、UIKit の containment 手順をすべて踏んでください — `addChild(_:)` は親子関係を結ぶだけでビューを足さないので、`addChild(_:)` → コンテナへの `addSubview(_:)` → 制約 → `didMove(toParent:)` の 4 段階が要ります。そうすれば外観遷移が転送され、画面外で停止する render loop も保たれます。

`build(to:)` を別コンテナで再度呼ぶと、同じ root view を移し、旧コンテナにまたがる制約と trait registration を外して新コンテナに再設置します。同じコンテナへの再 build は階層を壊さない idempotent な再レンダーです。この再ホスト経路は `e56854e` とその後の修正で強化され、`FineUIHostingTests.swift` が root 移動、制約の張り直し、状態と trait の追従を保護するため、変更時の必須確認先です。

## 宣言的 navigation

`FineNavigating` に適合すると `navigation() -> FineNavigation?` で `navigationItem` の title、prompt、large-title、back-button、leading/trailing button を宣言できます。`nil` は FineUIKit が navigation item に触れず、手動管理を維持する意味です（[FineNavigation.swift](../../Sources/FineUIKit/FineNavigation.swift)）。navigation が意味を持つのは画面としてマウントされたときだけです。サブビューへレンダリングされた content には書き込む先の bar が無いため、`FineContent.swift` は `FineContent` と `FineNavigating` を分離しています — 適合を禁じているのではなく、その位置では実装しても何も起きないメソッドを生やさない、という分け方です。

navigation は body から分離された observation scope です。タイトルや button の enabled 状態の変更は navigation item だけを更新し、view tree を再調停しません。また、画面本体が非表示で停止中でも navigation は更新されます。後ろの画面の title が上の画面の back-button label として表示されるためです。

bar button の action は既存の `UIAction.primaryAction` を最新 closure に置換して再利用します。button kind/style を変える実装では、古い識別子・title・image・action が残らないことを確認してください。これは `c7589e9`、`00fa51e` による回帰修正の対象でした。

## FineList と FineGrid

`FineList` は `UITableViewDiffableDataSource`、`FineGrid` は `UICollectionViewDiffableDataSource` と compositional layout に基づきます。いずれも `Identifiable` な item、section、header/footer、selection、refresh、keyboard dismiss を扱い、Grid は固定列数または adaptive 最小幅を指定できます（[FineList.swift](../../Sources/FineUIKit/Components/FineList.swift)、[FineGrid.swift](../../Sources/FineUIKit/Components/FineGrid.swift)）。

`fe0a733` 以降、両者の section は**同じ型** `FineSection<Element>` です（[FineCollection.swift](../../Sources/FineUIKit/Components/FineCollection.swift)）。`FineListSection` / `FineGridSection` はその typealias であり、1 つの section 値をどちらにも渡せます。差分ロジック（`plan(sections:reconfiguresAll:areElementsEqual:name:) → FineCollectionPlan` と `commit(_:)`）は共有の `FineCollectionCoordinator<Element>` に一本化され、テーブルとコレクションそれぞれに存在した section-Folding / `reconfiguredIDs` 補助付き signature 確認 / `needsApply` / snapshot 構築 / refresh 制御は重複しません。ヘッダー・フッターの enum は `FineSupplementaryKind`（`.header` / `.footer`）に統一され、`elementKind: String` は UIKit 境界でのみ変換します（List はかつて `Bool isHeader`、Grid は raw `String` を使っていました）。この後退（挙動の prior 差）は [`docs/components.md`](../../docs/components.md) で公に意図されます。`FineSection` 以外の同領域シンボル（`FineCollectionCoordinator`、`FineCollectionPlan`、`FineSupplementaryKind` など）は内部です。

### identity と更新ポリシー

- section ID と item ID は、各コレクション内で一意である必要があります。重複は assertion とスキップの対象です。
- surviving item は、比較可能な要素なら値変化時だけ reconfigure します。`@Observable` な参照モデルをセル内で読む場合はセル局所観測が更新を担います。
- element 外の非 Observable な capture を行表示に使う場合は、`.reconfiguringAllRows()` / `.reconfiguringAllItems()` を選びます。changed-only 設定では `Equatable` が表示内容全体を覆う必要があります。
- header/footer は snapshot の一部ではありません。section identity で supplementary view を追跡・更新する必要があります。

直近の `8a2f4e9` は、構造、reconfigure 対象、supplementary signature に変化がない場合の snapshot apply を省略しました。root の別 state（たとえばテキスト入力）で List/Grid が不要に全 diff されないことは維持すべき性能契約です。この省略判定は `FineCollectionPlan.needsApply` で行われ、`commit(_:)` は apply が行われたときだけ `appliedSectionIDs` / `appliedItemIDs` / `appliedSupplementarySignature` を記録します（Grid はレイアウト無効化のため `supplementaryDidChange` を `needsApply` の前に読みます）。

## セルの局所描画と再利用

セルと supplementary view は `FineNodeHost` を持ちます。`75e52b0` 以降、ホストはセルごとに専用の `FineNodeScheduler` を持ち、セル content 内の Observable 読み取りをノード単位で追跡します（それ以前は行全体が単一スコープで、1 つの値の変更が行の全ビューを書き直していました）。environment の変化は可視セルへ伝播し、内容の高さ変化は table の行高無効化、collection layout invalidation へつながります。非表示中に観測が抑止されたセルは、ホストが自身の復帰を処理し（`recoversSuspendedWork`）、未変更 item が stale のまま残りません（[FineNodeHost.swift](../../Sources/FineUIKit/FineNodeHost.swift)、[FineNodeScheduler.swift](../../Sources/FineUIKit/FineNodeScheduler.swift)）。

### 行バウンドのライフサイクル

`onAppear` / `onDisappear` / `.task` は**表示している行**のライフを表し、セルという UIView の window ライフではありません（`693bb45`）。再利用された visible セルに別の行を渡しても window 遷移は起きないため、かつては前の行が消えたことも新しい行が現れたことも感知されませんでした。`FineLifecycleView` は「window にある」かと「記述が適用された」かを分離し、`setLifecycle(...)` は記述適用後に `notifyAppearIfNeeded()` を、`fineStopIdentityWork()` は行が終わったときに `disappear` を notify します。ホストが identity 変更を知るのはこの分離の外部契機です。

`FineIdentityScopedView` プロトコル（[FineIdentityScopedView.swift](../../Sources/FineUIKit/FineIdentityScopedView.swift)）は、記述のためにビューが保持する状態（lifecycle task、キーボード focus、scroll offset）をホストが巻き下ろすための統一インターフェースです。ホストは `discardIdentityState(in:keepingLocalState:)` でサブツリーを走査し、2 つの状況を区別します（`a87efd7`）:

- **駐車（`prepareForReuse` → `invalidate()`）**: 次に何を表示するか不明。`fineStopIdentityWork()` で lifecycle task とキーボードを止めるが、scroll offset と `FineState` は保持（同じ行が戻るのが通常ケース）。
- **別の行を手渡す（`render(identity:)` で identity 変更）**: その行は終わり。`fineDiscardIdentityState()` でキーボード resign、scroll を `.zero` リセット（`FineScrollHostView` はこちらだけを実装）、`FineState` をクリア、`hasBeenUpdated` を `false` に。

キーボードはどちらの経路でも resign します（行はもうユーザーの手にないため）。scroll offset は駐車中は保持し本当の手渡しでのみゼロにします — 駐車セルが自分の行を取り戻すのが通常ケースで、そこで場所がリセットされるのはバグになるためです。focus binding は手渡し・駐車のいずれでも `false` に書き戻されます（書き込みは新しい記述が適用される前で、まだ旧い binding がインストールされているため、行の意図を正しく反映します）。`003c85b` 以降、この focus binding の書き戻しを検証するテストがあります（[テストと運用](../operations/testing.md) の `FineCellReuseViewStateTests`）。

この領域は UIKit の reuse、diffable apply、layout invalidation が交差します。変更後は [テストと運用](../operations/testing.md) の `FineListBehaviorTests`、`FineInteractionTests`、`FineUIHostingTests`、`FineCellReuseTests`、`FineCellReuseViewStateTests`、`FineLifecycleIdentityTests`、`FineCollectionSharingTests` を選択し、必要なら実装の担当ファイルを[ソースマップ](../source-map.md)で確認してください。
