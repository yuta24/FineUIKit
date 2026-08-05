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

## レンダリング回数

各ビューには「その位置で何回レンダリングされたか(`renders`)」「そのうち何回ビューを作り直したか(`rebuilds`)」が常に記録されます。フラグ不要・常時有効で、コストは整数のインクリメント2回です。作り直しの際はカウンタが新しいビューへ引き継がれるため、数字はビュー個体ではなく**ツリー上の位置**を表します。

作り直しに至らない再レンダリングも含めて全件ログに出したいときは:

```swift
FineDiagnostics.logsRenders = true  // または FINEUIKIT_LOG_RENDERS=1
```

```text
FineUIKit created UILabel for FineLabel (render #1, 0 rebuilt)
FineUIKit rebuilt UILabel for FineLabel (render #2, 1 rebuilt)
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
