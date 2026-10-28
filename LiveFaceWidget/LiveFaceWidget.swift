import SwiftUI
import WidgetKit

/// 表盘上的复杂功能：当前干员的头像，加上另一座城市的时间。
/// 点一下打开 LiveFace。城市在 App 的设置页里选（空白处双击打开）。
@main
struct LiveFaceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "liveface", provider: Provider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("LiveFace")
        .description("干员头像加一座城市的时间，点一下打开 LiveFace")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct Entry: TimelineEntry {
    let date: Date          // 这一分钟
    let shifted: Date       // 换算成本地时区之后、画出来正好是那座城市的时间
    let city: String
    let avatar: URL?        // 当前干员的头像，按复杂功能的大小挑一张
    let monoAvatar: URL?
    var rings: ActivityRings?   // 今天的运动情况，没授权就是 nil
}

/// 世界时钟每分钟要变一次。复杂功能的刷新次数有限，所以一次给一小时的条目，
/// 一小时后再要下一批——这样一天只醒二十来次。
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { entry(at: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            // 运动圆环一小时读一次：这一批条目共用同一份数据，打开 App 时也会刷新一次
            let rings = await ActivityRings.today()
            let minute = Calendar.current.date(bySetting: .second, value: 0, of: .now) ?? .now
            let entries = (0..<60).compactMap { i in
                Calendar.current.date(byAdding: .minute, value: i, to: minute).map {
                    var e = entry(at: $0); e.rings = rings; return e
                }
            }
            completion(Timeline(entries: entries, policy: .after(minute.addingTimeInterval(60 * 60))))
        }
    }

    private func entry(at date: Date) -> Entry {
        let city = PetAvatars.city
        let target = TimeZone(identifier: city.timeZone) ?? .current
        // SwiftUI 只会按本地时区画时间，所以把时刻整体挪一下，画出来就是那座城市的钟点
        let shift = TimeInterval(target.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date))
        return Entry(date: date, shifted: date.addingTimeInterval(shift), city: city.name,
                     avatar: PetAvatars.current(mono: false), monoAvatar: PetAvatars.current(mono: true))
    }
}

/// 头像放在 App 包里的 Frames/pets/<干员>/avatar-*.png（scripts/make_pet_avatars.py 生成）。
/// 扩展在 LiveFace.app/PlugIns/ 里，往上两层就是 App 自己的包。
enum PetAvatars {
    private static let shared = UserDefaults(suiteName: "group.com.shawn.liveface")

    static var city: (name: String, timeZone: String) {
        let id = shared?.string(forKey: "cityTimeZone") ?? "Asia/Shanghai"
        return (Self.names[id] ?? "Beijing", id)
    }

    /// 表盘上的字一律用英文，和 Prefs.cities 里的 english 一一对应
    private static let names = [
        "Asia/Shanghai": "Beijing", "Asia/Hong_Kong": "Hong Kong", "Asia/Tokyo": "Tokyo",
        "Asia/Seoul": "Seoul", "Asia/Singapore": "Singapore", "Asia/Dubai": "Dubai",
        "Europe/London": "London", "Europe/Paris": "Paris", "America/New_York": "New York",
        "America/Chicago": "Chicago", "America/Los_Angeles": "Los Angeles",
        "America/Vancouver": "Vancouver", "Australia/Sydney": "Sydney",
    ]

    private static let folders: [URL] = {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let pets = app.appendingPathComponent("Frames/pets")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: pets.path)) ?? [])
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return names.map { pets.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("pet.json").path) }
    }()

    /// 当前这位干员的头像目录；哪个尺寸等画的时候才知道，这里只给文件夹
    static func current(mono: Bool) -> URL? {
        guard !folders.isEmpty else { return nil }
        let i = shared?.integer(forKey: "petIndex") ?? 0
        return folders[((i % folders.count) + folders.count) % folders.count]
    }

    /// 复杂功能里的图不能比它占的地方大，大了系统就不画，所以按实际大小挑一张。
    /// 放了 avatar-local-* 就优先用它（自己换的图，不入库）
    static func file(in folder: URL, mono: Bool, side: CGFloat) -> URL? {
        let size = [280, 136, 88].first { CGFloat($0) <= side } ?? 64
        let suffix = mono ? "mono-\(size)" : "\(size)"
        for prefix in ["avatar-local", "avatar"] {
            let url = folder.appendingPathComponent("\(prefix)-\(suffix).png")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

struct ComplicationView: View {
    let entry: Entry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner:
                avatar.widgetLabel("\(entry.city) \(time)")
            case .accessoryRectangular:
                // 尽量把槽位填满：长条槽大约 62 点高，留太多空白看着像没对齐
                HStack(spacing: 5) {
                    let side: CGFloat = entry.rings == nil ? 62 : 58
                    avatar.frame(width: side, height: side)
                    VStack(alignment: .leading, spacing: -3) {
                        Text(entry.city)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(entry.shifted, style: .time)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let rings = entry.rings {
                        RingsView(rings: rings).frame(width: 46, height: 46)
                    }
                }
                .frame(maxHeight: .infinity)
            case .accessoryInline:
                Text("\(entry.city) \(time)")
            default:
                avatar.widgetLabel("\(entry.city) \(time)")
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0x1A / 255, green: 0x1F / 255, blue: 0x2B / 255),
                                    Color(red: 0x05 / 255, green: 0x07 / 255, blue: 0x0A / 255)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// 弯曲的小标签和纯文字槽位里没法用 Text(style:)，只能自己格式化
    private var time: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone.current   // shifted 已经换算过了
        return f.string(from: entry.shifted)
    }

    /// 单色表盘只按透明度画图，彩色原图会糊成一个实心圆，所以那时换黑白那张
    private var avatar: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let folder = renderingMode == .fullColor ? entry.avatar : entry.monoAvatar
            let url = folder.flatMap { PetAvatars.file(in: $0, mono: renderingMode != .fullColor,
                                                       side: side * displayScale) }
            Group {
                if let url, let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable()
                } else {
                    Image(systemName: "person.crop.circle").resizable()
                }
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 三个同心圆环，照着「体能训练」的配色画。
/// 画出来的形状（不是图片）在单色表盘上会被系统整体染色，不会像图片那样只剩透明度
struct RingsView: View {
    let rings: ActivityRings

    private static let colors = [Color(red: 0.98, green: 0.07, blue: 0.31),   // 活动
                                 Color(red: 0.57, green: 0.91, blue: 0.16),   // 锻炼
                                 Color(red: 0.00, green: 0.83, blue: 0.91)]   // 站立

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // 三条环加两道缝要塞进半径里：线宽取得太大，最里面那条半径会变成负数，整条就不画了
            let width = side * 0.115
            let gap = side * 0.02
            ZStack {
                ForEach(Array([rings.move, rings.exercise, rings.stand].enumerated()), id: \.offset) { i, value in
                    let inset = width / 2 + CGFloat(i) * (width + gap)
                    Circle()
                        .inset(by: inset)
                        .stroke(Self.colors[i].opacity(0.28), lineWidth: width)
                    Circle()
                        .inset(by: inset)
                        .trim(from: 0, to: min(max(value, 0), 1))
                        .stroke(Self.colors[i], style: StrokeStyle(lineWidth: width, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: side, height: side)
        }
    }
}
