import SwiftUI

/// 时间样式，在 App 的设置页里选（空白处双击打开），出厂默认在 Prefs.clockStyle。
/// ClockStyle 的 rawValue 存进 UserDefaults，所以不要改现有 case 的顺序。想加新样式：加一个 case，再在 ClockView 里接上对应的 View。
/// 所有尺寸都按 46mm 屏幕（208×248 点）设计，其他尺寸按屏幕宽高等比缩放。
enum ClockStyle: Int, CaseIterable {
    case classic   // 左下：日期 + 大号时间
    case menu      // 右侧：仿 P3R 主菜单的四行斜体，时、分、日期、星期互相压叠
    case center    // 居中：细体大字
    case top       // 顶部：时间和日期在上方，下半屏留给角色
    case none      // 纯动画：不画时间，保留右上角系统自带的小时间
}

struct ClockView: View {
    let style: ClockStyle
    let date: Date

    var body: some View {
        switch style {
        case .classic: ClassicClock(date: date)
        case .menu: MenuClock(date: date)
        case .center: CenterClock(date: date)
        case .top: TopClock(date: date)
        case .none: EmptyView()
        }
    }
}

private enum Format {
    /// 用系统首选语言格式化日期。App 本身没做本地化，直接用 Locale.current 会变成英文日期。
    static let locale = Locale(identifier: Locale.preferredLanguages.first ?? "en_US")

    static func time(_ date: Date) -> String {
        // 12/24 小时制随时能在设置里改，每次按当前设置取格式
        let format = FaceConfig.use24Hour ? "HH:mm" : "h:mm"
        if timeFormatter.dateFormat != format { timeFormatter.dateFormat = format }
        return timeFormatter.string(from: date)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated).locale(locale))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// 左下：日期 + 大号时间，底部压一层渐暗，换什么视频都看得清。
struct ClassicClock: View {
    let date: Date

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 208
            VStack(alignment: .leading, spacing: -6 * s) {
                Text(Format.date(date))
                    .font(.system(size: 16 * s, weight: .semibold, design: .rounded))
                Text(Format.time(date))
                    .font(.system(size: 64 * s, weight: .bold, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 5 * s, y: 2 * s)
            .padding(.leading, 18 * s)
            .padding(.bottom, 16 * s)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    .frame(height: geo.size.height * 0.5)
            }
        }
    }
}

/// 居中：细体大字 + 日期。
struct CenterClock: View {
    let date: Date

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 208
            VStack(spacing: 2 * s) {
                Text(Format.time(date))
                    .font(.system(size: 70 * s, weight: .thin, design: .rounded).monospacedDigit())
                Text(Format.date(date))
                    .font(.system(size: 15 * s, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 8 * s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// 顶部：时间和日期居中放在上方，适合人物站在下半屏的画面。
struct TopClock: View {
    let date: Date

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 208
            VStack(spacing: -2 * s) {
                Text(Format.time(date))
                    .font(.system(size: 48 * s, weight: .bold, design: .rounded).monospacedDigit())
                Text(Format.date(date))
                    .font(.system(size: 14 * s, weight: .semibold, design: .rounded))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4 * s, y: 1 * s)
            .frame(width: geo.size.width)
            .padding(.top, 16 * s)
        }
    }
}

/// 右侧四行：时、分、日期、星期。仿 P3R 主菜单：粗斜体、水色半透明、深蓝错位影子，
/// 行距小于字高互相压叠，倾角正负交替。版式参数来自 P3R-LiveClock（MIT），
/// 是给右侧偏暗的画面准备的；换了视频压到主体的话，调 top、right 和字号。
struct MenuClock: View {
    let date: Date

    private static let big: CGFloat = 57, small: CGFloat = 26
    private static let top: CGFloat = 100      // 第一行中心离屏幕顶端的距离
    private static let right: CGFloat = 203    // 每行右缘的位置（屏幕宽 208）
    private static let cyan = Color(red: 0x8B / 255, green: 0xE8 / 255, blue: 0xF5 / 255).opacity(0.82)
    private static let shadow = Color(red: 0x16 / 255, green: 0x3F / 255, blue: 0xB0 / 255).opacity(0.85)

    private struct Row: Identifiable {
        let id: Int
        let text: String
        let size: CGFloat
        let degrees: Double    // 逆时针为正
        let kerning: CGFloat
        let inset: CGFloat     // 右缘再往里缩多少
        let y: CGFloat         // 行中心
    }

    private var rows: [Row] {
        let hm = Format.time(date).split(separator: ":").map(String.init)
        let big = Self.big, small = Self.small
        let minuteY = Self.top + big * 0.55
        return [
            Row(id: 0, text: hm[0], size: big, degrees: 10, kerning: 0, inset: 2, y: Self.top),
            Row(id: 1, text: hm[1], size: big, degrees: -8, kerning: 0, inset: 0, y: minuteY),
            Row(id: 2, text: Self.dateFormatter.string(from: date), size: small, degrees: 8, kerning: 0.5, inset: 3,
                y: minuteY + big * 0.38 + small * 0.62),
            Row(id: 3, text: Self.weekdayFormatter.string(from: date).uppercased(), size: small, degrees: -7, kerning: 1, inset: 10,
                y: minuteY + big * 0.38 + small * 1.67),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / 208, sy = geo.size.height / 248, s = min(sx, sy)
            ForEach(rows) { row in
                let k = max(row.size / 60, 0.45)
                let font = Font.system(size: row.size * s, weight: .black).italic().monospacedDigit()
                let rightEdge = (Self.right - row.inset) * sx
                ZStack {
                    Text(row.text).font(font).kerning(row.kerning * s).foregroundStyle(Self.shadow)
                        .offset(x: 2.8 * k * s, y: 3.6 * k * s)
                    Text(row.text).font(font).kerning(row.kerning * s).foregroundStyle(Self.cyan)
                }
                .fixedSize()
                .rotationEffect(.degrees(-row.degrees))
                .frame(width: rightEdge, alignment: .trailing)
                .position(x: rightEdge / 2, y: row.y * sy)
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "M/d"; return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE"; return f
    }()
}
