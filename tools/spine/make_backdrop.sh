#!/bin/sh
# 把 PRTS 宿舍主题的总览图做成手表背景：按屏幕比例裁一条竖条 → 缩放到 416×496 → 稍微压暗 →
# 顶部加渐暗（让时间看得清）。需要 ffmpeg。
# 最好先用 upscale_backdrop.py 把总览图放大 4 倍（x4/ 里那份）；直接用原图（约 477×160）要放大 3 倍多，
# 会自动虚化遮住糊。
#
# 用法：sh make_backdrop.sh 总览图.png 裁剪起点x 输出.jpg
#   裁剪起点x：竖条左边缘在这张图里的位置（像素），换几个值看哪块好看。放大 4 倍的图，坐标也是原图的 4 倍
set -e
in="$1"; x="$2"; out="$3"
if [ -z "$out" ]; then echo "用法：sh make_backdrop.sh 总览图.png 裁剪起点x 输出.jpg"; exit 1; fi
h=$(sips -g pixelHeight "$in" | awk '/pixelHeight/ {print $2}')
w=$(( h * 416 / 496 ))
blur=""
if [ "$h" -lt 496 ]; then blur=",gblur=sigma=3"; fi
ffmpeg -hide_banner -loglevel error -y -i "$in" -f lavfi -i "color=black:s=416x496,format=rgba" -filter_complex \
  "[1]geq=r=0:g=0:b=0:a='255*0.85*pow(max(0\,1-Y/(H*0.5))\,1.3)'[shade];[0]crop=$w:$h:$x:0,scale=416:496:flags=lanczos$blur,eq=brightness=-0.08:saturation=0.88[bg];[bg][shade]overlay,format=yuvj444p" \
  -frames:v 1 -q:v 2 "$out"
echo "已生成 ${out}（裁剪 ${w}×${h}，起点 x=${x}）"
