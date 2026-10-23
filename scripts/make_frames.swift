#!/usr/bin/env swift
// 把一段视频转成 LiveFace 用的帧序列：LiveFace/Frames/frame-0000.jpg … 和 frames.json。
// 只用 macOS 自带的 AVFoundation，不需要 ffmpeg。
//
// 用法：swift scripts/make_frames.swift 视频文件 [选项]
//
//   --start 秒       从第几秒开始截，默认 0
//   --duration 秒    截多长，默认 6。帧数 = 时长 × 帧率，帧越多 App 越大
//   --fps 帧率       默认 12
//   --x 0~1          视频比手表屏幕宽时（横屏视频），取景框的水平位置：0 最左、0.5 居中（默认）、1 最右
//   --y 0~1          视频比手表屏幕高时（竖屏视频），取景框的垂直位置：0 最上、0.5 居中（默认）、1 最下
//   --crossfade 秒   首尾交叉淡化，让本身不循环的片段也能无缝衔接，默认 0（不处理）
//   --size 宽x高     输出像素，默认 422x514，所有尺寸的 Apple Watch 都够用
//   --quality 0~1    JPEG 质量，默认 0.8
//   --out 目录       输出目录，默认 LiveFace/Frames（会先清掉里面的旧帧）
import AVFoundation
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let usage = "用法：swift scripts/make_frames.swift 视频文件 [--start 秒] [--duration 秒] [--fps 12] [--x 0.5] [--y 0.5] [--crossfade 秒] [--size 422x514] [--quality 0.8] [--out 目录]"
var arguments = Array(CommandLine.arguments.dropFirst())
guard let inputPath = arguments.first, !inputPath.hasPrefix("-") else { fail(usage) }
arguments.removeFirst()
let known: Set = ["start", "duration", "fps", "x", "y", "crossfade", "size", "quality", "out"]
var options: [String: String] = [:]
while let key = arguments.first {
    arguments.removeFirst()
    let name = String(key.drop(while: { $0 == "-" }))
    guard key.hasPrefix("--"), known.contains(name), let value = arguments.first else { fail("看不懂的参数：\(key)\n\(usage)") }
    arguments.removeFirst()
    options[name] = value
}

func number(_ name: String, _ fallback: Double, in range: ClosedRange<Double>) -> Double {
    guard let raw = options[name] else { return fallback }
    guard let value = Double(raw), range.contains(value) else {
        fail("--\(name) 应该是 \(range.lowerBound) 到 \(range.upperBound) 之间的数字，收到的是 \(raw)")
    }
    return value
}

let fps = number("fps", 12, in: 1...60)
let start = number("start", 0, in: 0...86400)
let crossfade = number("crossfade", 0, in: 0...10)
let focusX = number("x", 0.5, in: 0...1)
let focusY = number("y", 0.5, in: 0...1)
let quality = number("quality", 0.8, in: 0.1...1)
let size = (options["size"] ?? "422x514").split(separator: "x").compactMap { Int($0) }
guard size.count == 2, size.allSatisfy({ (16...2000).contains($0) }) else { fail("--size 的格式是 宽x高，比如 422x514") }
let width = size[0], height = size[1]
// 默认输出到脚本所在工程的 LiveFace/Frames，从哪个目录运行都一样
let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outDir = options["out"].map { URL(fileURLWithPath: $0) } ?? projectRoot.appendingPathComponent("LiveFace/Frames")

let inputURL = URL(fileURLWithPath: inputPath)
guard FileManager.default.fileExists(atPath: inputURL.path) else { fail("找不到视频：\(inputPath)") }
let asset = AVURLAsset(url: inputURL)
let total = try await asset.load(.duration).seconds
guard total.isFinite, total > 0 else { fail("读不出视频时长：\(inputPath)") }
guard start + crossfade < total else {
    fail(String(format: "--start 加 --crossfade 超出了视频长度（视频只有 %.1f 秒）", total))
}
let duration = min(number("duration", 6, in: 0.1...60), total - start - crossfade)
let count = max(1, Int((duration * fps).rounded(.down)))
let fadeCount = min(count, Int((crossfade * fps).rounded()))

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true   // 手机竖着拍的视频也按正确方向读
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.maximumSize = CGSize(width: 1920, height: 1920)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let canvas = CGRect(x: 0, y: 0, width: width, height: height)

