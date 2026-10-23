import SwiftUI

/// 整块“表盘”：背景动画 + 时间。轻点屏幕戳一下桌宠，长按换背景，转表冠换桌宠，选择都会被记住。
struct FaceView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @AppStorage("petIndex") private var petIndex = 0
    @AppStorage("backgroundIndex") private var backgroundIndex = 0
    @State private var pet = PetBrain()
    @State private var crown = 0.0
    @State private var toast: String?

    var body: some View {
        let style = FaceConfig.clockStyle
        ZStack {
            // 放下手腕（常亮显示）时动画暂停、背景变暗
            Background(paused: isLuminanceReduced, pet: pet, petIndex: petIndex, backgroundIndex: backgroundIndex)
                .opacity(isLuminanceReduced ? FaceConfig.alwaysOnBackgroundOpacity : 1)
            // 常亮时系统按这个时间表预先渲染每分钟的画面，时间照常走
            TimelineView(.everyMinute) { context in
                ClockView(style: style, date: context.date)
            }
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
        .contentShape(Rectangle())
        // 长按优先：按住不放换背景，没按够时长就算轻点
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard !PetRoster.folders.isEmpty else { return }
                    backgroundIndex = (backgroundIndex + 1) % Backdrops.count
                    showToast(Backdrops.name(at: backgroundIndex))
                }
                .exclusively(before: TapGesture().onEnded { pet.poke() })
        )
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
        }
        // 右上角的系统时间：自己画了时间就藏起来，纯动画样式留着它。
        // _statusBarHidden 是 SwiftUI 公开但没写进文档的接口，系统更新后可能失效。
        ._statusBarHidden(style != .none)
    }

    private func showToast(_ text: String?) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if toast == text { withAnimation { toast = nil } }
        }
    }
}
