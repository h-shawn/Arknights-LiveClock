import Foundation

/// 常用设置，改完重新运行到手表即可。各时间样式自己的字号、位置在 ClockStyles.swift。
enum FaceConfig {
    /// 时间样式：.top 顶部、.classic 左下大字、.menu 仿 P3R 菜单、.center 居中、.none 只留系统小时间
    static let clockStyle = ClockStyle.top
    /// 24 小时制；改成 false 用 12 小时制
    static let use24Hour = true
    /// 放下手腕（常亮显示）时背景的亮度：0 为全黑，1 为不变暗
    static let alwaysOnBackgroundOpacity = 0.35
    /// 桌宠模式：脚底所在的高度（屏幕高度的比例），左右走动的范围（屏幕宽度的比例）
    static let petGround: CGFloat = 0.93
    static let petRange: ClosedRange<CGFloat> = 0.3...0.7
    /// 凳子放在哪（屏幕宽度的比例）；躺下时离屏幕边的安全范围
    static let petStoolX: CGFloat = 0.78
    static let petSleepRange: ClosedRange<CGFloat> = 0.36...0.42
    /// 几点到几点睡觉（24 小时制，可以跨午夜）
    static let petSleepFrom = 23, petSleepTo = 7

    static func isPetSleepTime(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return petSleepFrom > petSleepTo ? (hour >= petSleepFrom || hour < petSleepTo)
                                         : (hour >= petSleepFrom && hour < petSleepTo)
    }
}
