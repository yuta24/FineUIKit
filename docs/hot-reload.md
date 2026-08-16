# ホットリロード

DEBUG ビルドでは、コード注入(InjectionLite / InjectionIII / InjectionNext)の完了通知を `FineUI` が受け取り、自動で再レンダリングします。

`FineContent.body()` の実装が差し替わると、次の再レンダリングから新しいコードが使われます。**アプリ側にホットリロード用のコードは一切不要です。** 状態は content(`@Observable` なクラス)に住んでいるため、リロードをまたいで保持されます。

**差し替えの単位はシンボルです。** 注入ツールは再コンパイルした 1 ファイルを dylib にし、その中のシンボルをアプリ側のバインディングへ再バインド(interpose)します。これを可能にするのが **`-Xlinker -interposable`**(下のセットアップ手順 2)で、**content を `final class` で書く限り必須**です。

**`final` は要件です。** 非 `final` な class は vtable パッチという別経路でも差し替わり、その経路はフラグを必要としません。ただし**非 final class にメソッドを追加・削除するとクラッシュします**(クラスのメタデータサイズが変わり既存インスタンスと整合しなくなる)。`body()` からヘルパーを切り出すのはホットリロード中に最もよくやる編集なので、この経路は代替になりません。

**クロージャは差し替えられません。** ストアドクロージャは生成時に記述が確定してしまいます。公開 API に記述をクロージャで受け取る入口が無いのはこのためです。逆に、**シンボルとして存在する呼び出しなら種別を問いません** — メソッド、computed property の getter、struct のメソッド、トップレベル関数のいずれも差し替わります。だから記述を `struct MyRow: Renderable` へ切り出してもホットリロードは失われません([コンポーネント](components.md#renderable-で記述を分割する))。

---

## セットアップ

Example アプリでは [InjectionLite](https://github.com/johnno1962/InjectionLite)(GUI アプリ不要)を利用しています。

1. InjectionLite を SPM で追加(またはビルドマシンで InjectionIII.app を起動)
2. Debug 構成の Other Linker Flags に `-Xlinker -interposable` を追加
3. シミュレータでアプリを起動し、ソースを編集・保存すると数秒で画面に反映される

注入が届いて再レンダリングが走ると、画面上部に「FineUIKit reloaded」のトーストが出ます(複数のツリーが再レンダリングされた場合は `×3` のように件数付き)。**「注入が届いていない」のか「届いたが記述が変わらなかった」のか**は画面上は同じに見えるため、前者だけが無音になるこの区別が切り分けの起点になります。不要なら `FineDiagnostics.showsInjectionToast = false`、または環境変数 `FINEUIKIT_INJECTION_TOAST=0` で消せます。

---

## 注意: 差し替えられないコード

境界はアクセス修飾子です。再バインドできるのは **external linkage を持つシンボル**だけで、`private` / `fileprivate` は同一ファイル内でしか参照されないため local シンボルになり、対象から外れます。

| 書き方 | 差し替え |
|---|---|
| `internal` 以上のメソッド / computed property / トップレベル関数（class・struct を問わず） | ✅ |
| `private` / `fileprivate` | ❌ |
| ストアドクロージャ | ❌ |

ホットリロードで書き換えたいロジックは、`private` を外して `internal` にしてください。以前ここには「`body` から辿れる位置に置け」と書いていましたが、実際の制約はこれより緩いものでした。

なお、content を別モジュール（自作の SPM パッケージなど）に置く場合は、**そのモジュールがリンクされるバイナリにもフラグが要ります**。`-interposable` はリンク時に効くので、アプリへ静的リンクされる分にはアプリの設定でカバーされますが、動的フレームワークとして別バイナリになる場合はそちらにも指定が必要です。

---

## 既知の問題(Xcode 27 beta + InjectionLite 1.2.x)

1. **Xcode 27 の SLF ログ形式との非互換** — InjectionLite がビルドログから抽出するコンパイルコマンドの行頭にゴミ(不均衡な引用符)が混入し、`sh: unexpected EOF while looking for matching '"'` で再コンパイルに失敗する。GUI ビルドでも発生する(InjectionLite 側の対応待ち)
2. **注入 dylib の rpath に `/usr/lib/swift` が含まれない** — `libswift_Concurrency.dylib` が見つからず dlopen に失敗することがある
3. **CLI ビルドのみ**: `xcodebuild` には `EMIT_FRONTEND_COMMAND_LINES=YES` を付けないとログに `swift-frontend` の行が残らない。対象ファイルが実際に再コンパイルされたビルドのログにしか行は残らない。加えて `-destination "generic/platform=iOS Simulator"` は arm64 と x86_64 の**両方**をビルドするため、x86_64 のコマンドがログに混ざり、注入時に `unable to load standard library for target 'x86_64-...'` で失敗します。具体的なシミュレータを `-destination "platform=iOS Simulator,id=<UDID>"` で指定してください

1 と 2 は `Scripts/injectionlite-xcode27-fix.sh` で回避できます。クリーンなコマンドだけを含むログを DerivedData に生成し、`PackageFrameworks/` に dylib の symlink を張ります:

```sh
Scripts/injectionlite-xcode27-fix.sh ToDo   # ビルドのたびに実行(スキームの post-action 推奨)
```

新しいビルドを行うと壊れたログが最新になってしまうため、**ビルド後に毎回実行**が必要です。Xcode の Edit Scheme → Build → Post-actions に Run Script として登録しておくと自動化できます。

複数の Example を行き来する場合も注意が必要です。InjectionLite は**最も新しい DerivedData** のビルドログを走査するため、Counter をビルドした直後に ToDo で注入しようとすると、Counter のログを見て「コマンドが見つからない」と言われます。対象アプリを最後にビルドしてください。

### iOS 27 では 2 の回避策が成立しません

**iOS 27 のシミュレータランタイムは `usr/lib/swift/libswift_Concurrency.dylib` をファイルとして持ちません**(dyld shared cache に取り込まれました)。スクリプトが張ろうとする symlink のリンク元が存在しないため、注入 dylib の `dlopen` は次のように失敗します。

```text
⚠️ dlopen failed ... Library not loaded: @rpath/libswift_Concurrency.dylib
```

| ランタイム | `usr/lib/swift/libswift_Concurrency.dylib` |
|---|---|
| iOS 26.x | あり → スクリプトが機能する |
| iOS 27.0 | **無し** → 回避策なし |

**現状の実用的な対処は iOS 26 のシミュレータで動かすことです。** Example のデプロイメントターゲットは `$(RECOMMENDED_IPHONEOS_DEPLOYMENT_TARGET)`(現在 17.0、パッケージの下限と一致)なので、iOS 26 機を選べます。iOS 27 での注入は InjectionLite 側の対応待ちです。

---

## ランタイムは「誰が知らせたか」を知らない

`FineUI` は「リロードが起きた」ことだけを知り、**どのツールがそう言ったのかは知りません**。両者の間には `FineHotReloadBackend`(`Sources/FineUIKit/FineHotReload.swift`、DEBUG 限定)があります。

```swift
protocol FineHotReloadBackend: AnyObject {
    func start()
    func events() -> AsyncStream<FineReloadEvent>
}
```

既定の実装は `FineNotificationHotReloadBackend` で、やることは以前と同じ — `INJECTION_BUNDLE_NOTIFICATION` を `NotificationCenter` から購読し、届いたら `.codeInjected` を流すだけです。**上の「既知の問題」はこの分離では解決しません**(あれはツールチェーン側の問題です)。分離が効くのは別のところです:

- 通知名は InjectionIII / InjectionNext / InjectionLite の**慣習**であって、このライブラリの契約ではありません。ツール側が変えたときに直すのは backend 1 つで、レンダーループには触りません
- 別の仕組み(ファイル監視、ソケット、独自ツール)を足すときも、新しい適合型を1つ書くだけで済みます。**ただしこれは今のところライブラリ内部の話です** — `FineHotReloadBackend` も `FineUI.hotReloadBackend` も internal なので、アプリ側から差し替えることはできません。`FineUI` を internal にしている理由([公開 API の設計判断 §7](api-design.md#7-fineui-は-internal))と同じで、`internal → public` は後から source-compatible に開けますが逆は破壊的なため、必要が出るまで閉じてあります
- テストが `NotificationCenter` を経由しなくなりました。以前はプロセス全体に届く通知を post していたため、テストごとに一意な通知名を作って他のツリーを巻き込まないようにする必要がありました

`events` が property ではなく**メソッド**なのは、**呼ぶたびに専用のストリームを返し、1 回のリロードが全ストリームに届く**契約だからです。`AsyncStream` は各要素を単一のイテレータにしか渡しません。1 本を共有すると、2 つのツリーが 1 つの backend を共有した場合に**リロードが二分され**(両方に届くのではなく)、外れた方は差し替えられたはずの古いコードを黙って動かし続けます — ホットリロードで最も避けたい失敗の仕方です。既定では backend はツリーごとに 1 つですが、共有しても正しく動きます。

ツリーが解放されたら購読も止まります。`FineUI.deinit` が消費側の `Task` を cancel し、backend 側はその終了を `onTermination` で受けて登録を捨てます。backend がツリーより長生きする場合(共有した場合)でも、リロードを待ち続けるタスクも、表示し終えた画面ぶんの登録も残りません。

---

## テストが検証している範囲

`FineHotReloadTests` が検証しているのは配線だけです — backend がリロードを報告したら再レンダリングすること、2 回目の `build(to:)` が二重購読しないこと、1 つの backend を共有した全ツリーがリロードされること、既定の backend が `INJECTION_BUNDLE_NOTIFICATION` を購読すること、解放されたツリーが購読と登録を手放すこと。実際の dylib 差し替えは行いません。

InjectionLite/InjectionIII/InjectionNext が実際にコードを注入できるかどうかはビルド環境・ツールのバージョンに依存し、自動テストではカバーされていません(上記「既知の問題」参照)。ホットリロードが実際に機能するかどうかは、都度手元の環境で確認してください。

---

## 参考

- 差し替えの単位と、そこから決まった API の形: [公開 API の設計判断](api-design.md#2-差し替えの単位はシンボルでありクロージャは差し替えられない)
- `final` を要件にした判断: [同 §3](api-design.md#3-content-は-final-class-でなければならない)
