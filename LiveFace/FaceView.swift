import SwiftUI
import WidgetKit

/// 整块“表盘”：背景 + 桌宠 + 时间。转表冠换桌宠，选择都会被记住。
/// 触摸：轻点戳一下桌宠；按住她（或直接拖）能拎起来、扔出去；在空白处拖动，她会跑来追手指；
/// 在空白处按住不动换背景，在空白处双击打开设置。手腕：歪着她会往低的一边滑，甩一下把她颠起来。
struct FaceView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
    // 和表盘复杂功能共用一份存储，换了干员表盘上的头像也跟着换
    @AppStorage(Prefs.Key.petIndex, store: Prefs.store) private var petIndex = 0
    @AppStorage(Prefs.Key.backgroundIndex, store: Prefs.store) private var backgroundIndex = 0
    @State private var pet = PetBrain()
    @State private var crown = 0.0
    @State private var toast: String?
    @State private var lifted = false   // 拎着、在空中时把桌宠画到时间上面
    @State private var touch = Touch()
    @State private var showSettings = false
    @State private var lastTap = Date.distantPast
    @GestureState private var touching = false

    var body: some View {
        let style = FaceConfig.clockStyle
        let sprites = PetRoster.sprites(at: petIndex)
        ZStack {
            Background(paused: isLuminanceReduced, sprites: sprites, backgroundIndex: backgroundIndex)
            if let sprites {
                PetLayer(sprites: sprites, brain: pet, paused: isLuminanceReduced)
                    .zIndex(lifted && !isLuminanceReduced ? 3 : 1)
            }
            // 放下手腕（常亮显示）时动画暂停、画面变暗，时间不变暗
            if isLuminanceReduced {
                Color.black.opacity(1 - FaceConfig.alwaysOnBackgroundOpacity)
                    .zIndex(2)
            }
            // 常亮时系统按这个时间表预先渲染每分钟的画面，时间照常走
            TimelineView(.everyMinute) { context in
                ClockView(style: style, date: context.date)
            }
            .zIndex(2.5)
        }
        .background(.black)
        .overlay(alignment: .bottom) {
            // 换桌宠、换背景时在底部短暂显示名字
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showSettings) { SettingsView() }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { touchMoved(to: $0.location, from: $0.startLocation) }
                .onEnded { touchEnded(throwing: $0.velocity) }
        )
        // 触摸被系统打断（比如放下手腕）时不会有 onEnded，在这里收尾
        .onChange(of: touching) { _, now in
            if !now { touchEnded(throwing: .zero) }
        }
        // 第一次打开时要一下运动数据的权限，顺便刷新表盘上的圆环
        .onAppear {
            ActivityRings.requestAccess()
            WidgetCenter.shared.reloadAllTimelines()
        }
        // 亮着屏、在前台时才开运动传感器
        .onAppear(perform: updateMotion)
        .onChange(of: scenePhase, updateMotion)
        .onChange(of: isLuminanceReduced, updateMotion)
        // 表冠每转一格换一位桌宠
        .focusable(PetRoster.folders.count > 1)
        .focusEffectDisabled()
        .digitalCrownRotation($crown, from: -100_000, through: 100_000, by: 1, sensitivity: .low,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { old, new in
            let step = Int((new - old).rounded())
            let count = PetRoster.folders.count
            guard step != 0, count > 1 else { return }
            petIndex = ((petIndex + step) % count + count) % count
            pet = PetBrain()
            showToast(PetRoster.sprites(at: petIndex)?.name)
            WidgetCenter.shared.reloadAllTimelines()
        }
        // 右上角的系统时间：自己画了时间就藏起来，纯动画样式留着它。
        // _statusBarHidden 是 SwiftUI 公开但没写进文档的接口，系统更新后可能失效。
        ._statusBarHidden(style != .none)
    }

    /// 一次触摸算什么，按下时还不知道，边按边定
    private final class Touch {
        enum Kind { case undecided, grab, tease, done }
        var kind: Kind?             // nil：手指没按着
        var onPet = false
        var location = CGPoint.zero
        var timer: Task<Void, Never>?
        var landing: Task<Void, Never>?
    }

    private func touchMoved(to location: CGPoint, from start: CGPoint) {
        touch.location = location
        if touch.kind == nil {
            // 刚按下：按在她身上，按住一会儿就拎起来；按在空白处，按住不动够久就换背景
            let onPet = pet.contains(start)
            touch.kind = .undecided
            touch.onPet = onPet
            touch.timer = Task {
                try? await Task.sleep(for: .milliseconds(onPet ? 250 : 500))
                guard !Task.isCancelled, touch.kind == .undecided else { return }
                if onPet {
                    grab(at: touch.location)
                } else {
                    touch.kind = .done
                    nextBackground()
                }
            }
        }
        if touch.kind == .undecided, hypot(location.x - start.x, location.y - start.y) > 5 {
            // 动起来了：从她身上拖是拎，从空白处拖是逗她
            touch.timer?.cancel()
            if touch.onPet { grab(at: start) } else { touch.kind = .tease }
        }
        switch touch.kind {
        case .grab: pet.drag(to: location)
        case .tease: pet.tease(toward: location)
        default: break
        }
    }

    private func touchEnded(throwing velocity: CGSize) {
        guard let kind = touch.kind else { return }
        touch.kind = nil
        touch.timer?.cancel()
        switch kind {
        case .undecided:
            // 在空白处连点两下打开设置（第一下还是会戳她一下，当作按下去的反馈）
            let now = Date()
            if !touch.onPet, now.timeIntervalSince(lastTap) < 0.4 {
                lastTap = .distantPast
                showSettings = true
                return
            }
            lastTap = touch.onPet ? .distantPast : now
            pet.poke()
        case .grab:
            pet.release(throwing: velocity)
            putBackWhenLanded()
        case .tease:
            pet.endTease()
        case .done:
            break
        }
    }

    private func grab(at point: CGPoint) {
        touch.kind = .grab
        touch.landing?.cancel()
        pet.grab(at: point)
        lifted = true
    }

    /// 落地后把她放回时间下面
    private func putBackWhenLanded() {
        touch.landing?.cancel()
        touch.landing = Task {
            while pet.isAirborne {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            lifted = false
        }
    }

    private func updateMotion() {
        let motion = WristMotion.shared
        guard scenePhase == .active, !isLuminanceReduced else {
            motion.stop()
            return
        }
        // 甩一下手腕把她颠起来；手指按着屏幕时不算
        motion.onShake = { jolt, strength in
            guard touch.kind == nil else { return }
            pet.toss(jolt, strength: strength)
            if pet.isAirborne {
                lifted = true
                putBackWhenLanded()
            }
        }
        motion.start()
    }

    private func nextBackground() {
        guard !PetRoster.folders.isEmpty else { return }
        backgroundIndex = (backgroundIndex + 1) % Backdrops.count
        showToast(Backdrops.name(at: backgroundIndex))
    }

    private func showToast(_ text: String?) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if toast == text { withAnimation { toast = nil } }
        }
    }
}
