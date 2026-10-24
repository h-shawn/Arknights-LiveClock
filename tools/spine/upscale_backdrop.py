"""把宿舍总览图（约 477×160）用 Real-ESRGAN 的动漫插画模型放大 4 倍，裁成手表背景时就清楚了，不用再虚化遮糊。

准备（一次）：
  python3 -m venv .venv && .venv/bin/pip install torch numpy pillow
  curl -L --create-dirs -o models/RealESRGAN_x4plus_anime_6B.pth \\
    https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth

用法：.venv/bin/python upscale_backdrop.py 总览图.png [更多总览图.png ...]
  结果写到总览图旁边的 x4/ 文件夹，文件名不变。
"""
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from torch import nn
from torch.nn import functional as F

WEIGHTS = Path(__file__).parent / "models" / "RealESRGAN_x4plus_anime_6B.pth"


class DenseBlock(nn.Module):
    def __init__(self, feat=64, grow=32):
        super().__init__()
        for i in range(1, 6):
            setattr(self, f"conv{i}", nn.Conv2d(feat + (i - 1) * grow, grow if i < 5 else feat, 3, 1, 1))

    def forward(self, x):
        features = [x]
        for i in range(1, 5):
            features.append(F.leaky_relu(getattr(self, f"conv{i}")(torch.cat(features, 1)), 0.2))
        return self.conv5(torch.cat(features, 1)) * 0.2 + x


class RRDB(nn.Module):
    def __init__(self):
        super().__init__()
        self.rdb1, self.rdb2, self.rdb3 = DenseBlock(), DenseBlock(), DenseBlock()

    def forward(self, x):
        return self.rdb3(self.rdb2(self.rdb1(x))) * 0.2 + x


class RRDBNet(nn.Module):
    """Real-ESRGAN 用的 RRDBNet（4 倍、6 块），参数名和官方权重一致"""

    def __init__(self, blocks=6, feat=64):
        super().__init__()
        self.conv_first = nn.Conv2d(3, feat, 3, 1, 1)
        self.body = nn.Sequential(*[RRDB() for _ in range(blocks)])
        self.conv_body = nn.Conv2d(feat, feat, 3, 1, 1)
        self.conv_up1 = nn.Conv2d(feat, feat, 3, 1, 1)
        self.conv_up2 = nn.Conv2d(feat, feat, 3, 1, 1)
        self.conv_hr = nn.Conv2d(feat, feat, 3, 1, 1)
        self.conv_last = nn.Conv2d(feat, 3, 3, 1, 1)

    def forward(self, x):
        feat = self.conv_first(x)
        feat = feat + self.conv_body(self.body(feat))
        for up in (self.conv_up1, self.conv_up2):
            feat = F.leaky_relu(up(F.interpolate(feat, scale_factor=2, mode="nearest")), 0.2)
        return self.conv_last(F.leaky_relu(self.conv_hr(feat), 0.2))


def main():
    paths = [Path(p) for p in sys.argv[1:]]
    if not paths:
        sys.exit(__doc__)
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    net = RRDBNet()
    state = torch.load(WEIGHTS, map_location="cpu", weights_only=True)
    net.load_state_dict(state.get("params_ema", state))
    net.eval().to(device)
    for path in paths:
        image = Image.open(path).convert("RGB")
        x = torch.from_numpy(np.asarray(image, dtype=np.float32) / 255).permute(2, 0, 1)[None].to(device)
        pad = 10  # 四边先镜像补一圈再放大，放大后切掉，边缘不发糊
        with torch.no_grad():
            y = net(F.pad(x, (pad, pad, pad, pad), mode="reflect"))[..., pad * 4:-pad * 4, pad * 4:-pad * 4]
        out = (y.clamp(0, 1)[0].permute(1, 2, 0).cpu().numpy() * 255).round().astype(np.uint8)
        dest = path.parent / "x4" / path.name
        dest.parent.mkdir(exist_ok=True)
        Image.fromarray(out).save(dest)
        print(f"{dest}（{image.width}×{image.height} → {out.shape[1]}×{out.shape[0]}）")


if __name__ == "__main__":
    main()
