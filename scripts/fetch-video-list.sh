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
# --dump-json: 各動画をJSONで出力（タイトルにタブ・改行が含まれても安全）
TMPJSONL=$(mktemp)
trap 'rm -f "$TMPJSONL"' EXIT

yt-dlp \
  --flat-playlist \
  --dump-json \
  "$CHANNEL_URL/videos" \
  2>/dev/null > "$TMPJSONL"

python3 <<PYEOF
import json, os

video_list_path = "$VIDEO_LIST"
tmp_path = "$TMPJSONL"

# 既存IDを読み込む
existing_ids = set()
if os.path.exists(video_list_path):
    with open(video_list_path, encoding='utf-8') as f:
        for line in f:
            try:
                obj = json.loads(line)
                existing_ids.add(obj['id'])
            except Exception:
                pass

added = 0
with open(video_list_path, 'a', encoding='utf-8') as out, open(tmp_path, encoding='utf-8') as inp:
    for line in inp:
        try:
            d = json.loads(line)
        except Exception:
            continue
        video_id = d.get('id', '')
        if not video_id or video_id in existing_ids:
            continue
        record = {
            'id': video_id,
            'title': d.get('title', ''),
            'upload_date': d.get('upload_date', ''),
            'duration': d.get('duration', 0),
            'view_count': d.get('view_count', 0),
            'url': f"https://www.youtube.com/watch?v={video_id}",
            'transcript_fetched': False,
        }
        out.write(json.dumps(record, ensure_ascii=False) + '\n')
        existing_ids.add(video_id)
        added += 1
        print(f"[fetch-video-list] 追加: {video_id} - {record['title'][:40]}")

print(f"[fetch-video-list] 新規追加: {added}件")
PYEOF

TOTAL=$(wc -l < "$VIDEO_LIST" | tr -d ' ')
echo "[fetch-video-list] 完了: 合計 $TOTAL 件"
