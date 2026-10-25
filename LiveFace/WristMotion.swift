import CoreMotion
import WatchKit

/// 手腕的动作：左右歪手腕时重力在屏幕左右方向的分量，和猛甩一下的加速度。
/// 只在亮着屏、App 在前台时开传感器（FaceView 负责开关）。模拟器没有运动传感器，不会有反应。
final class WristMotion {
    static let shared = WristMotion()

    /// 加速度超过这个（g）算甩了一下；举起手腕看表、走路都到不了。
    /// 设置页里的「手腕灵敏度」会乘上去
    static var shakeThreshold: CGFloat { 1.6 * Prefs.motionScale }

    /// 屏幕左右方向的倾斜：-1…1，正数是右边低。平滑过，手轻轻抖不算
    private(set) var tilt: CGFloat = 0
    /// 甩了一下：甩的方向（屏幕坐标，向右、向下为正，单位 g）和力度（g，含垂直屏幕的分量）
    var onShake: ((CGVector, CGFloat) -> Void)?

    private let manager = CMMotionManager()
    private var peak = CGVector.zero      // 这一下甩的过程中加速度最大的那一刻
    private var peakStrength: CGFloat = 0
    private var lastShake = Date.distantPast

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 50
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // 表冠在左边时表是倒过来戴的，屏幕的左右上下和传感器正好相反
            let flip = WKInterfaceDevice.current().crownOrientation == .left ? -1.0 : 1.0
            let a = motion.userAcceleration
            self.update(gravityX: CGFloat(motion.gravity.x * flip),
                        acceleration: CGVector(dx: a.x * flip, dy: -a.y * flip), depth: CGFloat(a.z), at: Date())
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        tilt = 0
        peakStrength = 0
    }

    /// 每个传感器样本：倾斜做低通平滑；加速度冲过门槛再落回来算甩了一下，力度取这个过程中的最大值
    private func update(gravityX: CGFloat, acceleration a: CGVector, depth: CGFloat, at date: Date) {
        tilt += (gravityX - tilt) * 0.15
        let strength = (a.dx * a.dx + a.dy * a.dy + depth * depth).squareRoot()
        if strength > Self.shakeThreshold {
            if strength > peakStrength {
                peak = a
                peakStrength = strength
            }
        } else if peakStrength > 0 {
            // 来回甩一下会冲过门槛两次，隔得太近的只算一次
            if date.timeIntervalSince(lastShake) > 0.4 {
                lastShake = date
                onShake?(peak, peakStrength)
            }
            peakStrength = 0
        }
    }
}
