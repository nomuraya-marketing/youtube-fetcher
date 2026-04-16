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
# 細切れ行を1本の連続テキストにしてからbudoux分かち書き+定型句除去
MARKETING_CONTEXT_PATH="${MARKETING_CONTEXT_PATH:-$REPO_ROOT/../marketing-context}"
if [[ -f "$REPO_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
fi
# 相対パスを絶対パスに解決
MARKETING_CONTEXT_PATH="$(cd "$MARKETING_CONTEXT_PATH" 2>/dev/null && pwd || echo "")"
VENV_PYTHON=""
if [[ -n "$MARKETING_CONTEXT_PATH" && -f "$MARKETING_CONTEXT_PATH/.venv/bin/python3" ]]; then
  VENV_PYTHON="$MARKETING_CONTEXT_PATH/.venv/bin/python3"
fi
if [[ -z "$VENV_PYTHON" ]]; then
  VENV_PYTHON="python3"
fi

"$VENV_PYTHON" - "$VTT_FILE" "$TRANSCRIPT_FILE" <<'PYEOF'
import sys, re

vtt_file = sys.argv[1]
out_file = sys.argv[2]

# チャンネル固有の定型句パターン（マーケティング侍）
# 注意: YouTube自動字幕はWhisperエラーで文字化けが多い（例: 戦国自体→戦国時代）
# 実測パターンと標準形の両方を網羅する
BOILERPLATE_PATTERNS = [
    # イントロ定型句（実測バリエーション + 標準形）
    r'時は令和ビジネス戦国.{0,5}ビジネスの常識を.{0,10}切るマーケティング侍の非常識なビジネス.{0,5}',
    r'時は令和ビジネス戦国.{0,5}マーケティング侍の非常識なビジネス.{0,5}',
    # 自己紹介定型句
    r'マーケティング侍の.{0,5}(り|龍|竜)です',
    r'ちゃ?お?マーケティング侍',
    r'このチャンネルでは.{0,10}(実践的な|今すぐ使える).{0,20}マーケティングを.{0,20}(シェア|公開)',
    # アウトロ定型句
    r'チャンネル登録よろしくお願いします',
    r'いいね.{0,3}ボタン.{0,5}押して.{0,20}',
]

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
joined = ''.join(texts)

# 定型句除去
cleaned = joined
for pat in BOILERPLATE_PATTERNS:
    cleaned = re.sub(pat, '', cleaned)
# 連続スペース除去
cleaned = re.sub(r'\s{2,}', '', cleaned)

# budoux 分かち書き（インストール済みの場合のみ適用）
try:
    import budoux
    parser = budoux.load_default_japanese_parser()
    # budoux で文境界を検出して改行挿入
    words = parser.parse(cleaned)
    result = '\n'.join(words)
    budoux_applied = True
except ImportError:
    result = cleaned
    budoux_applied = False

removed_chars = len(joined) - len(cleaned)
with open(out_file, 'w', encoding='utf-8') as f:
    f.write(result)

budoux_note = "(budoux分かち書き適用)" if budoux_applied else "(budoux未インストール)"
print(f"[fetch-transcript] 変換完了: {len(texts)}ユニーク行 → {len(result)}文字 (定型句除去: {removed_chars}文字) {budoux_note}")
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
