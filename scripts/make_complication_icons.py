"""把 App 图标做成表盘复杂功能用的小图，写进 LiveFaceWidget/Assets.xcassets/：
- arknights-<尺寸>：彩色原图，彩色表盘用
- arknights-mono-<尺寸>：白色加透明度，单色表盘用。单色表盘只按透明度画图，不透明的彩色图会变成实心圆，
  所以把明暗转成透明度（亮的地方不透明），画出来是一张黑白图
尺寸是像素（按 @2x）。复杂功能里的图片不能比它占的地方大，大了系统就不画，所以准备几种让组件按大小挑。

用法：python3 scripts/make_complication_icons.py   （需要 Pillow，tools/spine/.venv 里有）
"""
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICON = ROOT / "LiveFace" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
ASSETS = ROOT / "LiveFaceWidget" / "Assets.xcassets"
SIZES = (64, 88, 136, 280)
DARK, BRIGHT = 0.12, 0.92   # 亮度低于 DARK 全透明，高于 BRIGHT 全不透明，中间线性


def save(image, name):
    imageset = ASSETS / f"{name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    image.save(imageset / f"{name}.png")
    contents = {"images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "2x"}],
                "info": {"author": "xcode", "version": 1}}
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    print(imageset.relative_to(ROOT))


def main():
    icon = Image.open(ICON).convert("RGB")
    for size in SIZES:
        color = icon.resize((size, size), Image.LANCZOS)
        save(color, f"arknights-{size}")
        alpha = color.convert("L").point(lambda v: round(min(max((v / 255 - DARK) / (BRIGHT - DARK), 0), 1) * 255))
        mono = Image.new("RGBA", color.size, (255, 255, 255, 255))
        mono.putalpha(alpha)
        save(mono, f"arknights-mono-{size}")


if __name__ == "__main__":
    main()
