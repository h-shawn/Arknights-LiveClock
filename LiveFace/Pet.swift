import ImageIO
import SwiftUI

/// 打包进来的所有桌宠：每位一个文件夹 Frames/pets/<文件夹>/，按文件夹名排序，转表冠切换。
/// 旧版直接放在 Frames/pet.json 的单个桌宠也认。只有当前这位的帧放在内存里。
@MainActor
enum PetRoster {
    static let folders: [URL] = {
        guard let frames = Bundle.main.url(forResource: "Frames", withExtension: nil) else { return [] }
        let pets = frames.appendingPathComponent("pets")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: pets.path)) ?? []).sorted()
        let folders = names.map { pets.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("pet.json").path) }
        if folders.isEmpty, FileManager.default.fileExists(atPath: frames.appendingPathComponent("pet.json").path) { return [frames] }
        return folders
    }()

    private static var cache: (index: Int, sprites: PetSprites)?

    static func sprites(at index: Int) -> PetSprites? {
        guard !folders.isEmpty else { return nil }
        let i = ((index % folders.count) + folders.count) % folders.count
        if let cache, cache.index == i { return cache.sprites }
        guard let sprites = PetSprites.load(from: folders[i]) else { return nil }
        cache = (i, sprites)
        return sprites
    }
}

