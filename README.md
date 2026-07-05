# FineUIKit

UIKit の上に宣言的 UI とホットリロードをもたらす実験的ライブラリ。

Rust の [Dioxus](https://dioxuslabs.com) と同じ設計方針 — 「UI を記述(データ)として扱い、ランタイムが差分適用する」 — を UIKit に適用したものです。UI 記述と UIView を分離しているため、状態変化・コード注入のどちらでも「記述を作り直して差分適用する」だけで画面が更新されます。

## 使い方

`FineViewController` を継承し、`@Observable` な状態を渡して `body(_:)` を override します。

```swift
import FineUIKit
import Observation

@Observable
final class ToDoListViewModel {
    var items: [ToDo] = []
}

final class ToDoListViewController: FineViewController<ToDoListViewModel> {
    init() {
        super.init(state: .init())
    }

    override func body(_ viewModel: ToDoListViewModel) -> any Renderable {
        FineStack.vertical(spacing: 8) {
            [
                FineLabel(text: "\(viewModel.items.count) items"),
                FineButton(title: "Add") {
                    viewModel.items.append(.init(title: "Task \(viewModel.items.count + 1)"))
                },
                FineList(viewModel.items) { item in
                    FineLabel(text: item.title)
                },
            ]
        }
    }
}
```

`body` 内で読んだ `@Observable` プロパティが変化すると自動で再レンダリングされます。ビューは作り直されず、互換なビューは in-place 更新されます(`FineStack` の子は位置ベース、`FineList` は `Identifiable` の ID ベースで差分適用)。

既存の View Controller に部分導入する場合は、低レベル API の `FineUI` を直接使えます(インスタンスの強参照保持が必要です)。

## アーキテクチャ

- `Renderable` — UI 記述のプロトコル。`_makeView()`(生成)/ `_canUpdate(_:)`(再利用可否)/ `_update(_:)`(適用)を実装する値型
- `FineRenderer` — 「互換なら既存ビューを更新、非互換なら作り直し」を行う差分適用層
- `FineUI` — `withObservationTracking` で「body 再評価 → 差分適用」のループを回すランタイム
- `FineViewController` — 上記をまとめた推奨インターフェース

## ホットリロード

DEBUG ビルドでは、コード注入(InjectionLite / InjectionIII / InjectionNext)の完了通知を `FineUI` が受け取り、自動で再レンダリングします。

`FineViewController` の `body` は vtable 経由で動的ディスパッチされるメソッドなので、注入によって実装が差し替わると、次の再レンダリングから新しいコードが使われます。**アプリ側にホットリロード用のコードは一切不要です。** 状態は `@Observable` オブジェクトに住んでいるため、リロードをまたいで保持されます。

Example アプリでは [InjectionLite](https://github.com/johnno1962/InjectionLite)(GUI アプリ不要)を利用しています。セットアップ:

1. InjectionLite を SPM で追加(またはビルドマシンで InjectionIII.app を起動)
2. Debug 構成の Other Linker Flags に `-Xlinker -interposable` を追加
3. シミュレータでアプリを起動し、ソースを編集・保存すると数秒で画面に反映される

### 注意: `body` の外に書いたコードの差し替え

Xcode の新リンカ(chained fixups)環境では、`private` メソッドへの直接呼び出しなど静的ディスパッチされるコードは注入で差し替わりません。確実に差し替わるのは、クラスの vtable 経由(`FineViewController.body` の override)か ObjC ディスパッチ(`@objc dynamic`)のコードです。ホットリロードで書き換えたいロジックはできるだけ `body` から辿れる位置に置いてください。

### 既知の問題(Xcode 27 beta + InjectionLite 1.2.x、CLI ビルド時)

Xcode の GUI から普通にビルド・実行する場合は不要ですが、`xcodebuild` CLI でビルドしたアプリで InjectionLite を使う場合は以下が必要でした:

1. **`EMIT_FRONTEND_COMMAND_LINES=YES` を付けてビルドする** — InjectionLite はビルドログから `swift-frontend -primary-file` の行を探すため。対象ファイルが実際に再コンパイルされたビルドのログにしか行は残らない
2. **Xcode 27 の SLF ログ形式との非互換** — 抽出したコマンド行に引用符が不均衡なゴミが混入し再コンパイルに失敗することがある(InjectionLite 側の対応待ち)
3. **注入 dylib の rpath に `/usr/lib/swift` が含まれない** — `libswift_Concurrency.dylib` が見つからず dlopen に失敗する場合、DerivedData の `Debug-iphonesimulator/PackageFrameworks/` へ symlink を置くと回避できる
