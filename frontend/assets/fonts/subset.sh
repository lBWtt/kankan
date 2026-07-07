#!/usr/bin/env bash
# 生成 Noto Serif SC 中文子集。
#
# 用法:
#   ./subset.sh /path/to/NotoSerifSC-Regular.otf
#   ./subset.sh /path/to/NotoSerifSC-Regular.otf common-3500.txt   # 精简到 3500 字
#
# 前置:
#   pip install fonttools brotli
#
# 产出:NotoSerifSC-Subset.ttf(放入本目录即可被 pubspec 引用)
set -euo pipefail

SRC="${1:-}"
if [[ -z "$SRC" || ! -f "$SRC" ]]; then
  echo "用法: $0 <NotoSerifSC-Regular.otf 路径> [text-file]"
  echo "  下载: https://github.com/notofonts/noto-cjk/releases"
  exit 1
fi

TEXT_FILE="${2:-}"
OUT="NotoSerifSC-Subset.ttf"

if [[ -n "$TEXT_FILE" ]]; then
  # 精简模式:只用 text-file 里的字(~3500 字 → ~1.5MB)
  echo "→ 精简模式:text-file=$TEXT_FILE"
  pyftsubset "$SRC" \
    --text-file="$TEXT_FILE" \
    --output-file="$OUT" \
    --no-hinting \
    --desubroutinize \
    --drop-tables+=DSIG
else
  # 宽模式:CJK 全量 + 标点 + ASCII(~20k 字 → ~3MB)
  echo "→ 宽模式:CJK 全量 + 标点"
  pyftsubset "$SRC" \
    --unicodes="U+4E00-9FFF,U+3000-303F,U+FF00-FFEF,U+2000-206F,U+0020-007E" \
    --output-file="$OUT" \
    --no-hinting \
    --desubroutinize \
    --drop-tables+=DSIG
fi

SIZE=$(du -h "$OUT" | cut -f1)
echo ""
echo "✅ 生成完毕:$OUT ($SIZE)"
echo "   放入 assets/fonts/ 后,编辑 pubspec.yaml 取消 fonts: 段注释即可"
