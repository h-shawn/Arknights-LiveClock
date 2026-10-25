import SwiftUI

/// App 里能改的设置：在空白处双击打开。存在 UserDefaults 里，关掉再开还在。
/// 没列在这儿的（站的高度、走动范围、凳子位置）还是改 FaceConfig.swift 里的常量。
enum Prefs {
    /// 歪手腕、甩手腕的灵敏度：阈值乘这个数，越小越容易触发
    enum Sensitivity: Int, CaseIterable {
        case light = 0, normal = 1, heavy = 2

        var scale: CGFloat {
            switch self {
            case .light: return 0.7
            case .normal: return 1
            case .heavy: return 1.4
            }
        }

        var name: String {
            switch self {
            case .light: return "灵敏"
            case .normal: return "普通"
            case .heavy: return "迟钝"
            }
        }
    }

    enum Key {
        static let clockStyle = "clockStyle"
        static let use24Hour = "use24Hour"
        static let alwaysOnPercent = "alwaysOnPercent"
        static let sleepFrom = "sleepFrom"
        static let sleepTo = "sleepTo"
        static let sensitivity = "sensitivity"
    }

    static var clockStyle: ClockStyle { ClockStyle(rawValue: int(Key.clockStyle, 3)) ?? .top }
    static var use24Hour: Bool { bool(Key.use24Hour, true) }
    /// 存成整数的百分比，Picker 的选中值才能精确对上
    static var alwaysOnOpacity: Double { Double(int(Key.alwaysOnPercent, 35)) / 100 }
    static var sleepFrom: Int { int(Key.sleepFrom, 23) }
    static var sleepTo: Int { int(Key.sleepTo, 7) }
    static var motionScale: CGFloat {
        (Sensitivity(rawValue: int(Key.sensitivity, Sensitivity.normal.rawValue)) ?? .normal).scale
    }

    /// UserDefaults 里没写过的时候返回出厂值（没写过和写了 0 要分开）
    private static func int(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

}

/// 设置页：转表冠上下翻，点右上角「完成」关掉
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.Key.clockStyle) private var clockStyle = 3
    @AppStorage(Prefs.Key.use24Hour) private var use24Hour = true
    @AppStorage(Prefs.Key.alwaysOnPercent) private var alwaysOnPercent = 35
    @AppStorage(Prefs.Key.sleepFrom) private var sleepFrom = 23
    @AppStorage(Prefs.Key.sleepTo) private var sleepTo = 7
    @AppStorage(Prefs.Key.sensitivity) private var sensitivity = Prefs.Sensitivity.normal.rawValue

    private static let styleNames = ["左下大字", "仿 P3R 菜单", "居中细体", "顶部", "不画时间"]
    private static let brightness: [(String, Int)] = [("暗", 20), ("中", 35), ("亮", 60)]

    var body: some View {
        NavigationStack {
            List {
                Section("时间") {
                    Picker("样式", selection: $clockStyle) {
                        ForEach(Array(Self.styleNames.enumerated()), id: \.offset) { i, name in
                            Text(name).tag(i)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Toggle("24 小时制", isOn: $use24Hour)
                }
                Section("常亮显示") {
                    Picker("背景亮度", selection: $alwaysOnPercent) {
                        ForEach(Self.brightness, id: \.1) { name, value in
                            Text(name).tag(value)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("睡觉") {
                    Picker("从", selection: $sleepFrom) { hours }
                        .pickerStyle(.navigationLink)
                    Picker("到", selection: $sleepTo) { hours }
                        .pickerStyle(.navigationLink)
                }
                Section {
                    Picker("手腕灵敏度", selection: $sensitivity) {
                        ForEach(Prefs.Sensitivity.allCases, id: \.rawValue) { s in
                            Text(s.name).tag(s.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("歪手腕她会往低处滑，甩一下手腕会把她颠起来。太容易触发就调成「迟钝」。")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var hours: some View {
        ForEach(0..<24, id: \.self) { h in
            Text(String(format: "%02d:00", h)).tag(h)
        }
    }
}
