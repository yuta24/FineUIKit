---
type: "Project Guide"
title: "FineUIKit クイックスタート"
description: "iOS 17 以上の UIKit 向け宣言的 UI ライブラリ FineUIKit の目的、利用開始、設計と保守ドキュメントへの入口。"
tags: [swift, ios, uikit, declarative-ui]
---

# FineUIKit クイックスタート

FineUIKit は、UIKit の上で `Renderable` による宣言的 UI を記述し、Swift Observation で検出した状態変化を既存の `UIView` ツリーへ差分適用する実験的ライブラリです。Swift Package として `FineUIKit` を公開し、最低対応は iOS 17、Swift 言語モードは 6 です（[Package.swift](../Package.swift)）。

設計の中心は「記述は再作成できる値、`UIView` と状態の保持は永続ノード」という分離です。このランタイム構造は[アーキテクチャ概要](architecture/overview.md)で、状態変化がどの粒度で更新されるかは[レンダリングワークフロー](workflows/rendering.md)で説明します。

## 最小の使い方

`@Observable` なクラスを `FineContent` に適合させ `body() -> any Renderable` を実装し、`FineContentController(content)` で画面としてマウントします。`body` 内で読んだ値は観測対象となり、互換なビューは作り直さず更新されます。

```swift
import FineUIKit
import Observation

@Observable
final class ScreenContent: FineContent {
    var title = "Hello"

    func body() -> any Renderable {
        FineStack.vertical {
            FineLabel(text: title)
        }
    }
}

let controller = FineContentController(ScreenContent())
navigationController.pushViewController(controller, animated: true)
```

公開 DSL、`FineState`、environment、ライフサイクル、独自 `UIView` のラップは[UI 合成と状態](domain/ui-composition.md)が正本です。リスト、グリッド、ナビゲーション、ホストは[UIKit 統合とコレクション](integrations/uikit-collections.md)を参照してください。

## 保守者向けの最短経路

1. 描画や局所更新を変える: [アーキテクチャ概要](architecture/overview.md) → [レンダリングワークフロー](workflows/rendering.md) → [テストと運用](operations/testing.md)。
2. コンポーネントやモディファイアを変える: [UI 合成と状態](domain/ui-composition.md) → [ソースマップ](source-map.md)。
3. `FineList` / `FineGrid`、セル、ナビゲーション、ホストを変える: [UIKit 統合とコレクション](integrations/uikit-collections.md) → [テストと運用](operations/testing.md)。
4. レンダリング計測・デバッグ診断を変える: [レンダリング計測とデバッグ診断](operations/diagnostics.md) → [テストと運用](operations/testing.md)。

## リポジトリの地図

- `Sources/FineUIKit/`: ランタイム、公開 DSL、UIKit コンポーネント。
- `Tests/FineUIKitTests/`: Swift Testing 中心の振る舞い・回帰テストと、XCTest ベースの性能テスト。
- `docs/architecture.md`: 実装内部を詳細に解説する既存設計書。本 Wiki は更新時の導線と判断を優先して要約します。
- `Example/`: 利用例アプリ、`Scripts/`: 補助スクリプト。

領域別の入口は[ソースマップ](source-map.md)に集約しています。

## 変更時の不変条件

- `Renderable.body` は副作用を持たず、同じ状態から同じ記述を返す必要があります。レンダラーはメタデータや primitive 解決のために複数回評価し得ます（[レンダリングワークフロー](workflows/rendering.md)）。
- 再利用はビュー型・モディファイア署名・key の一致に依存します。identity やモディファイア構成を変えるとビューと `FineState` は再作成されます（[UI 合成と状態](domain/ui-composition.md)）。
- List/Grid は無関係な root render で snapshot apply を行わない設計です。変更時は diff、supplementary view、セル局所観測のテストを優先します（[UIKit 統合とコレクション](integrations/uikit-collections.md)）。

## Backlog

- なし。初期調査で確認した主要領域（ランタイム、DSL、UIKit 統合、コレクション、CI・テスト）は本 Wiki に記録済みです。
