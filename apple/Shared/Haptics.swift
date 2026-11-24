import Foundation
#if os(iOS)
import CoreHaptics
#endif

/// 全局触感语义与花样波形（高起步、强辨识、物理质感）：
/// 起步强度 >= 0.55，配合锐度(sharpness)与多脉冲/连续事件形成鲜明手感差异。
enum HapticIntent: Sendable {
    /// 精密滚轮咔哒：相册勾选/滑选、滑动条刻度、快捷天数、开关
    case selection
    /// 磁吸落位双敲：切换目标设备（嗒-咔）
    case deviceSwitch
    /// 清脆机械按键：所有普通点击、按钮、图标、列表预览
    case tap
    /// 抽屉上扬弹开：展开文字输入框、展开自定义端口、打开相册/设置页
    case expand
    /// 轻柔下沉合拢：收起文字输入框、收起折叠项、关闭弹窗、取消选中
    case collapse
    /// 拉弦释放回弹：下拉刷新触发瞬间（连续微张力 + 清脆释放）
    case pullRefresh
    /// 图钉扎实按入：右滑/菜单置顶与取消置顶（咚-咔）
    case pin
    /// 扎实主操作键：快速相册一步发送、重发、接收、连接设备
    case action
    /// 双拍确认发射：点击发送发起传输、保存连接设置、确认清缓存
    case confirm
    /// 上扬三连凯旋：发送成功、下拉刷新完成、复制成功、清理完成（哒-哒-叮）
    case complete
    /// 厚重双敲警示：删除记录、移除附件、立即清理、拒绝接收、取消传输
    case warning
    /// 急促三连报错：发送失败、读取失败、操作错误（咚-咚-咚）
    case failure
}

/// 独立队列上的 Core Haptics 触感引擎，不阻塞主线程；离前台自动暂停，不在后台补播。
final class Haptics {
    static let shared = Haptics()

    #if os(iOS)
    private let queue = DispatchQueue(label: "com.chongyang.quicktransfer.haptics")
    private var engine: CHHapticEngine?
    private var players: [Int: CHHapticPatternPlayer] = [:]
    private var nextID = 0
    private var active = true
    #endif

    private init() {}

    func prepare() {
        #if os(iOS)
        queue.async { [weak self] in
            guard let self else { return }
            self.active = true
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
            try? self.ensureEngineStarted()
        }
        #endif
    }

    func suspend() {
        #if os(iOS)
        queue.async { [weak self] in
            guard let self else { return }
            self.active = false
            for player in self.players.values {
                try? player.stop(atTime: CHHapticTimeImmediate)
            }
            self.players.removeAll()
        }
        #endif
    }

    func play(_ intent: HapticIntent) {
        #if os(iOS)
        queue.async { [weak self] in
            guard let self, self.active else { return }
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
            do {
                try self.ensureEngineStarted()
                guard let engine = self.engine else { return }
                let (pattern, cleanupDelay) = try Self.makePattern(for: intent)
                let player = try engine.makePlayer(with: pattern)
                self.nextID &+= 1
                let id = self.nextID
                self.players[id] = player
                try player.start(atTime: CHHapticTimeImmediate)
                self.queue.asyncAfter(deadline: .now() + cleanupDelay) { [weak self, weak player] in
                    guard let self, let player, self.players[id] === player else { return }
                    self.players.removeValue(forKey: id)
                }
            } catch {
                // 触觉失败不影响业务流程
            }
        }
        #endif
    }

    #if os(iOS)
    private func ensureEngineStarted() throws {
        if engine == nil {
            let next = try CHHapticEngine()
            next.playsHapticsOnly = true
            next.isAutoShutdownEnabled = true
            next.resetHandler = { [weak self] in
                self?.queue.async {
                    self?.engine = nil
                    self?.players.removeAll()
                }
            }
            engine = next
        }
        try engine?.start()
    }

    private static func transient(time: Double, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private static func continuous(time: Double, duration: Double, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private static func makePattern(for intent: HapticIntent) throws -> (CHHapticPattern, Double) {
        let events: [CHHapticEvent]
        let delay: Double

        switch intent {
        case .selection:
            events = [
                transient(time: 0, intensity: 0.58, sharpness: 0.88)
            ]
            delay = 0.25

        case .deviceSwitch:
            events = [
                transient(time: 0, intensity: 0.56, sharpness: 0.68),
                transient(time: 0.048, intensity: 0.80, sharpness: 0.92),
            ]
            delay = 0.3

        case .tap:
            events = [
                transient(time: 0, intensity: 0.68, sharpness: 0.80)
            ]
            delay = 0.25

        case .expand:
            events = [
                transient(time: 0, intensity: 0.54, sharpness: 0.45),
                transient(time: 0.055, intensity: 0.74, sharpness: 0.80),
            ]
            delay = 0.3

        case .collapse:
            events = [
                transient(time: 0, intensity: 0.68, sharpness: 0.75),
                transient(time: 0.052, intensity: 0.50, sharpness: 0.40),
            ]
            delay = 0.3

        case .pullRefresh:
            // 单击高锐度清脆触发，干脆利落不拖尾
            events = [
                transient(time: 0, intensity: 0.86, sharpness: 0.95)
            ]
            delay = 0.25

        case .pin:
            events = [
                transient(time: 0, intensity: 0.80, sharpness: 0.35),
                transient(time: 0.068, intensity: 0.88, sharpness: 0.92),
            ]
            delay = 0.32

        case .action:
            events = [
                transient(time: 0, intensity: 0.84, sharpness: 0.72)
            ]
            delay = 0.28

        case .confirm:
            events = [
                transient(time: 0, intensity: 0.88, sharpness: 0.76),
                transient(time: 0.085, intensity: 0.68, sharpness: 0.55),
            ]
            delay = 0.35

        case .complete:
            events = [
                transient(time: 0, intensity: 0.60, sharpness: 0.65),
                transient(time: 0.065, intensity: 0.78, sharpness: 0.82),
                transient(time: 0.145, intensity: 0.96, sharpness: 0.92),
            ]
            delay = 0.45

        case .warning:
            events = [
                transient(time: 0, intensity: 0.92, sharpness: 0.42),
                transient(time: 0.095, intensity: 0.84, sharpness: 0.34),
            ]
            delay = 0.38

        case .failure:
            events = [
                transient(time: 0, intensity: 1.0, sharpness: 0.38),
                transient(time: 0.075, intensity: 0.95, sharpness: 0.30),
                transient(time: 0.155, intensity: 1.0, sharpness: 0.24),
            ]
            delay = 0.48
        }

        return (try CHHapticPattern(events: events, parameters: []), delay)
    }
    #endif
}
