#!/usr/bin/env bash
# add-video.sh <VIDEO_ID>
# 新規動画1本をfetch → export → RAG化まで1コマンドで完結
# 既存動画の再処理にも使用可（強制上書き）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

VIDEO_ID="${1:-}"
if [[ -z "$VIDEO_ID" ]]; then
  echo "Usage: $0 <VIDEO_ID>" >&2
  echo "  例: $0 dQw4w9WgXcQ" >&2
  exit 1
fi

# .envからMARKETING_CONTEXT_PATHを読み込む
MARKETING_CONTEXT_PATH="${MARKETING_CONTEXT_PATH:-$REPO_ROOT/../marketing-context}"
if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
fi
MARKETING_CONTEXT_PATH="$(cd "$MARKETING_CONTEXT_PATH" 2>/dev/null && pwd)"

echo "[add-video] 開始: $VIDEO_ID"

# Step 1: トランスクリプト取得
echo "[add-video] Step 1/3: fetch-transcript"
MARKETING_CONTEXT_PATH="$MARKETING_CONTEXT_PATH" \
  bash "$SCRIPT_DIR/fetch-transcript.sh" "$VIDEO_ID"

# Step 2: marketing-contextへエクスポート
echo "[add-video] Step 2/3: export-to-context"
MARKETING_CONTEXT_PATH="$MARKETING_CONTEXT_PATH" \
  bash "$SCRIPT_DIR/export-to-context.sh" "$VIDEO_ID"

# Step 3: チャンク分割 + DB upsert
echo "[add-video] Step 3/3: db-upsert"
bash "$MARKETING_CONTEXT_PATH/scripts/db-upsert.sh" "$VIDEO_ID"

echo "[add-video] 完了: $VIDEO_ID"
