# youtube-fetcher

マーケティング侍（りゅう先生）YouTubeチャンネルの動画リスト・トランスクリプトを取得し、
`marketing-context` リポジトリに投入するパイプライン。

## 対象チャンネル

- チャンネル: [@marketing-zamurai](https://www.youtube.com/@marketing-zamurai)
- チャンネル名: マーケティング侍の非常識なビジネス学
- 運営者: りゅう先生（小山竜央）
- チャンネル登録者数: 約10万人
- コンサルティング実績: プロデュースしたチャンネル総登録者数8,000万人超（複数チャンネルの合計）

## セットアップ

```bash
# 依存ツールインストール
brew install yt-dlp
uv sync

# 環境変数設定
cp .env.example .env
# .env に YouTube Data API v3 キーを設定
```

## 使い方

```bash
# 動画リスト取得（APIなしでも動作）
bash scripts/fetch-video-list.sh

# 特定動画のトランスクリプト取得
bash scripts/fetch-transcript.sh <VIDEO_ID>

# 未処理動画を一括取得（1日1回手動実行）
bash scripts/fetch-new-videos.sh

# marketing-context に投入
bash scripts/export-to-context.sh
```

## ディレクトリ構成

```
youtube-fetcher/
├── scripts/
│   ├── fetch-video-list.sh      # 動画リスト取得
│   ├── fetch-transcript.sh      # 1動画のトランスクリプト取得
│   ├── fetch-new-videos.sh      # 未処理動画の一括取得
│   └── export-to-context.sh     # marketing-contextへのエクスポート
├── data/
│   ├── video-list.jsonl         # 動画メタデータ一覧（gitignore対象外）
│   ├── transcripts/             # 生トランスクリプト（gitignore）
│   └── processed/               # クリーニング済みトランスクリプト
├── .env.example
└── pyproject.toml
```

## 設計原則

- LLM呼び出しはこのリポジトリでは行わない（要約はmarketing-context側の責務）
- 取得済み動画IDを `data/video-list.jsonl` で管理し、重複取得しない
- APIキーなしでも `yt-dlp` のみで動作する（APIは動画リスト高速取得用）
- 1スクリプト1責務
