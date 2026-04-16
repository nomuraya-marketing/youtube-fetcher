#!/usr/bin/env bash
# fetch-new-videos.sh
# video-list.jsonl のうち transcript_fetched=false の動画を順番に取得する
# 1日1回手動実行を想定。launchd/cronでの自動実行は行わない。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$REPO_ROOT/data"
VIDEO_LIST="$DATA_DIR/video-list.jsonl"

if [[ ! -f "$VIDEO_LIST" ]]; then
  echo "[fetch-new-videos] video-list.jsonlが存在しません。先に fetch-video-list.sh を実行してください" >&2
  exit 1
fi

# transcript_fetched=false の動画IDを抽出
PENDING=$(python3 -c "
import json, sys
with open('$VIDEO_LIST') as f:
    for line in f:
        obj = json.loads(line)
        if not obj.get('transcript_fetched', False):
            # NO_SUBTITLEファイルがあればスキップ
            import os
            transcript_path = '$DATA_DIR/transcripts/' + obj['id'] + '.txt'
            if os.path.exists(transcript_path):
                continue
            print(obj['id'])
")

COUNT=$(echo "$PENDING" | grep -c . || true)
echo "[fetch-new-videos] 未取得: ${COUNT}件"

if [[ $COUNT -eq 0 ]]; then
  echo "[fetch-new-videos] 未処理の動画はありません"
  exit 0
fi

# 最大処理件数（一度に大量取得しない）
MAX_PER_RUN="${MAX_PER_RUN:-10}"
PROCESSED=0

echo "$PENDING" | head -n "$MAX_PER_RUN" | while read -r video_id; do
  echo "---"
  bash "$SCRIPT_DIR/fetch-transcript.sh" "$video_id"
  PROCESSED=$((PROCESSED + 1))
  # YouTube のレート制限を避けるため少し待つ
  sleep 2
done

echo "[fetch-new-videos] 今回取得: 最大${MAX_PER_RUN}件"
echo "[fetch-new-videos] 残り: $((COUNT - MAX_PER_RUN > 0 ? COUNT - MAX_PER_RUN : 0))件"
