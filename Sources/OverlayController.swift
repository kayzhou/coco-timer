import AppKit

@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private var windows: [NSWindow] = []
    private var canvases: [RestCanvas] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
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
            canvas.autoresizingMask = [.width, .height]
            canvas.isPrimary = isPrimary
            canvas.remainingText = model.format(model.remaining)
            canvas.hexagram = model.currentHexagram
            canvas.onDefer = { [weak model] in
                model?.deferRest()
            }
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

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    OverlayController.shared.model?.skipRest()
                }
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    OverlayController.shared.model?.skipRest()
                }
            }
        }

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.relayoutIfNeeded()
                }
            }
        }

        refresh()
    }

    func hide(animated: Bool = true) {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
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
        let gua = model.currentHexagram
        for canvas in canvases {
            canvas.remainingText = text
            canvas.hexagram = gua
        }
    }

    private func relayoutIfNeeded() {
        guard isVisible, let model, model.phase == .rest, model.overlayEnabled else { return }
        show(model: model)
    }
}

final class RestCanvas: NSView {
    var remainingText = "1:00" {
        didSet {
            guard remainingText != oldValue else { return }
            needsDisplay = true
        }
    }
    var hexagram: IChingHexagram = HexagramCatalog.all[0] {
        didSet {
            guard hexagram != oldValue else { return }
            needsDisplay = true
        }
    }
    var isPrimary = false
    var onDefer: (() -> Void)?
    var onSkip: (() -> Void)?

    private var deferButton: NSButton?
    private var skipButton: NSButton?
    private var controlsY: CGFloat = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, isPrimary, deferButton == nil else { return }
        wantsLayer = true

        let deferBtn = NSButton(title: "再坐五分", target: self, action: #selector(deferRest))
        deferBtn.bezelStyle = .inline
        deferBtn.isBordered = false
        deferBtn.attributedTitle = NSAttributedString(
            string: "再坐五分",
            attributes: [
                .font: Theme.kaiti(size: 22),
                .foregroundColor: Theme.silk.withAlphaComponent(0.72)
            ]
        )
        addSubview(deferBtn)
        deferButton = deferBtn

        let skip = NSButton(title: "仍行", target: self, action: #selector(skip))
        skip.bezelStyle = .inline
        skip.isBordered = false
        skip.attributedTitle = NSAttributedString(
            string: "仍行",
            attributes: [
                .font: Theme.kaiti(size: 13),
                .foregroundColor: Theme.haze.withAlphaComponent(0.55)
            ]
        )
        addSubview(skip)
        skipButton = skip
    }

    override func layout() {
        super.layout()
        positionControls()
    }

    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(starting: Theme.xuan, ending: Theme.xuanDeep)
        gradient?.draw(in: bounds, angle: 270)

        let silk = Theme.silk.withAlphaComponent(0.88)

        guard isPrimary else {
            let guaWidth = min(bounds.width, bounds.height) * 0.14
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

        let noteW: CGFloat = min(520, bounds.width * 0.56)
        let guaW: CGFloat = 72
        let guaH: CGFloat = 80
        let gap: CGFloat = 18
        let textW = noteW - guaW - gap
        let noteX = (bounds.width - noteW) / 2
        let noteTop = bounds.height * 0.09

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.kaiti(size: 20),
            .foregroundColor: Theme.cinnabar.withAlphaComponent(0.7)
        ]
        let name = NSAttributedString(string: hexagram.heading, attributes: nameAttrs)
        let nameSize = name.boundingRect(
            with: NSSize(width: textW, height: 32),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let judgmentStyle = NSMutableParagraphStyle()
        judgmentStyle.alignment = .left
        judgmentStyle.lineSpacing = 4
        judgmentStyle.lineBreakMode = .byCharWrapping
        let judgmentAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.kaiti(size: 16),
            .foregroundColor: Theme.haze.withAlphaComponent(0.86),
            .paragraphStyle: judgmentStyle
        ]
        let judgment = NSAttributedString(string: hexagram.judgment, attributes: judgmentAttrs)
        let judgmentSize = judgment.boundingRect(
            with: NSSize(width: textW, height: 96),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let linesStyle = NSMutableParagraphStyle()
        linesStyle.alignment = .left
        linesStyle.lineSpacing = 5
        linesStyle.lineBreakMode = .byCharWrapping
        let linesAttrs: [NSAttributedString.Key: Any] = [
            .font: Theme.kaiti(size: 15),
            .foregroundColor: Theme.silk.withAlphaComponent(0.58),
            .paragraphStyle: linesStyle
        ]
        let lines = NSAttributedString(string: hexagram.yaoPassage, attributes: linesAttrs)
        let linesMaxH = min(160, bounds.height * 0.22)
        let linesSize = lines.boundingRect(
            with: NSSize(width: noteW, height: linesMaxH),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )

        let textH = ceil(nameSize.height) + 6 + ceil(judgmentSize.height)
        let rowH = max(guaH, textH)
        let guaRect = NSRect(x: noteX, y: noteTop + (rowH - guaH) / 2, width: guaW, height: guaH)
        YaoPainter.draw(
            in: guaRect,
            yaos: hexagram.yaos,
            progress: 1,
            yang: Theme.silk.withAlphaComponent(0.55),
            dim: Theme.silk.withAlphaComponent(0.18)
        )

        let textX = noteX + guaW + gap
        let textY = noteTop + (rowH - textH) / 2
        name.draw(in: NSRect(x: textX, y: textY, width: textW, height: ceil(nameSize.height)))
        judgment.draw(
            in: NSRect(
                x: textX,
                y: textY + ceil(nameSize.height) + 6,
                width: textW,
                height: ceil(judgmentSize.height)
            )
        )
        lines.draw(
            in: NSRect(
                x: noteX,
                y: noteTop + rowH + 14,
                width: noteW,
                height: min(linesMaxH, ceil(linesSize.height))
            )
        )

        let promptStyle = NSMutableParagraphStyle()
        promptStyle.alignment = .center
        let promptH: CGFloat = 56
        let timeH: CGFloat = 58
        let promptY = bounds.height * 0.52
        (Theme.standPrompt as NSString).draw(
            in: NSRect(x: 24, y: promptY, width: bounds.width - 48, height: promptH),
            withAttributes: [
                .font: Theme.kaiti(size: 40),
                .foregroundColor: Theme.silk,
                .paragraphStyle: promptStyle
            ]
        )

        let time = remainingText as NSString
        let timeStyle = NSMutableParagraphStyle()
        timeStyle.alignment = .center
        time.draw(
            in: NSRect(x: 0, y: promptY + promptH + 8, width: bounds.width, height: timeH),
            withAttributes: [
                .font: Theme.songti(size: 44, weight: .light),
                .foregroundColor: Theme.silk.withAlphaComponent(0.82),
                .paragraphStyle: timeStyle
            ]
        )

        controlsY = bounds.height - 96
        positionControls()
    }

    private func positionControls() {
        guard let deferButton, let skipButton else { return }
        deferButton.sizeToFit()
        skipButton.sizeToFit()
        deferButton.frame.origin = NSPoint(
            x: (bounds.width - deferButton.bounds.width) / 2,
            y: controlsY
        )
        skipButton.frame.origin = NSPoint(
            x: (bounds.width - skipButton.bounds.width) / 2,
            y: controlsY + deferButton.bounds.height + 6
        )
    }

    @objc private func deferRest() {
        onDefer?()
    }

    @objc private func skip() {
        onSkip?()
    }
}
