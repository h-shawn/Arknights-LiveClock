import SwiftUI

/// App 里能改的设置：在空白处双击打开。存在 UserDefaults 里，关掉再开还在。
/// 没列在这儿的（站的高度、走动范围、凳子位置）还是改 FaceConfig.swift 里的常量。
enum Prefs {
    /// App 和表盘复杂功能都读这一份，所以放在 App Group 里（免费账号也能用）
    static let store: UserDefaults = {
        guard let shared = UserDefaults(suiteName: "group.com.shawn.liveface") else { return .standard }
        // 以前存在 App 自己的沙盒里，第一次运行搬过来
        if shared.object(forKey: Key.migrated) == nil {
            for key in Key.all where UserDefaults.standard.object(forKey: key) != nil {
                shared.set(UserDefaults.standard.object(forKey: key), forKey: key)
            }
            shared.set(true, forKey: Key.migrated)
        }
        return shared
    }()

    /// 表盘上那个「世界时钟」显示哪座城市
    /// name 给设置页看，english 显示在表盘上（表盘上的字一律用英文）
    struct City: Hashable {
        let name: String
        let english: String
        let timeZone: String
    }

    static let cities = [
        City(name: "北京", english: "Beijing", timeZone: "Asia/Shanghai"),
        City(name: "香港", english: "Hong Kong", timeZone: "Asia/Hong_Kong"),
        City(name: "东京", english: "Tokyo", timeZone: "Asia/Tokyo"),
        City(name: "首尔", english: "Seoul", timeZone: "Asia/Seoul"),
        City(name: "新加坡", english: "Singapore", timeZone: "Asia/Singapore"),
        City(name: "迪拜", english: "Dubai", timeZone: "Asia/Dubai"),
        City(name: "伦敦", english: "London", timeZone: "Europe/London"),
        City(name: "巴黎", english: "Paris", timeZone: "Europe/Paris"),
        City(name: "纽约", english: "New York", timeZone: "America/New_York"),
        City(name: "芝加哥", english: "Chicago", timeZone: "America/Chicago"),
        City(name: "洛杉矶", english: "Los Angeles", timeZone: "America/Los_Angeles"),
        City(name: "温哥华", english: "Vancouver", timeZone: "America/Vancouver"),
        City(name: "悉尼", english: "Sydney", timeZone: "Australia/Sydney"),
    ]

    static var city: City {
        let id = store.string(forKey: Key.cityTimeZone) ?? cities[0].timeZone
        return cities.first { $0.timeZone == id } ?? cities[0]
    }

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
        static let cityTimeZone = "cityTimeZone"
        static let petIndex = "petIndex"
        static let backgroundIndex = "backgroundIndex"
        static let migrated = "migratedToAppGroup"

        static let all = [clockStyle, use24Hour, alwaysOnPercent, sleepFrom, sleepTo,
                          sensitivity, cityTimeZone, petIndex, backgroundIndex]
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
        store.object(forKey: key) as? Int ?? fallback
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        store.object(forKey: key) as? Bool ?? fallback
    }

}

/// 设置页：转表冠上下翻，点右上角「完成」关掉
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.Key.clockStyle, store: Prefs.store) private var clockStyle = 3
    @AppStorage(Prefs.Key.use24Hour, store: Prefs.store) private var use24Hour = true
    @AppStorage(Prefs.Key.alwaysOnPercent, store: Prefs.store) private var alwaysOnPercent = 35
    @AppStorage(Prefs.Key.sleepFrom, store: Prefs.store) private var sleepFrom = 23
    @AppStorage(Prefs.Key.sleepTo, store: Prefs.store) private var sleepTo = 7
    @AppStorage(Prefs.Key.sensitivity, store: Prefs.store) private var sensitivity = Prefs.Sensitivity.normal.rawValue
    @AppStorage(Prefs.Key.cityTimeZone, store: Prefs.store) private var cityTimeZone = Prefs.cities[0].timeZone

    // 「仿 P3R 菜单」是给视频模式做的版式，桌宠模式用不上，不列在这儿。
    // ClockStyle.menu 还在，想用就改 Prefs.clockStyle 的出厂值
    private static let styles: [(ClockStyle, String)] = [
        (.classic, "左下大字"), (.center, "居中细体"), (.top, "顶部"), (.none, "不画时间"),
    ]
    private static let brightness: [(String, Int)] = [("暗", 20), ("中", 35), ("亮", 60)]

    var body: some View {
        NavigationStack {
            List {
                Section("时间") {
                    Picker("样式", selection: $clockStyle) {
                        ForEach(Self.styles, id: \.0) { style, name in
                            Text(name).tag(style.rawValue)
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
                Section {
                    Picker("城市", selection: $cityTimeZone) {
                        ForEach(Prefs.cities, id: \.timeZone) { city in
                            Text("\(city.name) \(city.english)").tag(city.timeZone)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("表盘上的世界时钟")
                } footer: {
                    Text("系统表盘的复杂功能里，干员头像旁边显示这座城市的时间。")
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
