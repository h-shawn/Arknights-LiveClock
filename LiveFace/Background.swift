import ImageIO
import SwiftUI

/// 打包了桌宠素材就放桌宠，有帧序列就播帧序列，都没有就播内置的水波动画。
struct Background: View {
    let paused: Bool
    let pet: PetBrain
    let petIndex: Int
    let backgroundIndex: Int

    var body: some View {
        if let sprites = PetRoster.sprites(at: petIndex) {
            PetView(sprites: sprites, brain: pet, background: Backdrops.image(at: backgroundIndex), paused: paused)
        } else if let frames = FrameSequence.bundled {
            FramePlayer(frames: frames, paused: paused)
        } else {
            WaveBackground(paused: paused)
        }
    }
}

/// App 里的帧序列（Frames/frame-0000.jpg …），由 scripts/make_frames.swift 生成。
/// 只在内存里保存 JPEG 原始数据（每帧几十 KB），播到哪帧才解码哪帧，内存占用很小。
struct FrameSequence {
    let frames: [Data]
    let fps: Double

    static let bundled: FrameSequence? = Bundle.main.url(forResource: "Frames", withExtension: nil).flatMap { load(from: $0) }

    static func load(from directory: URL) -> FrameSequence? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let frames = names.filter { $0.hasPrefix("frame-") && $0.hasSuffix(".jpg") }.sorted()
            .compactMap { try? Data(contentsOf: directory.appendingPathComponent($0)) }
        guard !frames.isEmpty else { return nil }
        let manifest = (try? Data(contentsOf: directory.appendingPathComponent("frames.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let fps = manifest?["fps"] as? Double ?? 12
        return FrameSequence(frames: frames, fps: fps > 0 ? fps : 12)
    }

    /// 按绝对时间取帧，掉帧也不会让循环变慢。用 Double 取余：老款手表的 Int 是 32 位，乘出来会溢出。
    func image(at date: Date) -> CGImage? {
        let position = (date.timeIntervalSinceReferenceDate * fps).truncatingRemainder(dividingBy: Double(frames.count))
        guard let source = CGImageSourceCreateWithData(frames[Int(position)] as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

struct FramePlayer: View {
    let frames: FrameSequence
    let paused: Bool

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1 / frames.fps, paused: paused)) { context in
                if let image = frames.image(at: context.date) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
        }
    }
}

/// 没放视频时的默认背景：深蓝底上几层缓慢起伏的水波。
struct WaveBackground: View {
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: paused)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let sky = Gradient(colors: [Color(red: 0.01, green: 0.03, blue: 0.14), Color(red: 0.02, green: 0.2, blue: 0.45)])
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                for layer in 0..<4 {
                    let i = Double(layer)
                    let baseline: Double = size.height * (0.42 + 0.16 * i)
                    let amplitude: Double = size.height * (0.03 + 0.012 * i)
                    let wavelength: Double = size.width * (1.4 - 0.2 * i)
                    let phase: Double = t * (0.5 + 0.22 * i) + i * 1.7
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    for x in stride(from: 0.0, through: Double(size.width), by: 3) {
                        path.addLine(to: CGPoint(x: x, y: baseline + amplitude * sin(2 * .pi * x / wavelength + phase)))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(Color(red: 0.2 + 0.1 * i, green: 0.65 + 0.07 * i, blue: 0.95).opacity(0.18 + 0.05 * i)))
                }
            }
        }
    }
}
