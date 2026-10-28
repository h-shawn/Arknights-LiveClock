import HealthKit

/// 今天的三个运动圆环。表盘上的复杂功能要读，所以放在 App 和扩展都能用的地方。
/// 读 HealthKit 要先在 App 里请求授权，扩展跟着沾光。
struct ActivityRings {
    var move: Double = 0        // 已完成的比例，可能超过 1
    var exercise: Double = 0
    var stand: Double = 0

    static let store = HKHealthStore()

    /// 在 App 启动时调一次。系统只会弹一次框，之后是空操作
    static func requestAccess() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        store.requestAuthorization(toShare: [], read: [HKObjectType.activitySummaryType()]) { _, _ in }
    }

    static func today() async -> ActivityRings? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.calendar = Calendar.current
        let predicate = HKQuery.predicateForActivitySummary(with: components)
        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let s = summaries?.first else { return continuation.resume(returning: nil) }
                continuation.resume(returning: ActivityRings(
                    move: ratio(s.activeEnergyBurned, s.activeEnergyBurnedGoal, .kilocalorie()),
                    exercise: ratio(s.appleExerciseTime, s.appleExerciseTimeGoal, .minute()),
                    stand: ratio(s.appleStandHours, s.appleStandHoursGoal, .count())))
            }
            store.execute(query)
        }
    }

    private static func ratio(_ value: HKQuantity, _ goal: HKQuantity?, _ unit: HKUnit) -> Double {
        let target = goal?.doubleValue(for: unit) ?? 0
        guard target > 0 else { return 0 }
        return value.doubleValue(for: unit) / target
    }
}
