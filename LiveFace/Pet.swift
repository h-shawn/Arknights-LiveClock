import ImageIO
import SwiftUI
import WatchKit

/// 打包进来的所有桌宠：每位一个文件夹 Frames/pets/<文件夹>/，按文件夹名排序，转表冠切换。
/// 旧版直接放在 Frames/pet.json 的单个桌宠也认。只有当前这位的帧放在内存里。
@MainActor
enum PetRoster {
    static let folders: [URL] = {
        guard let frames = Bundle.main.url(forResource: "Frames", withExtension: nil) else { return [] }
        let pets = frames.appendingPathComponent("pets")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: pets.path)) ?? []).sorted(by: numberedOrder)
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
/// 长按屏幕空白处切换。一张图都没有时用深色渐变。
@MainActor
enum Backdrops {
    static let files: [URL] = {
        guard let dir = Bundle.main.url(forResource: "Frames", withExtension: nil)?.appendingPathComponent("backgrounds") else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { ["jpg", "jpeg", "png"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted(by: numberedOrder)
            .map { dir.appendingPathComponent($0) }
    }()

    static var count: Int { max(files.count, 1) }

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

/// 文件名里的数字按大小排（和访达一样），「10-」排在「9-」后面
private func numberedOrder(_ a: String, _ b: String) -> Bool {
    a.localizedStandardCompare(b) == .orderedAscending
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
        // 原点到画面上不透明部分最左、最右的距离（像素）。图的四周多是透明的，
        // 按这个算她站在哪才不会被屏幕边切掉
        let bounds: (left: CGFloat, right: CGFloat)
        var duration: TimeInterval { Double(frames.count) / fps }
    }

    let name: String
    let clips: [String: Clip]
    let pixelsPerPoint: CGFloat
    let walkSpeed: CGFloat     // 46mm 屏幕上每秒走多少点
    let cache = FrameCache()

    /// 刚解码过的几帧。待机、坐、睡只有 15 fps，画面按 30 fps 刷，同一张图没必要解两次。
    /// 一帧解开约 270 KB，留三张就够了
    final class FrameCache {
        private var entries: [(key: String, image: CGImage)] = []

        func image(_ key: String, decode: () -> CGImage?) -> CGImage? {
            if let hit = entries.first(where: { $0.key == key }) { return hit.image }
            guard let image = decode() else { return nil }
            entries.insert((key, image), at: 0)
            if entries.count > 3 { entries.removeLast() }
            return image
        }
    }

    /// 站着时的身高（像素，脚底到头顶）：取待机动作的原点离图顶多远
    var height: CGFloat { clips["relax"]!.anchor.y }
    /// 重心离脚底多高（像素）：拎起来晃、扔出去转都绕这里
    var center: CGFloat { height * 0.45 }

    static func decodeImage(at url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
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
            // 内存映射：帧数据留在闪存里，系统按需换页，不用一上来就读十几 MB 进内存
            let frames = (0..<count).compactMap {
                try? Data(contentsOf: directory.appendingPathComponent(String(format: "pet-%@-%04d.png", role, $0)),
                          options: .mappedIfSafe)
            }
            // 旧版 pet.json 把尺寸和锚点写在顶层，所有动作共用
            guard count > 0, frames.count == count,
                  let size = point(info["size"] ?? json["size"]), let anchor = point(info["anchor"] ?? json["anchor"]) else { continue }
            // 旧素材没写 bounds，就按整张图算（和以前一样）
            let bounds = (info["bounds"] as? [Double]).flatMap { $0.count == 2 ? $0 : nil }
                ?? [anchor.x, size.x - anchor.x]
            clips[role] = Clip(frames: frames, fps: info["fps"] as? Double ?? 30, size: CGSize(width: size.x, height: size.y),
                               anchor: anchor, lift: info["lift"] as? Double ?? 0,
                               bounds: (CGFloat(bounds[0]), CGFloat(bounds[1])))
        }
        guard clips["relax"] != nil else { return nil }
        return PetSprites(name: json["name"] as? String ?? directory.lastPathComponent, clips: clips,
                          pixelsPerPoint: json["pixelsPerPoint"] as? Double ?? 2,
                          walkSpeed: json["walkSpeed"] as? Double ?? 30)
    }

    /// 某个动作的身体，原点左右各占屏幕宽度的多少
    func extents(_ roles: String...) -> (left: CGFloat, right: CGFloat) {
        let unit = 208 * pixelsPerPoint
        return roles.compactMap { clips[$0] }.reduce((0, 0)) {
            (max($0.left, $1.bounds.left / unit), max($0.right, $1.bounds.right / unit))
        }
    }

    /// 把想要的落点范围挪进「身体完整留在屏幕里」的范围。
    /// 身体比屏幕还宽（克莱门莎躺下就是）就居中，两边均摊着出去一点
    func fit(_ preferred: ClosedRange<CGFloat>, within extents: (left: CGFloat, right: CGFloat)) -> ClosedRange<CGFloat> {
        let margin: CGFloat = 0.02   // 身体离屏幕边至少留这么点（屏幕宽度的比例）
        let lo = extents.left + margin, hi = 1 - extents.right - margin
        guard lo <= hi else {
            let center = extents.left + (1 - extents.left - extents.right) / 2
            return center...center
        }
        let a = min(max(preferred.lowerBound, lo), hi), b = min(max(preferred.upperBound, lo), hi)
        return min(a, b)...max(a, b)
    }

    /// 走动、站着的落点范围：站、走、互动三个动作都要放得下
    var walkRange: ClosedRange<CGFloat> { fit(FaceConfig.petRange, within: extents("relax", "move", "interact")) }
    /// 躺下的落点范围
    var sleepRange: ClosedRange<CGFloat> { fit(FaceConfig.petSleepRange, within: extents("sleep")) }

    /// 循环动作按时间取余，一次性动作停在最后一帧
    func image(_ role: String, elapsed: TimeInterval, loops: Bool) -> CGImage? {
        let name = clips[role] != nil ? role : "relax"
        guard let clip = clips[name] else { return nil }
        let frame = Int(max(0, elapsed) * clip.fps)
        let index = loops ? frame % clip.frames.count : min(frame, clip.frames.count - 1)
        return cache.image("\(name)-\(index)") {
            CGImageSourceCreateWithData(clip.frames[index] as CFData, nil).flatMap {
                CGImageSourceCreateImageAtIndex($0, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            }
        }
    }
}

/// 桌宠的行为：白天待机、随机走动，偶尔走到凳子上坐一会儿；夜里走到垫子那儿躺下睡觉。
/// 也能跟她玩：轻点做一次互动动作；按住能拎起来，跟着手指晃，松手掉下去（扔得猛会摔晕，丢到凳子上就坐下）；
/// 在空白处拖动手指，她会跑过来追。手腕歪得厉害，她会往低的一边滑（坐着的会从凳子上滑下来）；
/// 甩一下手腕会把她颠起来，甩得猛撞到屏幕顶会晕。夜里被弄醒后要过一会儿才接着睡。
/// 平时的位置用屏幕宽度的比例表示，各种尺寸的手表都一样；拎着、在空中、滑的时候按屏幕上的点算物理。
final class PetBrain {
    struct Pose {
        let role: String
        let elapsed: TimeInterval
        let loops: Bool
        let root: CGPoint          // 骨骼原点（脚底/椅面/床面）在屏幕上的位置，转动之前
        let facing: CGFloat
        var angle = 0.0            // 绕重心转多少（弧度，顺时针为正）
        var squash: CGFloat = 1    // 落地时竖直方向压扁到多少
        var dizzy = false
    }

    private enum Action {
        case relax(until: Date)
        case walk(from: CGFloat, to: CGFloat, duration: TimeInterval, arrival: Arrival)
        case sit(until: Date)
        case sleep
        case interact
        case chase      // 追着手指跑，手指离开就停
        case held       // 被拎着
        case falling    // 松手后在空中
        case slide      // 手腕歪着，在地上往低的一边滑
    }

    /// 走到地方之后做什么
    private enum Arrival { case relax, sit, sleep }

    /// 拎着、在空中时的身体，单位是屏幕上的点
    private struct Body {
        var center = CGPoint.zero      // 重心
        var previous = CGPoint.zero    // 拎着时上一小步的重心（两步之差就是速度）
        var velocity = CGVector.zero   // 在空中的速度
        var angle = 0.0                // 身体转角（弧度，顺时针为正）
        var spin = 0.0                 // 角速度
        var pivot = CGPoint.zero       // 拎着的那一点
        var rope: CGFloat = 40         // 拎着的那一点到重心的距离
        var tilt = 0.0                 // 拎的那一点不在重心正上方时，吊稳后身子要歪多少
        var bounced = false
        var hard = false               // 摔得重，落地后晕一会儿
    }

    /// 物理参数，按 46mm 屏幕上的点给出
    private enum Physics {
        static let gravity: CGFloat = 1600     // 点/秒²
        static let maxThrow: CGFloat = 1100    // 甩出去的速度上限
        static let bounceSpeed: CGFloat = 650  // 落地快过这个先弹一下
        static let dizzySpeed: CGFloat = 900   // 落地快过这个会晕
        static let bonkSpeed: CGFloat = 500    // 撞屏幕边快过这个也会晕
        static let maxSwing = 1.0              // 拎着最多晃多大（弧度，约 57°）
        // 手腕的倾斜按重力在屏幕左右方向的分量算（-1…1）。设置页里的「手腕灵敏度」会乘上去
        static var slipTilt: CGFloat { 0.45 * Prefs.motionScale }    // 站着时歪过这个（约 27°）站不稳，开始滑
        static let slideFriction: CGFloat = 0.3 // 滑起来以后的摩擦：歪得比这个小就慢慢停下
        static var fallOffTilt: CGFloat { 0.6 * Prefs.motionScale }  // 坐着时歪过这个（约 37°）从凳子上滑下来
        static let leanDeadZone: CGFloat = 0.15 // 在空中、拎着时，歪得比这个小不算，免得看表姿势不同她就飘
    }

    private var action: Action?
    private var start = Date()
    private var x: CGFloat = 0.5
    private var facing: CGFloat = 1
    private var pokedAt: Date?
    private var awakeUntil = Date.distantPast   // 夜里被弄醒，到这时候之前不睡
    private var lastStep: Date?

    // 上一帧的版面：触摸判定和物理都要用
    private var size = CGSize(width: 208, height: 248)
    private var k: CGFloat = 0.5                // 精灵像素 → 屏幕点
    private var height: CGFloat = 133           // 站着时的身高（点）
    private var centerHeight: CGFloat = 60      // 重心离脚底（点）
    private var lastPose: Pose?
    private var hitBox = CGRect.null

    private var body = Body()
    private var finger: CGPoint?
    private var fingerOffset = CGVector.zero    // 拎着的那一点相对手指的位置
    private var grabbedAt = Date.distantPast
    private var landedAt: Date?
    private var dizzyUntil = Date.distantPast   // 摔晕了，到这时候之前头上冒星星
    private var impact: CGFloat = 0            // 上次落地的速度（46mm 屏幕上的点/秒）
    private var chaseTarget: CGFloat?
    private var chaseIdle: Date?                // 追上手指停下来的时间
    private var slideSpeed: CGFloat = 0         // 滑的速度（屏幕上的点/秒，向右为正）
    private var slidePhase: TimeInterval = 0    // 滑的时候跑步动作播到哪

    private var unit: CGFloat { size.width / 208 }   // 46mm 屏幕上的 1 点
    private var ground: CGFloat { size.height * FaceConfig.petGround }

    /// 拎着或在空中（这时画在时间上面）
    var isAirborne: Bool {
        switch action {
        case .held, .falling: true
        default: false
        }
    }

    /// 这一点在不在她身上（按上一帧的位置，四周放宽一点好按）
    func contains(_ point: CGPoint) -> Bool { hitBox.contains(point) }

    /// 轻点：在当前位置停下，做互动动作
    func poke() { pokedAt = Date() }

    /// 按住她：从按到的那一点拎起来。按得太靠下也当是从肩膀拎，免得头朝下吊着
    func grab(at point: CGPoint) {
        if case .held = action { return }
        guard let pose = lastPose else { return }
        let now = Date()
        if !isAirborne {
            if pose.role == "sit" || pose.role == "sleep" {
                // 坐着、躺着的直接变成站姿，吊在手指下面
                body.center = CGPoint(x: point.x, y: point.y + height * 0.3)
            } else {
                body.center = CGPoint(x: pose.root.x, y: pose.root.y - centerHeight)
            }
            body.angle = 0
            body.spin = 0
        }
        let top = body.center.y - (height - centerHeight)
        let hold = CGPoint(x: body.center.x + min(max(point.x - body.center.x, -0.12 * height), 0.12 * height),
                           y: min(point.y, top + 0.35 * height))
        let dx = body.center.x - hold.x, dy = body.center.y - hold.y
        body.pivot = hold
        body.previous = body.center
        body.rope = max(hypot(dx, dy), 0.2 * height)
        body.tilt = body.angle + atan2(Double(dx), Double(dy))
        fingerOffset = CGVector(dx: hold.x - point.x, dy: hold.y - point.y)
        finger = point
        grabbedAt = now
        awakeUntil = now + 20
        landedAt = nil
        dizzyUntil = .distantPast
        begin(.held, at: now)
        WKInterfaceDevice.current().play(.click)
    }

    /// 拎着时手指移动
    func drag(to point: CGPoint) {
        if case .held = action { finger = point }
    }

    /// 松手：带着手指甩的速度飞出去
    func release(throwing velocity: CGSize) {
        guard case .held = action else { return }
        // 系统估算的速度偶尔可能不是有限数，那就当没甩
        var v = velocity.width.isFinite && velocity.height.isFinite ? CGVector(dx: velocity.width, dy: velocity.height) : .zero
        let speed = hypot(v.dx, v.dy), cap = Physics.maxThrow * unit
        if speed > cap {
            v.dx *= cap / speed
            v.dy *= cap / speed
        }
        body.velocity = v
        body.bounced = false
        body.hard = false
        finger = nil
        begin(.falling, at: Date())
    }

    /// 手指在空白处拖动：跑过去追
    func tease(toward point: CGPoint) {
        let target = min(max(point.x / size.width, 0.14), 0.86)
        if case .chase = action {
            chaseTarget = target
            return
        }
        guard !isAirborne else { return }
        let now = Date()
        x = position(at: now)
        chaseTarget = target
        chaseIdle = abs(target - x) < 0.05 ? now : nil
        awakeUntil = now + 20
        begin(.chase, at: now)
    }

    /// 手指离开：追上了就开心一下
    func endTease() {
        guard case .chase = action else { return }
        let now = Date()
        if let chaseTarget, abs(chaseTarget - x) < 0.05 {
            begin(.interact, at: now)
        } else {
            relax(from: now, seconds: 2...4)
        }
        chaseTarget = nil
    }

    /// 甩了一下手腕：把她颠起来，甩得越猛飞得越高；已经在空中就再加一把劲。
    /// 表往右甩，她相对屏幕是往左飞出去
    func toss(_ jolt: CGVector, strength: CGFloat) {
        let now = Date()
        switch action {
        case .held, nil: return
        case .falling: break
        default:
            guard let pose = lastPose else { return }
            body.center = CGPoint(x: pose.root.x, y: ground - centerHeight)
            body.angle = 0
            body.spin = 0
            grabbedAt = now   // 先吓一跳
            begin(.falling, at: now)
        }
        let up = min(max(450 + 300 * (strength - WristMotion.shakeThreshold), 450), 1300) * unit
        body.velocity.dx += (-jolt.dx / max(strength, 0.01) * 300 + .random(in: -60...60)) * unit
        body.velocity.dy = min(body.velocity.dy, 0) - up
        body.spin += .random(in: -6...6)
        body.bounced = false
        body.hard = false
        awakeUntil = now + 20
        landedAt = nil
        dizzyUntil = .distantPast
        WKInterfaceDevice.current().play(.click)
    }

    func pose(at date: Date, sprites: PetSprites, size: CGSize) -> Pose {
        self.size = size
        k = size.width / 208 / sprites.pixelsPerPoint
        height = sprites.height * k
        centerHeight = sprites.center * k
        if action == nil { relax(from: date, seconds: 2...4) }
        if let poked = pokedAt {
            pokedAt = nil
            if !isAirborne {
                x = position(at: poked)
                awakeUntil = poked + 20
                begin(.interact, at: poked)
            }
        }
        let tilt = WristMotion.shared.tilt
        if abs(tilt) > Physics.slipTilt { slip(tilt: tilt, at: date, sprites: sprites) }
        // 拎着、在空中、追手指、滑的时候逐帧推进（只在亮着屏时出现，不用补算）
        let dt = min(max(date.timeIntervalSince(lastStep ?? date), 0), 0.1)
        lastStep = date
        if dt > 0 {
            switch action {
            case .held: swing(dt, tilt: tilt)
            case .falling: fall(dt, tilt: tilt, at: date, sprites: sprites)
            case .chase: run(dt, at: date, sprites: sprites)
            case .slide: slide(dt, tilt: tilt, at: date, sprites: sprites)
            default: break
            }
        }
        // 抬腕前可能停了很久，按时间顺序把错过的动作补完
        while advance(to: date, sprites: sprites) {}
        let pose = makePose(at: date, sprites: sprites)
        lastPose = pose
        hitBox = box(around: pose, sprites: sprites)
        return pose
    }

    /// 当前动作做完就切到下一个；返回 true 表示切换过，要再检查一次
    private func advance(to date: Date, sprites: PetSprites) -> Bool {
        let night = sprites.clips["sleep"] != nil && FaceConfig.isPetSleepTime(date) && date >= awakeUntil
        switch action! {
        case .relax(let until):
            guard date >= until else { return false }
            if night { goToBed(from: until, sprites: sprites) } else { chooseNext(from: until, sprites: sprites) }
        case .walk(_, let to, let duration, let arrival):
            let end = start + duration
            guard date >= end else { return false }
            x = to
            switch arrival {
            case .relax: relax(from: end, seconds: 3...8)
            case .sit: begin(.sit(until: end + .random(in: 8...16)), at: end)
            case .sleep: sleep(from: end, sprites: sprites)
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
        case .chase, .held, .falling, .slide:
            return false
        }
        return true
    }

    private func chooseNext(from date: Date, sprites: PetSprites) {
        let roll = Double.random(in: 0..<1)
        if sprites.clips["sit"] != nil, roll < 0.3 {
            walk(from: date, to: FaceConfig.petStoolX, arrival: .sit, speed: sprites.walkSpeed)
        } else if roll < 0.85 {
            let range = sprites.walkRange
            var target = CGFloat.random(in: range)
            if abs(target - x) < 0.15 { target = x < 0.5 ? range.upperBound : range.lowerBound }
            walk(from: date, to: target, arrival: .relax, speed: sprites.walkSpeed)
        } else {
            relax(from: date, seconds: 3...6)
        }
    }

    /// 夜里先走到垫子那儿再躺下（被扔到别处也会自己走回去）
    private func goToBed(from date: Date, sprites: PetSprites) {
        let range = sprites.sleepRange
        let bed = min(max(x, range.lowerBound), range.upperBound)
        if abs(bed - x) > 0.01 {
            walk(from: date, to: bed, arrival: .sleep, speed: sprites.walkSpeed)
        } else {
            sleep(from: date, sprites: sprites)
        }
    }

    private func position(at date: Date) -> CGFloat {
        guard case .walk(let from, let to, let duration, _) = action, duration > 0 else { return x }
        let t = min(1, max(0, date.timeIntervalSince(start) / duration))
        return from + (to - from) * CGFloat(t)
    }

    private func begin(_ next: Action, at date: Date) {
        action = next
        start = date
    }

    private func relax(from date: Date, seconds: ClosedRange<Double>) {
        begin(.relax(until: date + .random(in: seconds)), at: date)
    }

    private func sleep(from date: Date, sprites: PetSprites) {
        // 躺下比站着宽很多：按睡姿图自己的宽度挑落点，头和脚都不出屏幕
        let range = sprites.sleepRange
        x = min(max(x, range.lowerBound), range.upperBound)
        facing = 1
        begin(.sleep, at: date)
    }

    private func walk(from date: Date, to target: CGFloat, arrival: Arrival, speed points: CGFloat) {
        if abs(target - x) > 0.005 { facing = target > x ? 1 : -1 }
        // 走速按 46mm 屏幕的点数给出，换成「屏幕宽度比例/秒」
        let speed = max(points, 1) / 208
        begin(.walk(from: x, to: target, duration: Double(abs(target - x) / speed), arrival: arrival), at: date)
    }

    /// 拎着：重心吊在拎着的那一点下面，像钟摆一样跟着手指晃（Verlet 积分，每帧分几小步）。手腕歪着就偏向低的一边
    private func swing(_ dt: Double, tilt: CGFloat) {
        guard let finger else { return }
        // 往下拖到脚碰地就不再往下
        let target = CGPoint(x: min(max(finger.x + fingerOffset.dx, 0), size.width),
                             y: min(finger.y + fingerOffset.dy, ground - body.rope - centerHeight))
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = dt / Double(steps)
        let keep = CGFloat(exp(-1.5 * h))                    // 空气阻力：晃几下就停
        let drop = Physics.gravity * unit * CGFloat(h * h)
        let drift = sideGravity(tilt) * CGFloat(h * h)
        let from = body.pivot
        var theta = 0.0
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let pivot = CGPoint(x: from.x + (target.x - from.x) * t, y: from.y + (target.y - from.y) * t)
            let c = body.center
            let moved = CGPoint(x: c.x + (c.x - body.previous.x) * keep + drift, y: c.y + (c.y - body.previous.y) * keep + drop)
            body.previous = c
            // 绳长不变，晃的角度不超过上限
            theta = min(max(atan2(Double(moved.x - pivot.x), Double(moved.y - pivot.y)), -Physics.maxSwing), Physics.maxSwing)
            body.center = CGPoint(x: pivot.x + body.rope * CGFloat(sin(theta)), y: pivot.y + body.rope * CGFloat(cos(theta)))
        }
        body.pivot = target
        let angle = body.tilt - theta
        body.spin = (angle - body.angle) / dt
        body.angle = angle
    }

    /// 在空中：抛物线往下掉（手腕歪着，重力也偏向低的一边），撞到屏幕两边和顶上弹回来（撞得狠会晕），
    /// 身子慢慢转正，落到凳面或地上
    private func fall(_ dt: Double, tilt: CGFloat, at date: Date, sprites: PetSprites) {
        let steps = max(1, Int((dt * 240).rounded(.up)))
        let h = CGFloat(dt) / CGFloat(steps)
        let margin = size.width * 0.14
        let ceiling = height - centerHeight     // 头顶碰到屏幕上沿时重心的高度
        let sit = sprites.clips["sit"]
        let seat = ground - (sit?.lift ?? 0) * k                // 凳面高度
        let seatHalfWidth = (sit?.lift ?? 0) * k * 1.25 / 2     // 和画出来的凳子一样宽
        let stoolX = FaceConfig.petStoolX * size.width
        let side = sideGravity(tilt)
        for _ in 0..<steps {
            let feetBefore = body.center.y + centerHeight
            body.velocity.dx += side * h
            body.velocity.dy += Physics.gravity * unit * h
            body.center.x += body.velocity.dx * h
            body.center.y += body.velocity.dy * h
            body.spin += (-100 * body.angle - 16 * body.spin) * Double(h)
            body.angle += body.spin * Double(h)
            if body.center.x < margin || body.center.x > size.width - margin {
                bonk(speed: abs(body.velocity.dx))
                body.center.x = min(max(body.center.x, margin), size.width - margin)
                body.velocity.dx = (body.center.x < size.width / 2 ? 1 : -1) * abs(body.velocity.dx) * 0.45
            }
            if body.center.y < ceiling, body.velocity.dy < 0 {
                bonk(speed: -body.velocity.dy)
                body.center.y = ceiling
                body.velocity.dy *= -0.4
            }
            guard body.velocity.dy > 0 else { continue }
            let feet = body.center.y + centerHeight
            if sit != nil, abs(body.center.x - stoolX) < seatHalfWidth, feetBefore <= seat, feet >= seat {
                if land(on: seat, at: date, stool: true) { return }
            } else if feet >= ground {
                if land(on: ground, at: date, stool: false) { return }
            }
        }
    }

    /// 撞到屏幕边上
    private func bonk(speed: CGFloat) {
        guard speed / unit > Physics.bonkSpeed else { return }
        body.hard = true
        WKInterfaceDevice.current().play(.click)
    }

    /// 碰到凳面或地面；站稳了返回 true
    private func land(on surface: CGFloat, at date: Date, stool: Bool) -> Bool {
        let speed = body.velocity.dy / unit
        body.center.y = surface - centerHeight
        landedAt = date
        impact = speed
        if speed > Physics.dizzySpeed { body.hard = true }
        if speed > Physics.bounceSpeed {
            WKInterfaceDevice.current().play(.click)
            if !body.bounced, !stool {
                // 摔得重先弹一下
                body.bounced = true
                body.velocity.dy *= -0.3
                body.velocity.dx *= 0.6
                return false
            }
        }
        body.angle = 0
        body.spin = 0
        if body.hard { dizzyUntil = date + 2.5 }
        if stool {
            x = FaceConfig.petStoolX
            begin(.sit(until: date + .random(in: 8...16)), at: date)
        } else {
            // 晕着的时候待在原地
            x = body.center.x / size.width
            relax(from: date, seconds: body.hard ? 3...4 : 2...4)
        }
        return true
    }

    /// 追手指：跑到手指下面停住，手指走远了再接着追
    private func run(_ dt: Double, at date: Date, sprites: PetSprites) {
        guard let target = chaseTarget else { return }
        let dx = target - x
        if chaseIdle != nil, abs(dx) < 0.05 { return }
        guard abs(dx) > 0.01 else {
            chaseIdle = date
            return
        }
        chaseIdle = nil
        facing = dx > 0 ? 1 : -1
        let step = max(sprites.walkSpeed, 1) * 2 / 208 * CGFloat(dt)   // 跑起来是走路的两倍快
        x += min(max(dx, -step), step)
    }

    /// 手腕歪得站不稳：站着、走着的开始往低的一边滑，睡着的被弄醒；坐着的歪得再狠一点就从凳子上滑下来
    private func slip(tilt: CGFloat, at date: Date, sprites: PetSprites) {
        switch action {
        case .relax, .walk, .interact, .sleep:
            if case .sleep = action { awakeUntil = date + 20 }
            x = position(at: date)
            slideSpeed = 0
            slidePhase = 0
            begin(.slide, at: date)
        case .sit where abs(tilt) > Physics.fallOffTilt:
            let seat = ground - (sprites.clips["sit"]?.lift ?? 0) * k
            body.center = CGPoint(x: x * size.width, y: seat - centerHeight * 0.4)
            body.velocity = CGVector(dx: (tilt > 0 ? 150 : -150) * unit, dy: -150 * unit)
            body.angle = 0
            body.spin = tilt > 0 ? 3 : -3
            body.bounced = false
            body.hard = false
            grabbedAt = date   // 吓一跳
            landedAt = nil
            begin(.falling, at: date)
        default:
            break
        }
    }

    /// 歪着手腕：顺着地面往低的一边滑。站着不动时歪过 slipTilt 才滑得动，滑起来以后摩擦小一些；
    /// 撞到屏幕边停住，撞得猛会晕。停下来以后只要歪得不够让她再滑起来，就接着过日子
    private func slide(_ dt: Double, tilt: CGFloat, at date: Date, sprites: PetSprites) {
        let g = Physics.gravity * unit, h = CGFloat(dt)
        var v = slideSpeed
        if v == 0 {
            if abs(tilt) > Physics.slipTilt { v = g * (tilt - Physics.slideFriction * (tilt > 0 ? 1 : -1)) * h }
        } else {
            // 摩擦只会让她停下，不会把她往回推
            let next = v + g * (tilt - Physics.slideFriction * (v > 0 ? 1 : -1)) * h
            v = next * v > 0 ? next : 0
        }
        let margin = size.width * 0.14
        var px = x * size.width + v * h
        if px < margin || px > size.width - margin {
            px = min(max(px, margin), size.width - margin)
            if abs(v) / unit > Physics.bonkSpeed { dizzyUntil = date + 2.5 }
            if abs(v) / unit > 150 { WKInterfaceDevice.current().play(.click) }
            v = 0
        }
        x = px / size.width
        slideSpeed = v
        if v != 0 {
            facing = v > 0 ? 1 : -1
            // 跑步动作跟着滑的速度加快，最快三倍
            slidePhase += dt * Double(min(max(abs(v) / (max(sprites.walkSpeed, 1) * unit), 1), 3))
        } else if abs(tilt) <= Physics.slipTilt {
            relax(from: date, seconds: 2...4)
        }
    }

    /// 重力在屏幕左右方向的分量（点/秒²），在空中、拎着时用
    private func sideGravity(_ tilt: CGFloat) -> CGFloat {
        let lean = max(abs(tilt) - Physics.leanDeadZone, 0)
        return Physics.gravity * unit * (tilt > 0 ? lean : -lean)
    }

    private func makePose(at date: Date, sprites: PetSprites) -> Pose {
        let elapsed = date.timeIntervalSince(start)
        let squash = squash(at: date)
        // 在地上：站着原点就是脚底，坐、躺的原点离地 lift
        func grounded(_ role: String, _ elapsed: TimeInterval, loops: Bool = true, x: CGFloat? = nil) -> Pose {
            let lift = (sprites.clips[role]?.lift ?? 0) * k
            return Pose(role: role, elapsed: elapsed, loops: loops,
                        root: CGPoint(x: (x ?? self.x) * size.width, y: ground - lift),
                        facing: facing, squash: squash, dizzy: date < dizzyUntil)
        }
        switch action! {
        case .relax: return grounded("relax", elapsed)
        case .walk: return grounded("move", elapsed, x: position(at: date))
        case .sit: return grounded("sit", elapsed)
        case .sleep: return grounded("sleep", elapsed)
        case .interact: return grounded("interact", elapsed, loops: false)
        case .chase:
            if let idle = chaseIdle { return grounded("relax", date.timeIntervalSince(idle)) }
            return grounded("move", elapsed * 2)   // 跑起来动作也快一倍
        case .slide:
            // 滑的时候脚下跟着跑，停在屏幕边就站着
            return slideSpeed == 0 ? grounded("relax", elapsed) : grounded("move", slidePhase)
        case .held, .falling:
            // 刚拎起来先吓一跳（互动动作），之后手脚乱蹬（走路动作）
            let held = date.timeIntervalSince(grabbedAt)
            let surprise = sprites.clips["interact"]?.duration ?? 0
            let (role, t) = held < surprise ? ("interact", held) : ("move", held - surprise)
            return Pose(role: role, elapsed: t, loops: true,
                        root: CGPoint(x: body.center.x, y: body.center.y + centerHeight),
                        facing: facing, angle: body.angle, squash: squash)
        }
    }

    /// 放下手腕（常亮显示）时画的那一帧：不管此刻在走路还是在半空中，都画成站稳的样子
    /// （本来在坐、在睡就保持坐、睡），免得定格在走一半或者飘在空中
    func restPose(sprites: PetSprites, size: CGSize) -> Pose {
        let k = size.width / 208 / sprites.pixelsPerPoint
        let ground = size.height * FaceConfig.petGround
        var role = "relax"
        var fraction = x
        switch action {
        case .sit: role = "sit"
        case .sleep: role = "sleep"
        case .walk: fraction = position(at: Date())
        case .held, .falling: fraction = min(max(body.center.x / size.width, 0.08), 0.92)
        default: break
        }
        if sprites.clips[role] == nil { role = "relax" }
        let lift = (sprites.clips[role]?.lift ?? 0) * k
        return Pose(role: role, elapsed: 0, loops: true,
                    root: CGPoint(x: fraction * size.width, y: ground - lift), facing: facing)
    }

    /// 落地时以脚底为轴压扁，再弹回来
    private func squash(at date: Date) -> CGFloat {
        guard let landedAt else { return 1 }
        let t = date.timeIntervalSince(landedAt)
        guard t >= 0, t < 0.5 else { return 1 }
        let depth = min(0.22, impact / 4500)
        return 1 - depth * CGFloat(exp(-t * 8) * cos(t * 24))
    }

    /// 触摸判定框：站姿按身体算（原点左右各 0.32 个身高），坐、躺按整张图算；四周放宽 4 点
    private func box(around pose: Pose, sprites: PetSprites) -> CGRect {
        let rect: CGRect
        if pose.role == "sit" || pose.role == "sleep", let clip = sprites.clips[pose.role] {
            let w = clip.size.width * k, ax = clip.anchor.x * k
            rect = CGRect(x: pose.facing > 0 ? pose.root.x - ax : pose.root.x - (w - ax), y: pose.root.y - clip.anchor.y * k,
                          width: w, height: clip.size.height * k)
        } else {
            rect = CGRect(x: pose.root.x - 0.32 * height, y: pose.root.y - height, width: 0.64 * height, height: height)
        }
        return rect.insetBy(dx: -4 * unit, dy: -4 * unit)
    }
}

/// 桌宠模式的背景：背景图（没有就用深色渐变），再加一张凳子
struct PetBackdrop: View {
    let sprites: PetSprites
    let image: CGImage?   // nil 时用深色渐变

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 208 / sprites.pixelsPerPoint   // 精灵像素 → 屏幕点
            let ground = geo.size.height * FaceConfig.petGround
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
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
            }
        }
    }
}

