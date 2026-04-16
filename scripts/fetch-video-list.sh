#!/usr/bin/env bash
# fetch-video-list.sh
# マーケティング侍チャンネルの動画リストを取得してdata/video-list.jsonlに追記
# yt-dlp のみで動作（APIキー不要）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$REPO_ROOT/data"
VIDEO_LIST="$DATA_DIR/video-list.jsonl"
CHANNEL_URL="https://www.youtube.com/@marketing-zamurai"

# .envがあれば読み込む
if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
fi

mkdir -p "$DATA_DIR"

echo "[fetch-video-list] 動画リストを取得中: $CHANNEL_URL"

# yt-dlp でチャンネルの全動画メタデータをJSONLで取得
# --flat-playlist: メタデータのみ（ダウンロードなし）
# --print-json: 各動画をJSON1行で出力
yt-dlp \
  --flat-playlist \
  --print "%(id)s\t%(title)s\t%(upload_date)s\t%(duration)s\t%(view_count)s" \
  "$CHANNEL_URL/videos" \
  2>/dev/null \
| while IFS=$'\t' read -r id title upload_date duration view_count; do
    # 既に取得済みかチェック
    if [[ -f "$VIDEO_LIST" ]] && grep -q "\"id\":\"$id\"" "$VIDEO_LIST" 2>/dev/null; then
      continue
    fi
    # JSONL形式で追記
    printf '{"id":"%s","title":%s,"upload_date":"%s","duration":%s,"view_count":%s,"url":"https://www.youtube.com/watch?v=%s","transcript_fetched":false}\n' \
      "$id" \
      "$(echo "$title" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')" \
      "$upload_date" \
      "${duration:-0}" \
      "${view_count:-0}" \
      "$id" \
    >> "$VIDEO_LIST"
    echo "[fetch-video-list] 追加: $id - $title"
  done

TOTAL=$(wc -l < "$VIDEO_LIST" | tr -d ' ')
echo "[fetch-video-list] 完了: 合計 $TOTAL 件"