func makeContext() -> CGContext {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("无法创建画布") }
    context.interpolationQuality = .high
    return context
}

/// 按手表屏幕的宽高比裁出取景框（铺满、不留黑边），再缩放到输出尺寸
func fit(_ image: CGImage) -> CGImage {
    let sourceWidth = Double(image.width), sourceHeight = Double(image.height)
    let aspect = Double(width) / Double(height)
    var crop = CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
    if sourceWidth / sourceHeight > aspect {
        crop.size.width = sourceHeight * aspect
        crop.origin.x = (sourceWidth - crop.width) * focusX
    } else {
        crop.size.height = sourceWidth / aspect
        crop.origin.y = (sourceHeight - crop.height) * focusY
    }
    guard let cropped = image.cropping(to: crop.integral) else { fail("裁切画面失败") }
    let context = makeContext()
    context.draw(cropped, in: canvas)
    return context.makeImage()!
}

/// 交叉淡化：在 base 上按 alpha 叠一层 top
func blend(_ top: CGImage, over base: CGImage, alpha: Double) -> CGImage {
    let context = makeContext()
    context.draw(base, in: canvas)
    context.setAlpha(alpha)
    context.draw(top, in: canvas)
    return context.makeImage()!
}

var bytes = 0
func write(_ image: CGImage, index: Int) {
    let url = outDir.appendingPathComponent(String(format: "frame-%04d.jpg", index))
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { fail("无法写入 \(url.path)") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fail("无法写入 \(url.path)") }
    bytes += (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
}

let fileManager = FileManager.default
try fileManager.createDirectory(at: outDir, withIntermediateDirectories: true)
for name in try fileManager.contentsOfDirectory(atPath: outDir.path) where name.hasPrefix("frame-") && name.hasSuffix(".jpg") {
    try fileManager.removeItem(at: outDir.appendingPathComponent(name))
}
// 桌宠素材优先级更高，换成视频时一并清掉，否则 App 还是显示桌宠
let petFiles = try fileManager.contentsOfDirectory(atPath: outDir.path)
    .filter { $0 == "pet.json" || $0 == "pets" || $0.hasPrefix("pet-") }
for name in petFiles { try fileManager.removeItem(at: outDir.appendingPathComponent(name)) }
if !petFiles.isEmpty { print("已删除原来的桌宠素材：\(petFiles.joined(separator: "、"))") }

// 交叉淡化：多读 fadeCount 帧，把片段结尾之后的画面渐变进开头，最后一帧接回第一帧时就是连续的
var head: [CGImage] = []
let readCount = count + fadeCount
for i in 0..<readCount {
    let time = CMTime(seconds: start + Double(i) / fps, preferredTimescale: 60000)
    let frame: CGImage
    do {
        frame = fit(try await generator.image(at: time).image)
    } catch {
        fail(String(format: "读取 %.2f 秒处的画面失败：%@", time.seconds, error.localizedDescription))
    }
    if i < fadeCount {
        head.append(frame)
    } else if i < count {
        write(frame, index: i)
    } else {
        let j = i - count
        write(blend(head[j], over: frame, alpha: Double(j) / Double(fadeCount)), index: j)
    }
    if (i + 1) % 20 == 0 || i + 1 == readCount { print("已处理 \(i + 1)/\(readCount) 帧") }
}

let manifest: [String: Any] = [
    "fps": fps, "count": count, "width": width, "height": height,
    "source": inputURL.lastPathComponent, "start": start, "crossfade": Double(fadeCount) / fps,
]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("frames.json"))
print(String(format: "完成：%d 帧，%.2f 秒一圈，共 %d KB → %@", count, Double(count) / fps, bytes / 1024, outDir.path))
if count > 150 { print("提示：帧数较多，App 会变大，播放也更费电。可以缩短 --duration 或降低 --fps。") }
