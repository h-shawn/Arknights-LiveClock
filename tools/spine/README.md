# 桌宠素材工具

把明日方舟基建小人（Spine 3.8）渲染成 LiveFace 桌宠用的透明精灵帧，再把宿舍主题总览图做成背景。只用 Node.js 和 ffmpeg，不需要 Spine 编辑器。

## 准备

```sh
cd ~/Code/LiveFace/tools/spine
npm install
```

## 加一位干员

1. 找编号：下载 [Ark-Models](https://github.com/isHarryh/Ark-Models) 的 `models_data.json`，按中文名查到编号（比如克莱门莎是 `4231_clemnt`）。
2. 下载模型：`models/<编号>/` 下的 `.skel`、`.atlas`、`.png` 三个文件放进同一个文件夹（参考 `assets/`）。
3. 看看有哪些动作、坐和睡的原点高度：

   ```sh
   node render_spine.js 模型.skel 模型.atlas /tmp/x --list
   node bbox_probe.js 模型.skel 模型.atlas
   ```

4. 估一下走路速度，作为下一步的 `--walk`（单位/秒，阿米娅用 97，克莱门莎用 125）：

   ```sh
   node stride_probe.js 模型.skel 模型.atlas
   ```

5. 出精灵帧：

   ```sh
   node render_pet.js 模型.skel 模型.atlas 输出目录 --height 278 --walk 125
   ```

   动作名不叫 Relax、Move、Interact、Sit、Sleep 的，用 `--relax`、`--move`、`--interact`、`--sit`、`--sleep` 指定。

6. 把输出目录整个放到 `LiveFace/Frames/pets/<序号-名字>/`，在 `pet.json` 里加一行 `"name": "干员名"`。序号决定转表冠时的顺序。

## 加一个背景

1. 在 PRTS 的宿舍主题页里找到总览图，地址形如 `https://torappu.prts.wiki/assets/furniture_preview/<主题>_<年份>_6.png`。总览图的文件名可以用 PRTS 的 `api.php?action=parse&page=<主题名>&prop=text` 解析出来。PRTS 有频率限制，别抓太快，被限了要等一阵。
2. 生成背景，裁剪起点换几个值看哪块好看：

   ```sh
   sh make_backdrop.sh backdrop-sources/office_2021_6.png 140 ../../LiveFace/Frames/backgrounds/1-罗德岛人事办公室.jpg
   ```

   文件名前面的序号决定长按时的顺序，`-` 后面是显示的名字。

## 文件

| 文件 | 用途 |
|---|---|
| `render_pet.js` | 桌宠精灵帧：每个动作一组透明 PNG，加 `pet.json` |
| `render_spine.js` | 整屏视频帧：单个动作循环，或用 `--seq` 串成一段 |
| `bbox_probe.js` | 每个动作的包围盒 |
| `stride_probe.js` | 估算走路速度 |
| `make_backdrop.sh` | 宿舍总览图 → 手表背景 |
| `assets/` | 阿米娅、克莱门莎默认服装的基建小人模型 |
| `backdrop-sources/` | 罗德岛人事办公室、飞空艇风格宿舍的总览图 |

## 许可

`spine-core-3.8.js` 是 Esoteric Software 的 Spine Runtimes，要遵守 Spine Runtimes License；模型和背景图的版权归鹰角网络。只供自己使用，不要公开分享。
