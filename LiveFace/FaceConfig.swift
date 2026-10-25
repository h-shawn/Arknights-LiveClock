import Foundation

/// 常用设置，改完重新运行到手表即可。各时间样式自己的字号、位置在 ClockStyles.swift。
/// 上面这几项现在也能在 App 里改：在空白处双击打开设置（存在 UserDefaults 里，见 Settings.swift）。
enum FaceConfig {
    /// 时间样式：.top 顶部、.classic 左下大字、.menu 仿 P3R 菜单、.center 居中、.none 只留系统小时间
    static var clockStyle: ClockStyle { Prefs.clockStyle }
    /// 24 小时制；关掉用 12 小时制
    static var use24Hour: Bool { Prefs.use24Hour }
    /// 放下手腕（常亮显示）时背景的亮度：0 为全黑，1 为不变暗
    static var alwaysOnBackgroundOpacity: Double { Prefs.alwaysOnOpacity }
    /// 几点到几点睡觉（24 小时制，可以跨午夜）
    static var petSleepFrom: Int { Prefs.sleepFrom }
    static var petSleepTo: Int { Prefs.sleepTo }

    /// 桌宠模式：脚底所在的高度（屏幕高度的比例），左右走动的范围（屏幕宽度的比例）
    static let petGround: CGFloat = 0.93
    static let petRange: ClosedRange<CGFloat> = 0.3...0.7
    /// 凳子放在哪（屏幕宽度的比例）；躺下时离屏幕边的安全范围
    static let petStoolX: CGFloat = 0.78
    static let petSleepRange: ClosedRange<CGFloat> = 0.36...0.42

    static func isPetSleepTime(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return petSleepFrom > petSleepTo ? (hour >= petSleepFrom || hour < petSleepTo)
                                         : (hour >= petSleepFrom && hour < petSleepTo)
    }
}
