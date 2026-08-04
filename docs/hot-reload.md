# ホットリロード

DEBUG ビルドでは、コード注入(InjectionLite / InjectionIII / InjectionNext)の完了通知を `FineUI` が受け取り、自動で再レンダリングします。

`FineContent.body()` はメソッドなので注入が名前で辿れます(`final` なら symbol の再バインド、非 `final` なら vtable スロットの差し替え)。実装が差し替わると、次の再レンダリングから新しいコードが使われます。**アプリ側にホットリロード用のコードは一切不要です。** 状態は content(`@Observable` なクラス)に住んでいるため、リロードをまたいで保持されます。

**これが `body` をクロージャではなくメソッドにしている理由**です。ストアドクロージャは生成時に記述が確定してしまい、注入では差し替えられません。公開 API に記述をクロージャで受け取る入口が無いのはこのためです。

差し替えの経路は content クラスが `final` かどうかで変わります。

| content の宣言 | 呼び出し | 注入の経路 |
|---|---|---|
| `final class`（推奨・例もこちら） | protocol witness が直接呼び出し | **symbol interposition** → `-Xlinker -interposable` が必要 |
| 非 `final` な `class` | witness thunk が vtable 経由 | vtable スロットの差し替え → フラグ不要 |

つまり **`final class` で書く限り `-Xlinker -interposable` は必須**です（下のセットアップ手順 2 がこれにあたります）。`final` を外せばフラグ無しでも差し替わりますが、Swift の慣習に反するので推奨しません。

---

## セットアップ

Example アプリでは [InjectionLite](https://github.com/johnno1962/InjectionLite)(GUI アプリ不要)を利用しています。

1. InjectionLite を SPM で追加(またはビルドマシンで InjectionIII.app を起動)
2. Debug 構成の Other Linker Flags に `-Xlinker -interposable` を追加
3. シミュレータでアプリを起動し、ソースを編集・保存すると数秒で画面に反映される

注入が届いて再レンダリングが走ると、画面上部に「FineUIKit reloaded」のトーストが出ます(複数のツリーが再レンダリングされた場合は `×3` のように件数付き)。**「注入が届いていない」のか「届いたが記述が変わらなかった」のか**は画面上は同じに見えるため、前者だけが無音になるこの区別が切り分けの起点になります。不要なら `FineDiagnostics.showsInjectionToast = false`、または環境変数 `FINEUIKIT_INJECTION_TOAST=0` で消せます。

---

## 注意: `body` の外に書いたコードの差し替え

Xcode の新リンカ(chained fixups)環境では、`private` メソッドへの直接呼び出しなど静的ディスパッチされるコードは注入で差し替わりません。確実に差し替わるのは、メソッドとして宣言されたコード(`FineContent.body()` の実装)か ObjC ディスパッチ(`@objc dynamic`)のコードです。ホットリロードで書き換えたいロジックはできるだけ `body` から辿れる位置に置いてください。

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

## テストが検証している範囲

`FineUITests.injectionRerenderDoesNotLeaveStaleObservationActive` は「注入完了通知を受け取ったら再レンダリングする」という `FineUI` 側の配線だけを検証しています(`NotificationCenter` で通知を手動 post するテストで、実際の dylib 差し替えは行いません)。InjectionLite/InjectionIII/InjectionNext が実際にコードを注入できるかどうかはビルド環境・ツールのバージョンに依存し、自動テストではカバーされていません(上記「既知の問題」参照)。ホットリロードが実際に機能するかどうかは、都度手元の環境で確認してください。

---

## 参考

- `body()` をメソッドにした判断: [公開 API の設計判断](api-design.md#2-body-はメソッドでありクロージャではない)
