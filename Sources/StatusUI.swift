import AppKit

@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let model: TimerModel
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let popoverController: PopoverController

    init(model: TimerModel) {
        self.model = model
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popoverController = PopoverController(model: model)
        super.init()

        if let button = item.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = popoverController
        popover.delegate = self
        popoverController.onSizeChange = { [weak self] size in
            self?.popover.contentSize = size
        }

        model.onChange = { [weak self] in
            self?.refresh()
        }
        refresh()
        popover.contentSize = popoverController.preferredSize
    }

    func refresh() {
        guard let button = item.button else { return }
        let image = Theme.statusIcon(yaos: model.currentHexagram.yaos)
        button.image = image
        button.title = " \(model.statusBarText)"
        popoverController.reload()
        OverlayController.shared.refresh()
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.contentSize = popoverController.preferredSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@MainActor
final class PopoverController: NSViewController {
    private let model: TimerModel
    private let root = PopoverView()
    var onSizeChange: ((NSSize) -> Void)?

    var preferredSize: NSSize { root.preferredSize }

    init(model: TimerModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        root.model = model
        root.onSizeChange = { [weak self] size in
            self?.onSizeChange?(size)
        }
        root.frame = NSRect(origin: .zero, size: NSSize(width: 360, height: 280))
        view = root
        root.buildIfNeeded()
    }

    func reload() {
        root.refresh()
    }
}

@MainActor
final class PopoverView: NSView {
    weak var model: TimerModel?
    var onSizeChange: ((NSSize) -> Void)?

    private let phaseLabel = NSTextField(labelWithString: "时行")
    private let timeLabel = NSTextField(labelWithString: "25:00")
    private let guaNameLabel = NSTextField(labelWithString: "乾　第一卦")
    private let judgmentLabel = NSTextField(wrappingLabelWithString: "元亨利贞。")
    private let hintLabel = NSTextField(labelWithString: "现在休息")
    private let progress = YaoProgress()
    private let pauseButton = NSButton(title: "且止", target: nil, action: nil)
    private let actionButton = NSButton(title: "入止", target: nil, action: nil)
    private let workValue = NSTextField(labelWithString: "25 分钟")
    private let restValue = NSTextField(labelWithString: "1 分钟")
    private let workStepper = NSStepper()
    private let restStepper = NSStepper()
    private let overlayBox = NSButton(checkboxWithTitle: "止时遮住屏幕", target: nil, action: nil)
    private let soundBox = NSButton(checkboxWithTitle: "钟声", target: nil, action: nil)
    private let loginBox = NSButton(checkboxWithTitle: "开机即行", target: nil, action: nil)
    private var settingsStack: NSStackView?
    private var prefsButton: NSButton?
    private var rootStack: NSStackView?
    private var prefsExpanded = false
    private var didBuild = false

    var preferredSize: NSSize {
        layoutSubtreeIfNeeded()
        let height = (rootStack?.fittingSize.height ?? 248) + 36
        return NSSize(width: 360, height: max(260, height))
    }

    override var isFlipped: Bool { true }

    func buildIfNeeded() {
        guard !didBuild else { return }
        didBuild = true
        wantsLayer = true
        layer?.backgroundColor = Theme.paper.cgColor

        phaseLabel.font = Theme.kaiti(size: 16)
        phaseLabel.textColor = Theme.cinnabar
        timeLabel.font = Theme.songti(size: 22, weight: .light)
        timeLabel.textColor = Theme.ink
        timeLabel.alignment = .right
        guaNameLabel.font = Theme.kaiti(size: 18)
        guaNameLabel.textColor = Theme.ink
        guaNameLabel.alignment = .left
        judgmentLabel.font = Theme.kaiti(size: 13)
        judgmentLabel.textColor = Theme.muted
        judgmentLabel.alignment = .left
        judgmentLabel.maximumNumberOfLines = 5
        judgmentLabel.lineBreakMode = .byTruncatingTail
        judgmentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hintLabel.font = Theme.kaiti(size: 11)
        hintLabel.textColor = Theme.muted
        hintLabel.alignment = .right

        styleFillButton(pauseButton, prominent: false)
        styleFillButton(actionButton, prominent: true)
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        actionButton.target = self
        actionButton.action = #selector(primaryAction)

        workStepper.minValue = 5
        workStepper.maxValue = 90
        workStepper.increment = 5
        workStepper.valueWraps = false
        workStepper.target = self
        workStepper.action = #selector(workChanged)

        restStepper.minValue = 1
        restStepper.maxValue = 15
        restStepper.increment = 1
        restStepper.valueWraps = false
        restStepper.target = self
        restStepper.action = #selector(restChanged)

        workValue.font = Theme.kaiti(size: 14)
        workValue.textColor = Theme.mineral
        restValue.font = Theme.kaiti(size: 14)
        restValue.textColor = Theme.mineral

        for box in [overlayBox, soundBox, loginBox] {
            box.font = Theme.kaiti(size: 14)
            box.target = self
        }
        overlayBox.action = #selector(toggleOverlay)
        soundBox.action = #selector(toggleSound)
        loginBox.action = #selector(toggleLogin)

        let topRow = NSStackView(views: [phaseLabel, NSView(), timeLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.distribution = .fill

        let textColumn = NSStackView(views: [guaNameLabel, judgmentLabel])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 6
        textColumn.setHuggingPriority(.defaultLow, for: .horizontal)

        let guaRow = NSStackView(views: [progress, textColumn])
        guaRow.orientation = .horizontal
        guaRow.alignment = .centerY
        guaRow.spacing = 16
        guaRow.distribution = .fill
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 84).isActive = true
        progress.heightAnchor.constraint(equalToConstant: 108).isActive = true

        let controls = NSStackView(views: [pauseButton, actionButton])
        controls.orientation = .horizontal
        controls.distribution = .fillEqually
        controls.spacing = 8
        pauseButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        actionButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let workRow = labeledRow("行", value: workValue, stepper: workStepper)
        let restRow = labeledRow("止", value: restValue, stepper: restStepper)
        let settings = NSStackView(views: [workRow, restRow, overlayBox, soundBox, loginBox])
        settings.orientation = .vertical
        settings.alignment = .leading
        settings.spacing = 10
        settings.isHidden = true
        settingsStack = settings

        let prefs = linkButton("偏好", #selector(togglePrefs))
        prefsButton = prefs
        let restart = linkButton("重起", #selector(restartCycle))
        let quit = linkButton("退出", #selector(quitApp))
        let footer = NSStackView(views: [prefs, restart, NSView(), quit])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12

        let root = NSStackView(views: [topRow, guaRow, hairline(), controls, hintLabel, settings, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        rootStack = root

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            topRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            guaRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            controls.widthAnchor.constraint(equalTo: root.widthAnchor),
            hintLabel.widthAnchor.constraint(equalTo: root.widthAnchor),
            settings.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
            workRow.widthAnchor.constraint(equalTo: settings.widthAnchor),
            restRow.widthAnchor.constraint(equalTo: settings.widthAnchor),
            textColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])

        refresh()
    }

    func refresh() {
        guard let model, didBuild else { return }
        phaseLabel.stringValue = model.phaseTitle
        timeLabel.stringValue = model.format(model.remaining)
        guaNameLabel.stringValue = model.currentHexagram.heading
        judgmentLabel.stringValue = model.currentHexagram.judgment
        let textWidth = max(180, bounds.width - 56 - 84)
        judgmentLabel.preferredMaxLayoutWidth = textWidth
        progress.progress = 1
        progress.yaos = model.currentHexagram.yaos
        pauseButton.title = model.isPaused ? "再行" : "且止"
        actionButton.title = model.phase == .rest ? "仍行" : "入止"
        hintLabel.stringValue = model.phase == .rest ? "跳过这次" : "现在休息"
        styleFillButton(pauseButton, prominent: false)
        styleFillButton(actionButton, prominent: true)
        workStepper.integerValue = model.workMinutes
        restStepper.integerValue = model.restMinutes
        workValue.stringValue = "\(model.workMinutes) 分钟"
        restValue.stringValue = "\(model.restMinutes) 分钟"
        overlayBox.state = model.overlayEnabled ? .on : .off
        soundBox.state = model.soundEnabled ? .on : .off
        loginBox.state = model.launchAtLogin ? .on : .off
        prefsButton?.attributedTitle = NSAttributedString(
            string: prefsExpanded ? "收起" : "偏好",
            attributes: [
                .foregroundColor: Theme.muted,
                .font: Theme.kaiti(size: 13)
            ]
        )
    }

    private func styleFillButton(_ button: NSButton, prominent: Bool) {
        button.bezelStyle = .flexiblePush
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 0
        button.layer?.backgroundColor = (prominent ? Theme.cinnabar : Theme.chip).cgColor
        button.font = Theme.kaiti(size: 15)
        button.contentTintColor = prominent ? Theme.silk : Theme.ink
        let color = prominent ? Theme.silk : Theme.ink
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: color,
                .font: Theme.kaiti(size: 15)
            ]
        )
    }

    private func linkButton(_ title: String, _ selector: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: selector)
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = Theme.kaiti(size: 13)
        button.contentTintColor = Theme.muted
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: Theme.muted,
                .font: Theme.kaiti(size: 13)
            ]
        )
        return button
    }

    private func labeledRow(_ title: String, value: NSTextField, stepper: NSStepper) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = Theme.kaiti(size: 14)
        label.textColor = Theme.ink
        let row = NSStackView(views: [label, NSView(), value, stepper])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func hairline() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Theme.line.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    @objc private func togglePause() { model?.togglePause() }
    @objc private func primaryAction() {
        guard let model else { return }
        if model.phase == .rest {
            model.skipRest()
        } else {
            model.restNow()
        }
    }
    @objc private func togglePrefs() {
        prefsExpanded.toggle()
        settingsStack?.isHidden = !prefsExpanded
        needsLayout = true
        layoutSubtreeIfNeeded()
        onSizeChange?(preferredSize)
        refresh()
    }
    @objc private func workChanged() {
        model?.workMinutes = workStepper.integerValue
        model?.applyDurations()
    }
    @objc private func restChanged() {
        model?.restMinutes = restStepper.integerValue
        model?.applyDurations()
    }
    @objc private func toggleOverlay() {
        model?.overlayEnabled = overlayBox.state == .on
    }
    @objc private func toggleSound() {
        model?.soundEnabled = soundBox.state == .on
    }
    @objc private func toggleLogin() {
        model?.launchAtLogin = loginBox.state == .on
    }
    @objc private func restartCycle() { model?.restartCycle() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}

final class YaoProgress: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }
    var yaos: [Bool] = HexagramCatalog.all[0].yaos {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        YaoPainter.draw(
            in: bounds,
            yaos: yaos,
            progress: progress,
            yang: Theme.ink,
            dim: Theme.ink.withAlphaComponent(0.18)
        )
    }
}
