import AppKit

@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private var windows: [NSWindow] = []
    private var canvases: [RestCanvas] = []
    private var eventMonitor: Any?
    private weak var model: TimerModel?
    private var savedPresentation: NSApplication.PresentationOptions = []

    var isVisible: Bool { !windows.isEmpty }

    func show(model: TimerModel) {
        self.model = model
        hide(animated: false)
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let mainScreen = NSScreen.main ?? screens[0]

        savedPresentation = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideMenuBar, .hideDock]

        for screen in screens {
            let isPrimary = screen == mainScreen
            let frame = screen.frame
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.setFrame(frame, display: true)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = false
            panel.animationBehavior = .utilityWindow
            panel.alphaValue = 0

            let canvas = RestCanvas(frame: NSRect(origin: .zero, size: frame.size))
            canvas.isPrimary = isPrimary
            canvas.remainingText = model.format(model.remaining)
            canvas.hexagram = model.currentHexagram
            canvas.onSkip = { [weak model] in
                model?.skipRest()
            }
            panel.contentView = canvas
            panel.orderFrontRegardless()
            windows.append(panel)
            canvases.append(canvas)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            for window in windows {
                window.animator().alphaValue = 1
            }
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    OverlayController.shared.model?.skipRest()
                }
                return nil
            }
            return event
        }

        refresh()
    }

    func hide(animated: Bool = true) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        NSApp.presentationOptions = savedPresentation

        let closing = windows
        windows = []
        canvases = []
        guard !closing.isEmpty else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                for window in closing {
                    window.animator().alphaValue = 0
                }
            } completionHandler: {
                Task { @MainActor in
                    for window in closing {
                        window.orderOut(nil)
                        window.close()
                    }
                }
            }
        } else {
            for window in closing {
                window.orderOut(nil)
                window.close()
            }
        }
    }

    func refresh() {
        guard let model else { return }
        let text = model.format(model.remaining)
        for canvas in canvases {
            canvas.remainingText = text
            canvas.hexagram = model.currentHexagram
        }
    }
}

final class RestCanvas: NSView {
    var remainingText = "1:00" {
        didSet { needsDisplay = true }
    }
    var hexagram: IChingHexagram = HexagramCatalog.all[0] {
        didSet { needsDisplay = true }
    }
    var isPrimary = false
    var onSkip: (() -> Void)?

