# LiveFace 动态表盘

把视频循环播放成“表盘”的 Apple Watch App：全屏动画，上面叠一层自己画的时间。也可以放会走动、能戳的桌宠：轻点戳她，长按换背景，转表冠换角色。

watchOS 不开放第三方表盘，所以它其实是个 App。配合手表的「返回时钟」设置，抬腕时看到的一直是它。

## 功能

- 三种背景，按 `LiveFace/Frames/` 里放了什么自动选择：
  - 桌宠：`pets/` 里每位角色一个文件夹（`pet.json` 加精灵帧），背景图放在 `backgrounds/`（文件名排序，`1-` 后面是名字，最后还有一个纯深色）。角色会自己待机、走动、偶尔坐到凳子上，夜里（默认 23 点到 7 点）躺下睡觉；**轻点屏幕**她会做互动动作，**长按**换背景，**转表冠**换角色，选择都会被记住
  - 视频：有 `frame-*.jpg` 时，全屏循环播放
  - 都没有时，播内置的水波动画
- 五种时间样式，在 `FaceConfig.clockStyle` 里选，默认「顶部」：
  - 经典：左下角日期 + 大号时间
  - 菜单：仿 P3R 主菜单，右侧四行斜体
  - 居中：细体大字
  - 顶部：时间和日期在上方，下半屏留给角色（配桌宠用）
  - 纯动画：不画时间，只留右上角系统自带的小时间（其他样式会把系统时间藏掉，避免出现两个时间）
- 放下手腕（常亮显示）时动画暂停、背景变暗，时间照常每分钟更新
- 按屏幕宽高自动缩放，各种尺寸的 Apple Watch 都能用
- 内存里只放 JPEG 原始数据，播到哪一帧才解码哪一帧，内存占用小

## 需要准备

- Mac + Xcode。Xcode 版本要支持你手表上的 watchOS：watchOS 26 用 Xcode 26，watchOS 27 用 Xcode 27。第一次连手表时，Xcode 会提示下载 watchOS 平台组件（几个 GB）。
- 和手表配对的 iPhone，一根数据线
- Apple ID。免费账号就行，但签名 7 天后过期，过期后重新运行一次即可

## 1. 换成你的视频（可选）

```sh
cd ~/Code/LiveFace
swift scripts/make_frames.swift ~/Downloads/你的视频.mp4 --start 3 --duration 6
```

| 参数 | 默认 | 说明 |
|---|---|---|
| `--start` | 0 | 从第几秒开始截 |
| `--duration` | 6 | 截多长（秒）。帧数 = 时长 × 帧率 |
| `--fps` | 12 | 帧率 |
| `--x` | 0.5 | 横屏视频取景框的水平位置：0 最左，1 最右 |
| `--y` | 0.5 | 竖屏视频取景框的垂直位置：0 最上，1 最下 |
| `--crossfade` | 0 | 首尾交叉淡化的秒数。片段首尾接不上时设 0.5–1，循环就不会跳 |
| `--size` | 422x514 | 输出像素。默认值对所有尺寸的手表都够用 |
| `--quality` | 0.8 | JPEG 质量 |
| `--out` | LiveFace/Frames | 输出目录 |

帧会写进 `LiveFace/Frames/`，旧帧和桌宠素材会先清掉。重新运行到手表就生效。想换回水波动画，删掉 `LiveFace/Frames/` 里除 README 以外的文件即可。

5–8 秒、首尾画面差不多的片段效果最好。6 秒、12 fps 是 72 帧，两三 MB。

## 2. 装到手表

1. `open LiveFace.xcodeproj`
2. 在左侧点工程 → TARGETS 选 **LiveFace** → **Signing & Capabilities**：
   - **Team** 选你的 Apple ID（Personal Team）。
   - **Bundle Identifier** 如果提示已被占用，改成独一无二的，比如 `com.你的名字.liveface`。
3. iPhone 和手表都打开开发者模式：设置 → 隐私与安全性 → 开发者模式。手表上的这个开关，要等 Xcode 发现过手表一次之后才会出现。
4. 在 Xcode 顶部的运行目标里选你的手表，按 ⌘R。第一次要拷贝调试符号，可能要十几分钟，期间让手表保持亮屏、解锁。
5. 如果提示“不受信任的开发者”：在 iPhone 上打开设置 → 通用 → VPN 与设备管理，信任你的证书，再运行一次。
6. 装好后在 Xcode 里点停止，然后在手表上直接打开「动态表盘」。

连不上手表？先关掉 Mac 上的代理或 VPN，让 Mac、iPhone、手表连同一个 Wi-Fi，并让手表的蓝牙保持开启。

没有手表也可以先用模拟器看效果：在 Xcode → Settings → Platforms 里下载 watchOS 模拟器，运行目标选一个手表模拟器。

## 3. 让它一直留在屏幕上

在手表上打开：设置 → 通用 → 返回时钟 → 动态表盘 → 自定 → 1 小时后。也可以在 iPhone「Watch」App → 通用 → 返回时钟 里设置。

这样放下手腕后一小时内再抬腕，看到的还是它。超过一小时没看会回到系统表盘，重新打开一次即可。

## 自定义

| 想改什么 | 改哪里 |
|---|---|
| 时间样式、12/24 小时制、常亮时背景亮度 | `LiveFace/FaceConfig.swift` |
| 桌宠站的高度、走动范围、凳子位置、几点睡觉 | `LiveFace/FaceConfig.swift` |
| 桌宠多久走一次、坐多久、待机多久 | `LiveFace/Pet.swift` 里的 `PetBrain` |
| 时间的字号、位置、颜色；加新样式 | `LiveFace/ClockStyles.swift` |
| 没放视频时的默认动画 | `LiveFace/Background.swift` 里的 `WaveBackground` |

菜单样式是给右侧偏暗的画面设计的。换了视频后如果文字压到画面主体，就调整 `MenuClock` 里的 `top`、`right` 和字号。

## 已知限制

- 它是 App 不是表盘：没有复杂功能和智能叠放，太久不看会退回系统表盘。
- 右上角的系统时间是用 SwiftUI 没写进文档的 `_statusBarHidden` 藏掉的（公开文档里的 `persistentSystemOverlays`、`toolbar(.hidden)` 等写法在 watchOS 上都无效）。在 watchOS 27 模拟器上验证有效，但以后的系统更新可能让它失效；这种 App 也不适合上架。
- 常亮显示时动画停住，这是 watchOS 对所有 App 的限制。
- 比静态表盘耗电：抬腕亮屏期间一直在解码、绘制画面。
- 免费签名 7 天后过期。

## 致谢

菜单样式的版式参数来自 [P3R-LiveClock](https://github.com/Hastur-02/P3R-LiveClock)（MIT）。
