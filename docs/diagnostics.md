# 診断(なぜビューが作り直されたか)

差分適用は「型 + モディファイア署名 + key」が一致したときだけ in-place 更新し、それ以外はビューを作り直します。作り直し自体は正しい動作ですが、意図しない作り直しはフォーカス・スクロール位置・`FineState` を失わせます。原因を知りたいときは診断を有効にしてください。

```swift
FineDiagnostics.logsViewReuse = true
```

スキームの環境変数 `FINEUIKIT_LOG_REUSE=1` でも有効になります。出力例:

```text
FineUIKit rebuilt UILabel for FineLabel: modifier composition changed ("|backgroundColor" → "|backgroundColor|cornerRadius")
FineUIKit rebuilt UITextField for FineTextField: key changed (a → b)
FineUIKit rebuilt UILabel for FineImage: view type is incompatible
FineUIKit rebuilt UILabel for FineLabel: modifier composition changed ("composite.ToDo.Header|" → "composite.ToDo.Footer|")
```

最後の形は、自作の `Renderable` を別の型へ入れ替えたときに出ます。署名の `composite.` は「その primitive へ解決するまでに通った `Renderable` 型」で、型が変わればビューは作り直されます([コンポーネント](components.md#renderable-で記述を分割する))。

既定では `OSLog` に出力します。`FineDiagnostics.handler` を差し替えれば、テストや自前のコンソールへ流せます。

---

## なぜこのビューが更新されたのか

各ビューには**最後のレンダーの理由**と**所要時間**も記録されます。回数と同じく常時有効です。

| 理由 | 意味 |
|---|---|
| `because it is new here` | その位置での最初のレンダー |
| `because its parent re-rendered` | 上のスコープが再レンダーして、その通り道になった |
| `because a value it read changed` | このノード(またはホストするセル)が読んだ値が変わった |
| `because code was injected` | コード注入で実装が差し替わった |

作り直しの理由(`rebuilds`)が「**ビューがどうなったか**」を答えるのに対し、こちらは「**誰が頼んだか**」を答えます。両方揃うと「ラベルがキーストロークのたびに作り直されている」が探索ではなく一文になります。

```text
FineStack → UIStackView  renders 1  because it is new here            330.17 µs
  FineLabel → UILabel    renders 2  because a value it read changed    80.67 µs
  FineLabel → UILabel    renders 1  because it is new here              6.46 µs
```

`renders 2` かつ `a value it read changed` なのが片方のラベルだけで、兄弟も親のスタックも `renders 1` のまま。**ノード単位で更新が閉じている**ことがそのまま読めます。

**時間はそのノードの `_update` にかかったぶんです。** ランタイム(`FineContentController` 経由)ではコンテナの更新が子をスケジューラへ渡して戻り、子はそれぞれの順番が来たときに計測されるので、**枝を下った数字は入れ子ではなく独立**しています。足し合わせて上の数字になるものではありません(コンテナの数字に子の**ビュー生成**は含まれます — 親の更新中に起きるので)。

`FineRenderer.render(_:reusing:)` を直接呼ぶ場合はスケジューラが無く、`_update` がその場で子まで再帰するため、**そちらの数字は子孫を含みます**。テストから直接描画したときに数字の意味が変わるのはこのためです。

> ⚠️ **どの値が変わったかは分かりません。** `withObservationTracking` は「読んだ何かが変わった」ことだけを報告し、変更されたプロパティを渡しません。`a value it read changed` がランタイムに言える限界で、`movie.title が変わった`のような特定はできません。どの値かを絞りたいときは、読み取りを別のノードへ切り分ける(`FineLabel(text:)` の autoclosure に通す)のが実用的な方法です。

---

## レンダリング回数

各ビューには「その位置で何回レンダリングされたか(`renders`)」「そのうち何回ビューを作り直したか(`rebuilds`)」が常に記録されます。フラグ不要・常時有効で、コストは整数のインクリメント2回です。作り直しの際はカウンタが新しいビューへ引き継がれるため、数字はビュー個体ではなく**ツリー上の位置**を表します。

作り直しに至らない再レンダリングも含めて全件ログに出したいときは:

```swift
FineDiagnostics.logsRenders = true  // または FINEUIKIT_LOG_RENDERS=1
```

```text
FineUIKit created UILabel for FineLabel because it is new here (render #1, 0 rebuilt, 6.46 µs)
FineUIKit updated UILabel for FineLabel because a value it read changed (render #2, 0 rebuilt, 80.67 µs)
```

名乗るのは**ビューを作ったコンポーネント**です。`.backgroundColor()` や `.key()` は content のビューにそのまま描画する(自前のビューを作らない)ため、`FineStyled` / `FineKeyed` ではなく `FineLabel` と表示されます。適用されたモディファイア自体は署名の方に出ます。

---

## 再レンダリングのハイライト

再レンダリングされたビューの輪郭が一瞬光ります。**緑 = in-place 更新、赤 = 作り直し**で、数字はそのビューの累計レンダリング回数です。

```swift
FineDiagnostics.highlightsRenders = true  // または FINEUIKIT_HIGHLIGHT_RENDERS=1
```

ビュー自身の `layer.border` ではなく専用のサブレイヤーを重ねるため、枠線を持つコンポーネントの見た目を壊さず、タップも吸いません。DEBUG ビルド限定です。フレームレートを計測するときはオフにしてください(オーバーレイの描画コストが計測対象を上回ります)。

---

## ツリーのダンプとビューの説明

Xcode の View Debugger は `UILabel` は見せますが、それを作った `FineLabel`・key・モディファイア署名は見せません。デバッガから:

```text
(lldb) po view.fineDumpTree()
FineStack → UIStackView  renders 1
  FinePadded → FinePaddingView  renders 1  modifiers "padding"
    FineLabel → UILabel  renders 3
  FineStack → UIStackView  renders 1
    FineTextField → FineTextFieldView  renders 1  key draft
      UITextFieldLabel (unmanaged)
    FineButton → UIButton  renders 1  modifiers "|backgroundColor"
      UIButtonLabel (unmanaged)

(lldb) po someLabel.fineDebugDescription
FineLabel → UILabel  renders 3
```

この例では、ラベルだけが `renders 3`、親は `renders 1` です。テキストがノード単位で3回更新され、ツリーの再 diff は1回も起きていないことがそのまま読み取れます。作り直しがあれば `rebuilds N` が付き、`FineState` を持つノードには `state` が付きます。

FineUIKit が管理していないビュー(UIKit が内部で作るラベルなど)は `unmanaged` と表示されます。どちらも observable な状態を読まないので、ブレークポイントから呼んでもレンダリングループを乱しません。

---

## makeView() の中で状態を読んでしまった場合

`FineViewRepresentable.makeView()` は**ビュー identity ごとに1回**しか呼ばれず、しかも**観測スコープの外**で実行されます(追跡されるのは `_update` だけです)。そのため、ここで `@Observable` な値を読んでも登録は行われず、後からその値が変わっても**何も起きません** — 再レンダリングもエラーも無く、ビューは最初の値を表示し続けます。

```swift
struct Badge: FineViewRepresentable {
    let model: Model

    func makeView() -> UILabel {
        let label = UILabel()
        label.text = model.title      // ← 効きません
        return label
    }

    func updateView(_ view: UILabel, environment: FineEnvironmentValues) {}
}
```

DEBUG ビルドでは、**その値が実際に変化した時点で**次のように報告されます(変化しなければ実害が無いので何も出ません)。

```text
FineUIKit FineRepresentableAdapter<Badge>: a value read while creating its view has changed.
makeView() runs once per view identity and outside observation tracking, so this change
will not be applied — read the value in updateView(_:environment:) instead, which runs on
every render.
```

出力先は `FineDiagnostics.handler` です(既定は `OSLog`)。

**読み取りは `updateView(_:environment:)` に移してください。** こちらは毎レンダリング呼ばれ、観測スコープの内側です。

---

## Instruments(signpost)

3つのレンダリングループが Points of Interest に signpost 区間を出します。Time Profiler や Animation Hitches のテンプレートでそのまま見えるため、専用テンプレートは不要です。

| 区間 | 意味 |
|---|---|
| `render` | ルートの再レンダリング(`body()` の再評価とツリーの再 diff) |
| `node` | ノード単位の更新(観測起因のノードローカル再レンダリングを含む。記述の型名付き) |
| `cell` | リスト / グリッドのセルが抱えるサブツリー |

計測ツールが記録していなければ何も出力されないため、release ビルドにもそのまま残ります。

---

## 参考

- 何がビューの再利用を決めるか: [内部アーキテクチャ](architecture.md#4-差分適用reconciliation)
- モディファイア署名: [モディファイアとレイアウト](layout.md#モディファイア)
