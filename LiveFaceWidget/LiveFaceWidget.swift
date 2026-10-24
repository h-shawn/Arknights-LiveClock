import SwiftUI
import WidgetKit

/// 表盘上的快捷入口：在系统表盘的复杂功能里放一个明日方舟的游戏图标，写着 Arknights LiveFace，点一下打开 LiveFace。
/// 内容不会变，不用刷新。
@main
struct LiveFaceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "liveface", provider: Provider()) { _ in
            ComplicationView()
        }
        .configurationDisplayName(ComplicationView.title)
        .description("Tap to open LiveFace")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

/// 只有一条内容，永不刷新
struct Provider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

struct ComplicationView: View {
    static let title = "Arknights LiveFace"

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner:
                icon
                    .widgetLabel(Self.title)
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    icon
                    Text(Self.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Text(Self.title)
            default:
                icon
            }
        }
        // 放在智能叠放里时的底色；表盘上的复杂功能不画它
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0x1A / 255, green: 0x1F / 255, blue: 0x2B / 255),
                                    Color(red: 0x05 / 255, green: 0x07 / 255, blue: 0x0A / 255)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// 明日方舟的游戏图标（和 App 图标是同一张），裁成圆形。图片由 scripts/make_complication_icons.py 生成：
    /// - 复杂功能里的图片像素不能比它占的地方大，大了系统就不画、只留灰色占位，所以按实际大小挑一张不超过的
    /// - 单色表盘只按透明度画图，彩色原图会变成实心圆，所以那时用把明暗转成透明度的黑白图
    private var icon: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let size = [280, 136, 88].first { CGFloat($0) <= side * displayScale } ?? 64
            Image(renderingMode == .fullColor ? "arknights-\(size)" : "arknights-mono-\(size)")
                .resizable()
                .frame(width: side, height: side)
                .clipShape(Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
