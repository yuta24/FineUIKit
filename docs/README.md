# FineUIKit ドキュメント

## 使い方

| ドキュメント | 内容 |
|---|---|
| [はじめかた](getting-started.md) | `FineContent` の書き方、`FineContentController` でのマウント、ナビゲーション |
| [コンポーネント](components.md) | 組み込みコンポーネント一覧、`FineViewRepresentable`、キーボード |
| [状態とバインディング](state.md) | `FineBinding`、フォーカス、`FineState`、Environment |
| [モディファイアとレイアウト](layout.md) | 外観・レイアウト・インタラクションのモディファイア、Auto Layout ネイティブな制約 API |
| [レンダリングの挙動](rendering.md) | keyed diff、Dynamic Type と trait、ライフサイクル、画面が隠れている間の停止、アニメーション |
| [メモリ管理](memory.md) | キャプチャの安全性、守るべきルール、状態の置き場所、入れ子 |
| [診断](diagnostics.md) | ビューが作り直された理由のログ、レンダリング回数、ハイライト、ツリーダンプ、signpost |
| [ホットリロード](hot-reload.md) | コード注入のセットアップ、`-Xlinker -interposable`、既知の問題 |

## 設計と内部

| ドキュメント | 内容 |
|---|---|
| [内部アーキテクチャ](architecture.md) | 記述層 / `FineNode` / `UIView` の三層、差分適用、observation の粒度 |
| [公開 API の設計判断](api-design.md) | 現在の API 形状に至った判断とその根拠 |

概要とクイックスタートは [README](../README.md) にあります。
