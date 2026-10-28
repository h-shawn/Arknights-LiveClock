#!/usr/bin/env python3
"""生成表盘复杂功能用的圆形干员头像。

从基建小人的待机首帧裁头（Q 版，眼睛大、块面简单，缩到表盘那么小还认得出来）。

如果某位干员目录下放了 avatar-source.png，再额外用它生成一套 avatar-local-*，
表盘优先用这一套。这是留给「只想在自己表上换张图」的口子：avatar-source.png 和
avatar-local-* 都在 .gitignore 里，不会被提交，入库的始终是小人裁出来的那套。

每个目录下生成：
  avatar-64/88/136/280.png        彩色，给彩色表盘
  avatar-mono-64/88/136/280.png   白色、透明度=明暗，给单色表盘

两点都是真机上踩出来的坑：复杂功能里的图片像素不能比它占的地方大，大了系统
就不画只留灰底；单色表盘只按透明度画图，彩色原图会糊成一个实心圆。

用法：python3 scripts/make_pet_avatars.py [干员目录…]，不给目录就处理全部。
"""
import json
import pathlib
import sys

from PIL import Image, ImageDraw

SIZES = (64, 88, 136, 280)
# 单色图的透明度范围：深色部分也要留得住，不然深发色的干员只剩一张脸
DARK, BRIGHT = 0.38, 1.0


def head_from_sprite(path, relax):
    """没有官方头像时，从待机首帧里裁头：取不透明部分最上面一截，配成正方形。"""
    im = Image.open(path).convert("RGBA")
    alpha = im.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    bbox = alpha.getbbox()
    if not bbox:
        raise SystemExit(f"{path} 整张都是透明的")
    left, top, right, _ = bbox
    side = (relax["anchor"][1] - top) * 0.46     # 基建小人的头约占身高 46%
    band = alpha.crop((left, top, right, int(top + side * 0.6)))
    bb = band.getbbox()
    cx = left + (bb[0] + bb[2]) / 2 if bb else (left + right) / 2
    cy = top + side * 0.52                       # 往下挪一点，别切了下巴
    return im.crop((int(cx - side / 2), int(cy - side / 2), int(cx + side / 2), int(cy + side / 2)))


def circular(im, size):
    im = im.resize((size, size), Image.LANCZOS)
    big = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(big).ellipse([0, 0, size * 4 - 1, size * 4 - 1], fill=255)
    ring = big.resize((size, size), Image.LANCZOS)
    out = im.copy()
    out.putalpha(multiply(im.getchannel("A"), ring))
    return out


def multiply(a, b):
    return Image.frombytes("L", a.size, bytes(x * y // 255 for x, y in zip(a.tobytes(), b.tobytes())))


def monochrome(im):
    """纯白的图，透明度 = 原图明暗 × 原图透明度。"""
    lut = [int(255 * (DARK + (BRIGHT - DARK) * (v / 255))) for v in range(256)]
    shade = im.convert("L").point(lut)
    out = Image.new("RGBA", im.size, (255, 255, 255, 255))
    out.putalpha(multiply(shade, im.getchannel("A")))
    return out


def write(head, d, prefix):
    for size in SIZES:
        circular(head, size).save(d / f"{prefix}-{size}.png")
        circular(monochrome(head), size).save(d / f"{prefix}-mono-{size}.png")


def main(dirs):
    for d in map(pathlib.Path, dirs):
        meta = json.loads((d / "pet.json").read_text())
        head = head_from_sprite(d / "pet-relax-0000.png", meta["animations"]["relax"])
        write(head, d, "avatar")
        note = f"小人裁头 {head.width}×{head.height}"
        source = d / "avatar-source.png"
        if source.exists():
            local = Image.open(source).convert("RGBA")
            write(local, d, "avatar-local")
            note += f"；另有本地专用图 {local.width}×{local.height}（不入库）"
        print(f"{d.name}: {note}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        root = pathlib.Path(__file__).resolve().parent.parent / "LiveFace/Frames/pets"
        args = sorted(str(p) for p in root.iterdir() if (p / "pet.json").exists())
    main(args)
