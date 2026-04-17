#!/usr/bin/env bash
# export-to-context.sh [VIDEO_ID]
# 取得済みトランスクリプトをmarketing-contextリポジトリ形式に変換してコピー
# VIDEO_IDを指定すると1動画のみ処理。省略すると未エクスポート全件を処理。
# LLMによる要約はmarketing-context側で行う（このスクリプトはLLM不使用）
# チャンク分割・DB更新は呼び出し元（add-video.sh等）で行う。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$REPO_ROOT/data"
VIDEO_LIST="$DATA_DIR/video-list.jsonl"
TRANSCRIPT_DIR="$DATA_DIR/transcripts"

TARGET_VIDEO_ID="${1:-}"

# .envからCONTEXT_PATHを読み込む
MARKETING_CONTEXT_PATH="${MARKETING_CONTEXT_PATH:-../marketing-context}"
if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
fi

CONTEXT_RAW_DIR="$MARKETING_CONTEXT_PATH/raw/transcripts"
mkdir -p "$CONTEXT_RAW_DIR"

if [[ ! -f "$VIDEO_LIST" ]]; then
  echo "[export] video-list.jsonlが存在しません" >&2
  exit 1
fi

python3 - "$VIDEO_LIST" "$TRANSCRIPT_DIR" "$CONTEXT_RAW_DIR" "$TARGET_VIDEO_ID" <<'PYEOF'
import json, sys, os

jsonl_path = sys.argv[1]
transcript_dir = sys.argv[2]
context_dir = sys.argv[3]
target_id = sys.argv[4]  # 空文字なら全件

exported = 0
with open(jsonl_path, encoding='utf-8') as f:
    for line in f:
        obj = json.loads(line)
        video_id = obj['id']

        # VIDEO_ID指定時は対象のみ処理
        if target_id and video_id != target_id:
            continue

        transcript_file = os.path.join(transcript_dir, f"{video_id}.txt")
        if not os.path.exists(transcript_file):
            continue

        # NO_SUBTITLEはスキップ
        with open(transcript_file, encoding='utf-8') as tf:
            first_line = tf.readline().strip()
        if first_line == '# NO_SUBTITLE':
            continue

        dest_path = os.path.join(context_dir, f"{video_id}.json")
        if os.path.exists(dest_path) and not target_id:
            continue  # 全件モードでは既エクスポート済みをスキップ
        # VIDEO_ID指定時は強制上書き（再エクスポート）

        with open(transcript_file, encoding='utf-8') as tf:
            transcript_text = tf.read()

        record = {
            'id': video_id,
            'title': obj.get('title', ''),
            'upload_date': obj.get('upload_date', ''),
            'url': obj.get('url', f"https://www.youtube.com/watch?v={video_id}"),
            'duration': obj.get('duration', 0),
            'view_count': obj.get('view_count', 0),
            'transcript': transcript_text,
            'summarized': False,
        }

        with open(dest_path, 'w', encoding='utf-8') as out:
            json.dump(record, out, ensure_ascii=False, indent=2)
        exported += 1
        print(f"[export] エクスポート: {video_id}")

print(f"[export] 完了: {exported}件")
PYEOF
