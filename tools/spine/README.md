# 桌宠素材工具

把明日方舟基建小人（Spine 3.8）渲染成 LiveFace 桌宠用的透明精灵帧，再把宿舍主题总览图做成背景。小人只用 Node.js 和 ffmpeg 渲染，不需要 Spine 编辑器；背景放大另外要 Python 和 PyTorch。

## 准备

```sh
cd ~/Code/LiveFace/tools/spine
npm install
brew install pngquant   # 把精灵帧压成 256 色，体积只有三成
```

## 加一位干员

1. 找编号：下载 [Ark-Models](https://github.com/isHarryh/Ark-Models) 的 `models_data.json`，按中文名查到编号（比如史尔特尔是 `350_surtr`）。皮肤的编号带 `#`，比如近卫阿米娅的「于万千宇宙之中」是 `1001_amiya2_sale#16`。这个文件里只写了皮肤属于哪个系列，皮肤名要到 [ArknightsGameData](https://github.com/Kengxxiao/ArknightsGameData) 的 `skin_table.json` 里查。
2. 下载模型：`models/<编号>/` 下的 `.skel`、`.atlas`、`.png` 三个文件放进同一个文件夹（参考 `assets/`）。下载地址里的 `#` 要写成 `%23`。
3. 看看有哪些动作、坐和睡的原点高度：

   ```sh
   node render_spine.js 模型.skel 模型.atlas /tmp/x --list
   node bbox_probe.js 模型.skel 模型.atlas
   ```

4. 估一下走路速度，作为下一步的 `--walk`（单位/秒，史尔特尔用 125，假日威龙陈用 143，玛恩纳用 135）。有的模型带几根不跟着走的脚部骨骼，速度是 0，会把平均值拉低，只看会动的那几根（史尔特尔就是这样，脚本给的 64 偏低，按会动的那几根取 125）：

   ```sh
   node stride_probe.js 模型.skel 模型.atlas
   ```

5. 出精灵帧：

   ```sh
   node render_pet.js 模型.skel 模型.atlas 输出目录 --height 278 --walk 125
   ```

   动作名不叫 Relax、Move、Interact、Sit、Sleep 的，用 `--relax`、`--move`、`--interact`、`--sit`、`--sleep` 指定。

   待机、坐、睡这三个动作按 15 fps 出（`--slow-fps` 改），走路和互动按 30 fps（`--fps` 改）。每帧出来会自动用 pngquant 压成 256 色，体积只有三成，手表上解码一样快（实测真机 2.4 ms/帧，和原图一样；放大看不出差别）。没装 pngquant 会提示一下，帧照出，只是大三倍。已经出好的帧可以事后补压：`sh scripts/compress_frames.sh`。

6. 把输出目录整个放到 `LiveFace/Frames/pets/<序号-名字>/`，在 `pet.json` 里加一行 `"name": "干员名"`。序号决定转表冠时的顺序。

## 加一个背景

1. 在 PRTS 的宿舍主题页里找到总览图，地址形如 `https://torappu.prts.wiki/assets/furniture_preview/<主题>_<年份>_6.png`。总览图的文件名可以用 PRTS 的 `api.php?action=parse&page=<主题名>&prop=text` 解析出来。PRTS 有频率限制，别抓太快，被限了要等一阵。
2. 总览图只有约 477×160，先用 Real-ESRGAN 的动漫插画模型放大 4 倍，背景才清楚。第一次要装 PyTorch、下载模型（约 18 MB）：

   ```sh
   python3 -m venv .venv && .venv/bin/pip install torch numpy pillow
   curl -L --create-dirs -o models/RealESRGAN_x4plus_anime_6B.pth \
     https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth
   ```

   然后放大，结果在 `backdrop-sources/x4/`：

   ```sh
   .venv/bin/python upscale_backdrop.py backdrop-sources/office_2021_6.png
   ```

3. 生成背景，裁剪起点换几个值看哪块好看（用放大后的图，起点也按 4 倍算）：

   ```sh
   sh make_backdrop.sh backdrop-sources/x4/office_2021_6.png 560 ../../LiveFace/Frames/backgrounds/1-罗德岛人事办公室.jpg
   ```

   文件名前面的序号决定长按时的顺序，`-` 后面是显示的名字。

现有背景用的总览图和裁剪起点（起点是放大 4 倍后的坐标）。顺序按干员分组，每位两到三张：

| 背景 | 总览图 | 起点 x | 配谁 |
|---|---|---|---|
| 1 “求索者之梦”科考小屋 | `volcaRoom_2023_6.png` | 912 | 史尔特尔 |
| 2 异变梦城堡大厅 | `dreamCastle_2025_6.png` | 683 | 史尔特尔 |
| 3 “纯白火山”之旅 | `coastCottage_2023_6.png` | 683 | 假日威龙陈 |
| 4 港都会客室 | `clmsRoom_2026_6.png` | 950 | 假日威龙陈 |
| 5 神农祭庙会 | `TempleFair_2024_6.png` | 950 | 假日威龙陈 |
| 6 喀兰贸易接待室 | `tradeLounge_2025_6.png` | 683 | 玛恩纳 |
| 7 谢拉格游客体验中心 | `winterHouse_2025_6.png` | 397 | 玛恩纳 |
| 8 雪山小邮局 | `postOffice_2023_6.png` | 1250 | 玛恩纳 |

主题的英文编号在 [ArknightsGameData](https://github.com/Kengxxiao/ArknightsGameData) 的 `building_data.json` 里（`customData.themes`，id 去掉 `furni_set_` 前缀就是文件名前缀）。文件名里的年份猜不出来，挨个年份试一下哪个返回 200 就行。PRTS 的网页接口会挡爬虫（403），但图片 CDN `torappu.prts.wiki` 能直接下。

## 文件

| 文件 | 用途 |
|---|---|
| `render_pet.js` | 桌宠精灵帧：每个动作一组透明 PNG，加 `pet.json` |
| `render_spine.js` | 整屏视频帧：单个动作循环，或用 `--seq` 串成一段 |
| `bbox_probe.js` | 每个动作的包围盒 |
| `stride_probe.js` | 估算走路速度 |
| `upscale_backdrop.py` | 宿舍总览图放大 4 倍（Real-ESRGAN 动漫插画模型） |
| `make_backdrop.sh` | 宿舍总览图 → 手表背景 |
| `assets/` | 史尔特尔、假日威龙陈、玛恩纳默认服装的基建小人模型 |
| `backdrop-sources/` | 现有背景用到的宿舍总览图。放大后的 `x4/` 不入库，用 `upscale_backdrop.py` 重新生成 |

## 许可

`spine-core-3.8.js` 是 Esoteric Software 的 Spine Runtimes，要遵守 Spine Runtimes License；模型和背景图的版权归鹰角网络。只供自己使用，不要公开分享。`upscale_backdrop.py` 的网络结构和模型权重来自 [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN)（BSD-3-Clause）。