/// 桌宠的背景：Frames/backgrounds/ 里的图片按文件名排序（文件名里「1-」之后的部分就是名字），
/// 最后再加一个深色渐变。长按屏幕切换。
@MainActor
enum Backdrops {
    static let files: [URL] = {
        guard let dir = Bundle.main.url(forResource: "Frames", withExtension: nil)?.appendingPathComponent("backgrounds") else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { ["jpg", "jpeg", "png"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { dir.appendingPathComponent($0) }
    }()

    static var count: Int { files.count + 1 }

    static func name(at index: Int) -> String {
        let i = wrap(index)
        guard i < files.count else { return "深色" }
        let base = files[i].deletingPathExtension().lastPathComponent
        return base.split(separator: "-", maxSplits: 1).last.map(String.init) ?? base
    }

    private static var cache: (index: Int, image: CGImage?)?

    /// nil 表示用深色渐变
    static func image(at index: Int) -> CGImage? {
        let i = wrap(index)
        if let cache, cache.index == i { return cache.image }
        let image = i < files.count ? PetSprites.decodeImage(at: files[i]) : nil
        cache = (i, image)
        return image
    }

    private static func wrap(_ index: Int) -> Int { ((index % count) + count) % count }
}

/// 一位桌宠的素材：pet.json 加上每个动作一组透明底精灵帧（pet-relax-0000.png …）。
/// 必有待机 relax；走路 move、互动 interact、坐 sit、睡 sleep 有就用。
/// 和视频帧一样只在内存里放压缩数据，播到哪帧才解码哪帧。
struct PetSprites {
    struct Clip {
        let frames: [Data]
        let fps: Double
        let size: CGSize       // 精灵图的像素尺寸
        let anchor: CGPoint    // 骨骼原点在图里的像素位置：站着是脚底，坐是椅面，睡是床面
        let lift: CGFloat      // 原点要离地多少像素（坐、睡才有）
        var duration: TimeInterval { Double(frames.count) / fps }
    }

    let name: String
    let clips: [String: Clip]
    let pixelsPerPoint: CGFloat
    let walkSpeed: CGFloat     // 46mm 屏幕上每秒走多少点

    static func decodeImage(at url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    static func load(from directory: URL) -> PetSprites? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("pet.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let animations = json["animations"] as? [String: [String: Any]] else { return nil }
        let point = { (value: Any?) -> CGPoint? in
            guard let v = value as? [Double], v.count == 2 else { return nil }
            return CGPoint(x: v[0], y: v[1])
        }
        var clips: [String: Clip] = [:]
        for (role, info) in animations {
            let count = info["count"] as? Int ?? 0
            let frames = (0..<count).compactMap {
                try? Data(contentsOf: directory.appendingPathComponent(String(format: "pet-%@-%04d.png", role, $0)))
            }
            // 旧版 pet.json 把尺寸和锚点写在顶层，所有动作共用
            guard count > 0, frames.count == count,
                  let size = point(info["size"] ?? json["size"]), let anchor = point(info["anchor"] ?? json["anchor"]) else { continue }
            clips[role] = Clip(frames: frames, fps: info["fps"] as? Double ?? 30, size: CGSize(width: size.x, height: size.y),
                               anchor: anchor, lift: info["lift"] as? Double ?? 0)
        }
        guard clips["relax"] != nil else { return nil }
        return PetSprites(name: json["name"] as? String ?? directory.lastPathComponent, clips: clips,
                          pixelsPerPoint: json["pixelsPerPoint"] as? Double ?? 2,
                          walkSpeed: json["walkSpeed"] as? Double ?? 30)
    }

    /// 循环动作按时间取余，一次性动作停在最后一帧
    func image(_ clip: Clip, elapsed: TimeInterval, loops: Bool) -> CGImage? {
        let frame = Int(max(0, elapsed) * clip.fps)
        let index = loops ? frame % clip.frames.count : min(frame, clip.frames.count - 1)
        guard let source = CGImageSourceCreateWithData(clip.frames[index] as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// 桌宠的行为：白天待机、随机走动，偶尔走到凳子上坐一会儿；夜里躺下睡觉。
/// 被轻点就做一次互动动作，做完回去待机（夜里待机一会儿又接着睡）。
/// 位置用屏幕宽度的比例表示，各种尺寸的手表都一样。
final class PetBrain {
    struct Pose {
        let role: String
        let elapsed: TimeInterval
        let loops: Bool
        let x: CGFloat
        let facing: CGFloat
    }

    private enum Action {
        case relax(until: Date)
        case walk(from: CGFloat, to: CGFloat, duration: TimeInterval, thenSit: Bool)
        case sit(until: Date)
        case sleep
        case interact
    }

    private var action: Action?
    private var start = Date()
    private var x: CGFloat = 0.5
    private var facing: CGFloat = 1
    private var pokedAt: Date?

    /// 轻点屏幕时调用：在当前位置停下，做互动动作
    func poke() { pokedAt = Date() }

    func pose(at date: Date, sprites: PetSprites) -> Pose {
        if action == nil { relax(from: date, seconds: 2...4) }
        if let poked = pokedAt {
            pokedAt = nil
            x = position(at: poked)
            action = .interact
            start = poked
        }
        // 抬腕前可能停了很久，按时间顺序把错过的动作补完
        while advance(to: date, sprites: sprites) {}
        let elapsed = date.timeIntervalSince(start)
        switch action! {
        case .relax: return Pose(role: "relax", elapsed: elapsed, loops: true, x: x, facing: facing)
        case .walk: return Pose(role: "move", elapsed: elapsed, loops: true, x: position(at: date), facing: facing)
        case .sit: return Pose(role: "sit", elapsed: elapsed, loops: true, x: x, facing: facing)
        case .sleep: return Pose(role: "sleep", elapsed: elapsed, loops: true, x: x, facing: facing)
        case .interact: return Pose(role: "interact", elapsed: elapsed, loops: false, x: x, facing: facing)
        }
    }

    /// 当前动作做完就切到下一个；返回 true 表示切换过，要再检查一次
    private func advance(to date: Date, sprites: PetSprites) -> Bool {
        let night = sprites.clips["sleep"] != nil && FaceConfig.isPetSleepTime(date)
        switch action! {
        case .relax(let until):
            guard date >= until else { return false }
            if night { sleep(from: until) } else { chooseNext(from: until, sprites: sprites) }
        case .walk(_, let to, let duration, let thenSit):
            let end = start + duration
            guard date >= end else { return false }
            x = to
            if thenSit {
                action = .sit(until: end + .random(in: 8...16))
                start = end
            } else {
                relax(from: end, seconds: 3...8)
            }
        case .sit(let until):
            guard date >= until || night else { return false }
            relax(from: min(until, date), seconds: 2...4)
        case .sleep:
            guard !night else { return false }
            relax(from: date, seconds: 2...4)   // 天亮了，起床
        case .interact:
            let end = start + (sprites.clips["interact"]?.duration ?? 1)
            guard date >= end else { return false }
            relax(from: end, seconds: 2...5)
        }
        return true
    }

    private func chooseNext(from date: Date, sprites: PetSprites) {
        let roll = Double.random(in: 0..<1)
        if sprites.clips["sit"] != nil, roll < 0.3 {
            walk(from: date, to: FaceConfig.petStoolX, thenSit: true, speed: sprites.walkSpeed)
        } else if roll < 0.85 {
            var target = CGFloat.random(in: FaceConfig.petRange)
            if abs(target - x) < 0.15 { target = x < 0.5 ? FaceConfig.petRange.upperBound : FaceConfig.petRange.lowerBound }
            walk(from: date, to: target, thenSit: false, speed: sprites.walkSpeed)
        } else {
            relax(from: date, seconds: 3...6)
        }
    }

    private func position(at date: Date) -> CGFloat {
        guard case .walk(let from, let to, let duration, _) = action, duration > 0 else { return x }
        let t = min(1, max(0, date.timeIntervalSince(start) / duration))
        return from + (to - from) * CGFloat(t)
    }

    private func relax(from date: Date, seconds: ClosedRange<Double>) {
        action = .relax(until: date + .random(in: seconds))
        start = date
    }

    private func sleep(from date: Date) {
        // 躺下比站着宽很多：固定在凳子左边、头朝左，不被屏幕边切掉，也不压到凳子
        x = min(max(x, FaceConfig.petSleepRange.lowerBound), FaceConfig.petSleepRange.upperBound)
        facing = 1
        action = .sleep
        start = date
    }

    private func walk(from date: Date, to target: CGFloat, thenSit: Bool, speed points: CGFloat) {
        if abs(target - x) > 0.005 { facing = target > x ? 1 : -1 }
        // 走速按 46mm 屏幕的点数给出，换成「屏幕宽度比例/秒」
        let speed = max(points, 1) / 208
        action = .walk(from: x, to: target, duration: Double(abs(target - x) / speed), thenSit: thenSit)
        start = date
    }
}

struct PetView: View {
    let sprites: PetSprites
    let brain: PetBrain
    let background: CGImage?   // nil 时用深色渐变
    let paused: Bool

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 208 / sprites.pixelsPerPoint   // 精灵像素 → 屏幕点
            let ground = geo.size.height * FaceConfig.petGround
            ZStack {
                if let background {
                    Image(decorative: background, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    LinearGradient(colors: [Color(red: 0x1A / 255, green: 0x1F / 255, blue: 0x2B / 255),
                                            Color(red: 0x05 / 255, green: 0x07 / 255, blue: 0x0A / 255)],
                                   startPoint: .top, endPoint: .bottom)
                }
                if let sit = sprites.clips["sit"] {
                    let seat = sit.lift * k
                    Stool(seatHeight: seat, width: seat * 1.25)
                        .position(x: FaceConfig.petStoolX * geo.size.width, y: ground - seat / 2)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
                    let pose = brain.pose(at: context.date, sprites: sprites)
                    if let clip = sprites.clips[pose.role] ?? sprites.clips["relax"],
                       let image = sprites.image(clip, elapsed: pose.elapsed, loops: pose.loops) {
                        let w = clip.size.width * k, h = clip.size.height * k
                        let ax = clip.anchor.x * k, ay = clip.anchor.y * k
                        let rootX = pose.x * geo.size.width, rootY = ground - clip.lift * k
                        ZStack {
                            if pose.role == "sleep" {
                                // 垫子：铺在身体正下方
                                RoundedRectangle(cornerRadius: 3 * k * 2)
                                    .fill(Color(red: 0.16, green: 0.2, blue: 0.3))
                                    .frame(width: w * 0.8, height: 7 * k * 2)
                                    .position(x: rootX + (w / 2 - ax) * pose.facing, y: ground - 2 * k * 2)
                            }
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .frame(width: w, height: h)
                                // 以原点为轴水平翻转，转身时脚不挪位
                                .scaleEffect(x: pose.facing, y: 1, anchor: UnitPoint(x: ax / w, y: ay / h))
                                .position(x: rootX - ax + w / 2, y: rootY - ay + h / 2)
                            if pose.role == "sleep" {
                                Snore(time: context.date.timeIntervalSinceReferenceDate, size: 12 * k * 2)
                                    .position(x: rootX - ax * 0.55 * pose.facing, y: rootY - ay - 6 * k * 2)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 罗德岛风格的小圆凳：深灰椅面加一道黄边。高度正好是坐姿原点的离地高度。
private struct Stool: View {
    let seatHeight: CGFloat
    let width: CGFloat

    var body: some View {
        let seat = width * 0.24, base = width * 0.1
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: seat * 0.45)
                .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.14)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(red: 0.98, green: 0.78, blue: 0.1)).frame(height: max(1, seat * 0.22))
                }
                .clipShape(RoundedRectangle(cornerRadius: seat * 0.45))
                .frame(width: width, height: seat)
            Rectangle()
                .fill(Color(white: 0.2))
                .frame(width: width * 0.12, height: max(0, seatHeight - seat - base))
            Capsule()
                .fill(Color(white: 0.16))
                .frame(width: width * 0.7, height: base)
        }
        .frame(height: seatHeight)
    }
}

/// 睡觉时头顶飘起的三个 z
private struct Snore: View {
    let time: TimeInterval
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let phase = (time / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: size * (0.7 + 0.15 * CGFloat(i)), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(sin(phase * .pi) * 0.9)
                    .offset(x: CGFloat(phase) * size * 0.8, y: -CGFloat(phase) * size * 2)
            }
        }
    }
}