    private var pulseTimer: Timer?
    private var skipButton: NSButton?
    private var skipHint: NSTextField?
    private var skipY: CGFloat = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            pulseTimer?.invalidate()
            pulseTimer = nil
            return
        }
        wantsLayer = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.needsDisplay = true
            }
        }
        if let pulseTimer {
            RunLoop.main.add(pulseTimer, forMode: .common)
        }
        if isPrimary, skipButton == nil {
            let button = NSButton(title: "仍行", target: self, action: #selector(skip))
            button.bezelStyle = .inline
            button.isBordered = false
            button.attributedTitle = NSAttributedString(
                string: "仍行",
                attributes: [
                    .font: Theme.kaiti(size: 22),
                    .foregroundColor: Theme.silk
                ]
            )
            addSubview(button)
            skipButton = button

            let hint = NSTextField(labelWithString: "跳过这次")
            hint.font = Theme.kaiti(size: 13)
            hint.textColor = Theme.haze
            hint.alignment = .center
            hint.isBezeled = false
            hint.drawsBackground = false
            addSubview(hint)
            skipHint = hint
        }
    }

    override func layout() {
        super.layout()
        positionSkipControls()
    }

    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(starting: Theme.xuan, ending: Theme.xuanDeep)
        gradient?.draw(in: bounds, angle: 270)

        let t = Date().timeIntervalSinceReferenceDate
        let pulse = (sin(t * .pi / 2.6) + 1) / 2
        let silk = Theme.silk.withAlphaComponent(0.78 + 0.18 * pulse)

        guard isPrimary else {
            let guaWidth = min(bounds.width, bounds.height) * 0.18
            let guaRect = NSRect(
                x: bounds.midX - guaWidth / 2,
                y: bounds.midY - guaWidth * 0.54,
                width: guaWidth,
                height: guaWidth * 1.08
            )
            YaoPainter.draw(
                in: guaRect,
                yaos: hexagram.yaos,
                progress: 1,
                yang: silk,
                dim: Theme.silk.withAlphaComponent(0.28)
            )
            return
        }

        let guaW: CGFloat = 168
        let guaH: CGFloat = 186
        let gap: CGFloat = 40
        let textW: CGFloat = min(420, max(240, bounds.width * 0.38))
        let blockW = guaW + gap + textW

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.kaiti(size: 28),
            .foregroundColor: Theme.cinnabar.withAlphaComponent(0.92)
        ]
        let name = NSAttributedString(string: hexagram.heading, attributes: nameAttrs)
        let nameSize = name.boundingRect(
            with: NSSize(width: textW, height: 40),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let judgmentStyle = NSMutableParagraphStyle()
        judgmentStyle.alignment = .left
        judgmentStyle.lineSpacing = 6
        let judgmentAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.kaiti(size: 17),
            .foregroundColor: Theme.haze,
            .paragraphStyle: judgmentStyle
        ]
        let judgment = NSAttributedString(string: hexagram.judgment, attributes: judgmentAttrs)
        let judgmentSize = judgment.boundingRect(
            with: NSSize(width: textW, height: 220),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let textH = ceil(nameSize.height) + 12 + ceil(judgmentSize.height)
        let rowH = max(guaH, textH)
        let promptH: CGFloat = 40
        let timeH: CGFloat = 52
        let skipBlock: CGFloat = 72
        let blockH = rowH + 20 + promptH + 16 + timeH + skipBlock
        let originX = (bounds.width - blockW) / 2
        let originY = (bounds.height - blockH) / 2

        let guaRect = NSRect(x: originX, y: originY + (rowH - guaH) / 2, width: guaW, height: guaH)
        YaoPainter.draw(
            in: guaRect,
            yaos: hexagram.yaos,
            progress: 1,
            yang: silk,
            dim: Theme.silk.withAlphaComponent(0.28)
        )

        let textX = originX + guaW + gap
        let textY = originY + (rowH - textH) / 2
        name.draw(in: NSRect(x: textX, y: textY, width: textW, height: ceil(nameSize.height)))
        judgment.draw(
            in: NSRect(
                x: textX,
                y: textY + ceil(nameSize.height) + 12,
                width: textW,
                height: ceil(judgmentSize.height)
            )
        )

        let promptStyle = NSMutableParagraphStyle()
        promptStyle.alignment = .center
        let promptY = originY + rowH + 20
        (Theme.standPrompt as NSString).draw(
            in: NSRect(x: 0, y: promptY, width: bounds.width, height: promptH),
            withAttributes: [
                .font: Theme.kaiti(size: 24),
                .foregroundColor: Theme.silk,
                .paragraphStyle: promptStyle
            ]
        )

        let time = remainingText as NSString
        let timeStyle = NSMutableParagraphStyle()
        timeStyle.alignment = .center
        time.draw(
            in: NSRect(x: 0, y: promptY + promptH + 16, width: bounds.width, height: timeH),
            withAttributes: [
                .font: Theme.songti(size: 36, weight: .light),
                .foregroundColor: Theme.silk.withAlphaComponent(0.85),
                .paragraphStyle: timeStyle
            ]
        )

        skipY = promptY + promptH + 16 + timeH + 18
        positionSkipControls()
    }

    private func positionSkipControls() {
        guard let skipButton else { return }
        skipButton.sizeToFit()
        skipButton.frame.origin = NSPoint(
            x: (bounds.width - skipButton.bounds.width) / 2,
            y: skipY
        )
        if let skipHint {
            skipHint.sizeToFit()
            skipHint.frame.origin = NSPoint(
                x: (bounds.width - skipHint.bounds.width) / 2,
                y: skipY + skipButton.bounds.height + 4
            )
        }
    }

    @objc private func skip() {
        onSkip?()
    }
}
