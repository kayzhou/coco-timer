import AppKit
import Foundation
import ServiceManagement

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
            Self.setLaunchAtLogin(launchAtLogin)
            emit()
        }
    }

    var onChange: (() -> Void)?

    private var endDate = Date()
    private var ticker: Timer?
    private var remainingWhenPaused: TimeInterval = 25 * 60
    private var phaseBeforePause: TimerPhase = .work
    private var runningBeforeSleep = false
    private var didBootstrap = false
    private var lastEmittedSecond = -1
    private var lastHexagramNumber = -1

    var workDuration: TimeInterval { TimeInterval(workMinutes * 60) }
    var restDuration: TimeInterval { TimeInterval(restMinutes * 60) }
    var isPaused: Bool { phase == .paused }

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
            return "坐不可久，起而步之。"
        case .paused:
            return "止而未迁"
        }
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
        remaining = TimeInterval(workMinutes * 60)
        remainingWhenPaused = remaining
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        NotificationService.request()
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
        enterRest(playSound: true, notify: true)
        startTicking()
    }

    func skipRest() {
        enterWork(playSound: true, notify: true)
        startTicking()
    }

    /// 取消这次休息，五分钟后再止。
    func deferRest() {
        OverlayController.shared.hide()
        phase = .work
        remaining = 5 * 60
        endDate = Date().addingTimeInterval(remaining)
        remainingWhenPaused = remaining
        startTicking()
        emit()
    }

    func restartCycle() {
        enterWork(playSound: false, notify: false)
        startTicking()
    }

    func applyDurations() {
        workMinutes = Self.clamp(workMinutes, 5, 90)
        restMinutes = Self.clamp(restMinutes, 1, 15)
        emit()
    }

    func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
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
                body: "可以继续了。下一止在 \(workMinutes) 分钟后。"
            )
        }
        emit()
    }

    private func enterRest(playSound: Bool, notify: Bool) {
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
                title: "时止则止",
                body: Theme.standPrompt
            )
        }
        emit()
    }

    private func observeSleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handleSleep()
            }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
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

    private static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("含章可贞：开机启动设置失败：\(error.localizedDescription)")
        }
    }
}
