import AppKit
import Foundation
import ServiceManagement
import YixiPolicy

enum TimerPhase: Equatable {
    case work
    case rest
    case paused
}

@MainActor
final class TimerModel {
    private(set) var phase: TimerPhase = .work
    private(set) var remaining: TimeInterval = 25 * 60

    var workMinutes: Int {
        didSet {
            UserDefaults.standard.set(workMinutes, forKey: "workMinutes")
            emit()
        }
    }
    var restMinutes: Int {
        didSet {
            UserDefaults.standard.set(restMinutes, forKey: "restMinutes")
            emit()
        }
    }
    var overlayEnabled: Bool {
        didSet {
            UserDefaults.standard.set(overlayEnabled, forKey: "overlayEnabled")
            if !overlayEnabled {
                OverlayController.shared.hide()
            } else if phase == .rest {
                OverlayController.shared.show(model: self)
            }
            emit()
        }
    }
    var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled")
            emit()
        }
    }
    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            emit()
        }
    }

    var onChange: (() -> Void)?

    /// 连续跳过（仍行）次数；满 4 次后，下一次休息不可跳过。
    var consecutiveSkipCount: Int { skipPolicy.consecutiveSkipCount }
    /// 当前这次休息是否禁止跳过（已消耗连续跳过额度）。
    private(set) var isSkipBlocked = false

    private var skipPolicy: SkipPolicy
    private var endDate = Date()
    private var ticker: Timer?
    private var remainingWhenPaused: TimeInterval = 25 * 60
    private var phaseBeforePause: TimerPhase = .work
    private var runningBeforeSleep = false
    private var didBootstrap = false
    private var lastEmittedSecond = -1
    private var lastHexagramNumber = -1

    private static let consecutiveSkipKey = "consecutiveSkipCount"

    var workDuration: TimeInterval { TimeInterval(workMinutes * 60) }
    var restDuration: TimeInterval { TimeInterval(restMinutes * 60) }
    var isPaused: Bool { phase == .paused }

    /// 休息中且未被强制止息时，才可「仍行」。
    var canSkipRest: Bool { phase == .rest && !isSkipBlocked }

    /// 强制止息中：不可跳过、延期、暂停摘罩，也不可「重起」逃回工作。
    var isForcedRest: Bool { phase == .rest && isSkipBlocked }

    var canDeferRest: Bool { phase == .rest && !isSkipBlocked }
    var canPause: Bool { phase != .paused && !isForcedRest }
    var canRestartCycle: Bool { !isForcedRest }

    var statusBarText: String {
        format(remaining)
    }

    var currentHexagram: IChingHexagram {
        HexagramCatalog.at()
    }

    var phaseTitle: String {
        switch phase {
        case .work:
            return "时行"
        case .rest:
            return "时止"
        case .paused:
            return "静"
        }
    }

    var phaseHint: String {
        switch phase {
        case .work:
            return "时行则行 · \(restMinutes) 分钟后入止"
        case .rest:
            return isSkipBlocked ? Theme.skipBlockedHint : "坐不可久，起而步之。"
        case .paused:
            return "止而未迁"
        }
    }

    /// 全屏遮罩主提示文案。
    var restPrompt: String {
        isSkipBlocked ? Theme.skipBlockedHint : Theme.standPrompt
    }

    var hexagramYaos: [Bool] {
        currentHexagram.yaos
    }

    var progress: Double {
        let total: TimeInterval
        switch phase {
        case .rest:
            total = restDuration
        case .work:
            total = workDuration
        case .paused:
            total = phaseBeforePause == .rest ? restDuration : workDuration
        }
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    init() {
        let storedWork = UserDefaults.standard.object(forKey: "workMinutes") as? Int
        let storedRest = UserDefaults.standard.object(forKey: "restMinutes") as? Int
        workMinutes = Self.clamp(storedWork ?? 25, 5, 90)
        restMinutes = Self.clamp(storedRest ?? 1, 1, 15)
        overlayEnabled = UserDefaults.standard.object(forKey: "overlayEnabled") as? Bool ?? true
        soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        launchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? false
        let storedSkips = UserDefaults.standard.object(forKey: Self.consecutiveSkipKey) as? Int
        skipPolicy = SkipPolicy(stored: storedSkips ?? 0)
        if skipPolicy.consecutiveSkipCount != (storedSkips ?? 0) {
            persistConsecutiveSkipCount()
        }
        remaining = TimeInterval(workMinutes * 60)
        remainingWhenPaused = remaining
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        NotificationService.request()
        syncLaunchAtLoginFromSystem()
        observeSleep()
        enterWork(playSound: false, notify: false)
        startTicking()
    }

    func togglePause() {
        if phase == .paused {
            resume()
        } else {
            pause()
        }
    }

    func pause() {
        guard phase != .paused else { return }
        // 强制止息时禁止暂停，避免摘掉全屏遮罩或长期停在暂停以回避止息。
        guard !isForcedRest else { return }
        phaseBeforePause = phase
        remainingWhenPaused = max(0, endDate.timeIntervalSinceNow)
        remaining = remainingWhenPaused
        ticker?.invalidate()
        ticker = nil
        if phase == .rest {
            OverlayController.shared.hide()
        }
        phase = .paused
        emit()
    }

    func resume() {
        guard phase == .paused else { return }
        remaining = remainingWhenPaused
        if remaining <= 0.5 {
            phase = phaseBeforePause
            completePhase()
            return
        }
        phase = phaseBeforePause
        endDate = Date().addingTimeInterval(remaining)
        startTicking()
        if phase == .rest, overlayEnabled {
            OverlayController.shared.show(model: self)
        }
        emit()
    }

    func restNow() {
        // 仅从工作（或暂停于工作）进入休息，避免休息态误触重置倒计时。
        let fromWork = phase == .work || (phase == .paused && phaseBeforePause == .work)
        guard fromWork else { return }
        enterRest(playSound: true, notify: true)
        startTicking()
    }

    func skipRest() {
        guard phase == .rest else { return }
        guard canSkipRest else { return }
        skipPolicy.recordSkip()
        persistConsecutiveSkipCount()
        enterWork(playSound: true, notify: true)
        startTicking()
    }

    /// 取消这次休息，五分钟后再止。强制止息时不可延期。
    func deferRest() {
        guard canDeferRest else { return }
        OverlayController.shared.hide()
        phase = .work
        remaining = 5 * 60
        endDate = Date().addingTimeInterval(remaining)
        remainingWhenPaused = remaining
        startTicking()
        emit()
    }

    func restartCycle() {
        guard canRestartCycle else { return }
        enterWork(playSound: false, notify: false)
        startTicking()
    }

    func applyWorkDuration() {
        workMinutes = Self.clamp(workMinutes, 5, 90)
        let active = phase == .paused ? phaseBeforePause : phase
        if active == .work {
            rebindRemaining(to: workDuration)
        }
        emit()
    }

    func applyRestDuration() {
        restMinutes = Self.clamp(restMinutes, 1, 15)
        let active = phase == .paused ? phaseBeforePause : phase
        if active == .rest {
            rebindRemaining(to: restDuration)
        }
        emit()
    }

    /// 兼容旧调用：同时钳制两项；仅重绑当前相位对应的时长。
    func applyDurations() {
        applyWorkDuration()
        applyRestDuration()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard enabled != launchAtLogin else { return }
        if Self.applyLaunchAtLogin(enabled) {
            launchAtLogin = enabled
        } else {
            NSLog("含章可贞：开机启动设置失败，已保持原状态。")
            emit()
        }
    }

    /// 用 SMAppService 实际状态校准面板开关。
    func syncLaunchAtLoginFromSystem() {
        let systemEnabled = SMAppService.mainApp.status == .enabled
        guard launchAtLogin != systemEnabled else { return }
        launchAtLogin = systemEnabled
    }

    func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func rebindRemaining(to duration: TimeInterval) {
        remaining = duration
        remainingWhenPaused = duration
        if phase != .paused {
            endDate = Date().addingTimeInterval(duration)
        }
    }

    private func startTicking() {
        ticker?.invalidate()
        // 只注册到 common mode，避免 default + common 双挂接的歧义。
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard phase == .work || phase == .rest else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0.05 {
            completePhase()
            return
        }
        let second = Int(remaining.rounded())
        let gua = currentHexagram.number
        if second != lastEmittedSecond || gua != lastHexagramNumber {
            lastEmittedSecond = second
            lastHexagramNumber = gua
            emit()
        }
    }

    private func completePhase() {
        if phase == .work {
            enterRest(playSound: true, notify: true)
        } else {
            // 正常完成休息（含强制止息）后清零连续跳过，恢复可「仍行」。
            resetConsecutiveSkips()
            isSkipBlocked = false
            enterWork(playSound: true, notify: true)
        }
    }

    private func enterWork(playSound: Bool, notify: Bool) {
        OverlayController.shared.hide()
        phase = .work
        remaining = workDuration
        endDate = Date().addingTimeInterval(remaining)
        remainingWhenPaused = remaining
        if playSound, soundEnabled {
            SoundPlayer.playWorkStart()
        }
        if notify {
            NotificationService.notify(
                title: "乾 · 时行则行",
                body: "可以继续了。下一止在 \(workMinutes) 分钟后。",
                soundEnabled: soundEnabled
            )
        }
        emit()
    }

    private func enterRest(playSound: Bool, notify: Bool) {
        // 连续仍行满四次后，本次休息不可跳过；额度在休息正常结束时消耗清零。
        isSkipBlocked = skipPolicy.isSkipBlocked
        phase = .rest
        remaining = restDuration
        endDate = Date().addingTimeInterval(remaining)
        remainingWhenPaused = remaining
        if overlayEnabled {
            OverlayController.shared.show(model: self)
        }
        if playSound, soundEnabled {
            SoundPlayer.playRestStart()
        }
        if notify {
            NotificationService.notify(
                title: "艮 · 时止则止",
                body: isSkipBlocked ? Theme.skipBlockedHint : Theme.standPrompt,
                soundEnabled: soundEnabled
            )
        }
        emit()
    }

    private func resetConsecutiveSkips() {
        guard skipPolicy.consecutiveSkipCount != 0 else { return }
        skipPolicy.reset()
        persistConsecutiveSkipCount()
    }

    private func persistConsecutiveSkipCount() {
        UserDefaults.standard.set(skipPolicy.consecutiveSkipCount, forKey: Self.consecutiveSkipKey)
    }

    private func observeSleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            // queue 已是 main：同步处理，避免与 tick 交错。
            MainActor.assumeIsolated {
                self?.handleSleep()
            }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWake()
            }
        }
    }

    private func handleSleep() {
        guard phase == .work || phase == .rest else {
            runningBeforeSleep = false
            return
        }
        runningBeforeSleep = true
        remainingWhenPaused = max(0, endDate.timeIntervalSinceNow)
        remaining = remainingWhenPaused
        ticker?.invalidate()
        ticker = nil
        emit()
    }

    private func handleWake() {
        guard runningBeforeSleep else { return }
        runningBeforeSleep = false
        remaining = remainingWhenPaused
        endDate = Date().addingTimeInterval(remaining)
        startTicking()
        // 睡眠期间屏幕配置可能变化；若在休息且应显示遮罩却不可见，重建。
        if phase == .rest, overlayEnabled, !OverlayController.shared.isVisible {
            OverlayController.shared.show(model: self)
        } else if phase == .rest, overlayEnabled {
            OverlayController.shared.relayoutIfNeeded()
        }
        emit()
    }

    private func emit() {
        lastEmittedSecond = Int(remaining.rounded())
        lastHexagramNumber = currentHexagram.number
        onChange?()
    }

    private static func clamp(_ value: Int, _ minValue: Int, _ maxValue: Int) -> Int {
        min(maxValue, max(minValue, value))
    }

    @discardableResult
    private static func applyLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("含章可贞：开机启动设置失败：\(error.localizedDescription)")
            return false
        }
    }
}