/// 桌宠本身：每帧问 PetBrain 摆什么动作、站在哪、转多少
struct PetLayer: View {
    let sprites: PetSprites
    let brain: PetBrain
    let paused: Bool

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 208 / sprites.pixelsPerPoint   // 精灵像素 → 屏幕点
            let ground = geo.size.height * FaceConfig.petGround
            if paused {
                // 放下手腕（常亮显示）：画一张站稳的静止画面，不定格在走一半或者半空中
                figure(brain.restPose(sprites: sprites, size: geo.size), k: k, ground: ground, time: nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    figure(brain.pose(at: context.date, sprites: sprites, size: geo.size), k: k, ground: ground,
                           time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    /// 画某一帧。time 为 nil 表示常亮显示的静止画面，这时不画打呼的 z 和摔晕的星星
    @ViewBuilder
    private func figure(_ pose: PetBrain.Pose, k: CGFloat, ground: CGFloat, time: TimeInterval?) -> some View {
        if let clip = sprites.clips[pose.role] ?? sprites.clips["relax"],
           let image = sprites.image(pose.role, elapsed: pose.elapsed, loops: pose.loops) {
            let w = clip.size.width * k, h = clip.size.height * k
            let ax = clip.anchor.x * k, ay = clip.anchor.y * k
            ZStack {
                if pose.role == "sleep" {
                    // 垫子：铺在身体正下方
                    RoundedRectangle(cornerRadius: 3 * k * 2)
                        .fill(Color(red: 0.16, green: 0.2, blue: 0.3))
                        .frame(width: w * 0.8, height: 7 * k * 2)
                        .position(x: pose.root.x + (w / 2 - ax) * pose.facing, y: ground - 2 * k * 2)
                }
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: w, height: h)
                    // 以原点为轴水平翻转（转身时脚不挪位），落地时也以原点为轴压扁
                    .scaleEffect(x: pose.facing * (1 + (1 - pose.squash) * 0.6), y: pose.squash,
                                 anchor: UnitPoint(x: ax / w, y: ay / h))
                    // 拎着晃、扔出去转，都绕重心
                    .rotationEffect(.radians(pose.angle), anchor: UnitPoint(x: ax / w, y: (ay - sprites.center * k) / h))
                    .position(x: pose.root.x - ax + w / 2, y: pose.root.y - ay + h / 2)
                if pose.role == "sleep", let time {
                    Snore(time: time, size: 12 * k * 2)
                        .position(x: pose.root.x - ax * 0.55 * pose.facing, y: pose.root.y - ay - 6 * k * 2)
                }
                if pose.dizzy, let time {
                    // 绕着头顶转（图的上沿差不多就是头顶，站着坐着都适用）
                    DizzyStars(time: time, size: 11 * k * 2)
                        .position(x: pose.root.x, y: pose.root.y - ay + sprites.height * 0.06 * k)
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

/// 摔晕时头顶绕圈的小星星：转到前面的大一点
private struct DizzyStars: View {
    let time: TimeInterval
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let a = time * 2 * .pi / 1.1 + Double(i) * 2 * .pi / 3
                Image(systemName: "star.fill")
                    .font(.system(size: size * (0.8 + 0.25 * sin(a))))
                    .foregroundStyle(Color(red: 1, green: 0.94, blue: 0.55))
                    .shadow(color: .black.opacity(0.8), radius: 1.2)
                    .offset(x: cos(a) * size * 2, y: sin(a) * size * 0.4)
            }
        }
    }
}
