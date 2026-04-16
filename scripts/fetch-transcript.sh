#!/usr/bin/env bash
# fetch-transcript.sh <VIDEO_ID>
# 1動画のトランスクリプト（字幕）を取得してdata/transcripts/<VIDEO_ID>.txt に保存
# 日本語字幕を優先。自動生成字幕もフォールバックで使用。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$REPO_ROOT/data"
TRANSCRIPT_DIR="$DATA_DIR/transcripts"
VIDEO_LIST="$DATA_DIR/video-list.jsonl"

VIDEO_ID="${1:-}"
if [[ -z "$VIDEO_ID" ]]; then
  echo "Usage: $0 <VIDEO_ID>" >&2
  exit 1
fi

mkdir -p "$TRANSCRIPT_DIR"

TRANSCRIPT_FILE="$TRANSCRIPT_DIR/${VIDEO_ID}.txt"
if [[ -f "$TRANSCRIPT_FILE" ]]; then
  echo "[fetch-transcript] スキップ（取得済み）: $VIDEO_ID"
  exit 0
fi

VIDEO_URL="https://www.youtube.com/watch?v=$VIDEO_ID"
echo "[fetch-transcript] トランスクリプト取得中: $VIDEO_ID"

# 字幕を取得（日本語優先、自動生成字幕も許可）
TMPDIR_LOCAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

yt-dlp \
  --write-subs \
  --write-auto-subs \
  --sub-langs "ja,ja-JP" \
  --sub-format "vtt" \
  --skip-download \
  --output "$TMPDIR_LOCAL/%(id)s.%(ext)s" \
  "$VIDEO_URL" \
  2>/dev/null || true

# VTTファイルをプレーンテキストに変換
VTT_FILE=$(find "$TMPDIR_LOCAL" -name "*.vtt" | head -1)
if [[ -z "$VTT_FILE" ]]; then
  echo "[fetch-transcript] 字幕なし: $VIDEO_ID" >&2
  # 字幕なしとして記録（空ファイル+マーカー）
  echo "# NO_SUBTITLE" > "$TRANSCRIPT_FILE"
  exit 0
fi

# VTT → プレーンテキスト変換
# aranobot方式: set で完全一致重複除去 + 改行なし連結
# 細切れ行を1本の連続テキストにすることでトークン数を削減
python3 - "$VTT_FILE" "$TRANSCRIPT_FILE" <<'PYEOF'
import sys, re

vtt_file = sys.argv[1]
out_file = sys.argv[2]

with open(vtt_file, encoding='utf-8') as f:
    content = f.read()

lines = content.splitlines()
seen = set()
texts = []

for line in lines:
    # タイムコード・ヘッダー・空行をスキップ
    if re.match(r'^\d{2}:\d{2}', line):
        continue
    if line.startswith('WEBVTT') or line.startswith('Kind:') or line.startswith('Language:') or line.startswith('NOTE'):
        continue
    # インラインタイムコード・HTMLタグ除去
    line = re.sub(r'<\d{2}:\d{2}:\d{2}\.\d{3}>', '', line)
    line = re.sub(r'<[^>]+>', '', line)
    line = re.sub(r'align:.*$', '', line)
    line = line.strip()
    if not line or line in seen:
        continue
    # [音楽]等のメタ表記をスキップ
    if re.match(r'^\[.+\]$', line):
        continue
    seen.add(line)
    texts.append(line)

# 改行なし連結（細切れ行を1本のテキストに）
result = ''.join(texts)

with open(out_file, 'w', encoding='utf-8') as f:
    f.write(result)

print(f"[fetch-transcript] 変換完了: {len(texts)}ユニーク行 → {len(result)}文字")
PYEOF

echo "[fetch-transcript] 保存: $TRANSCRIPT_FILE"

# video-list.jsonl の transcript_fetched フラグを更新
if [[ -f "$VIDEO_LIST" ]]; then
  python3 - "$VIDEO_LIST" "$VIDEO_ID" <<'PYEOF'
import sys, json

jsonl_path = sys.argv[1]
video_id = sys.argv[2]

lines = []
with open(jsonl_path, encoding='utf-8') as f:
    for line in f:
        obj = json.loads(line)
        if obj.get('id') == video_id:
            obj['transcript_fetched'] = True
        lines.append(json.dumps(obj, ensure_ascii=False))

with open(jsonl_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')
PYEOF
fi
