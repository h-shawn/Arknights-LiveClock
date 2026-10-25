#!/bin/sh
# 把桌宠精灵帧压成 256 色的 PNG：体积约为原来的三成，手表上解码一样快（数据少了，有时还更快）。
# 256 色对基建小人这种平涂画风够用，放大看不出差别。
# 用法：sh scripts/compress_frames.sh [要压的目录…]，不给目录就压 LiveFace/Frames/pets 下的所有帧。
# 需要 pngquant：brew install pngquant
set -e

command -v pngquant >/dev/null || { echo "缺 pngquant，先 brew install pngquant"; exit 1; }

root=$(cd "$(dirname "$0")/.." && pwd)
[ $# -gt 0 ] && dirs="$*" || dirs=$(find "$root/LiveFace/Frames/pets" -mindepth 1 -maxdepth 1 -type d)

before=0 after=0 n=0
for dir in $dirs; do
  for png in "$dir"/pet-*.png; do
    [ -e "$png" ] || continue
    before=$((before + $(stat -f%z "$png")))
    # --speed 1 挑颜色最仔细；--skip-if-larger 万一压完更大就保持原样
    pngquant --force --strip --speed 1 --skip-if-larger --ext .png -- "$png" || true
    after=$((after + $(stat -f%z "$png")))
    n=$((n + 1))
  done
done

[ "$n" -eq 0 ] && { echo "没找到 pet-*.png"; exit 0; }
echo "$n 帧：$((before / 1024 / 1024)) MB → $((after / 1024 / 1024)) MB（$((after * 100 / before))%）"
