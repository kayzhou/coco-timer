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
            button.imagePosition = .noImage
            button.target = self
            button.action = #selector(togglePopover)
        }

        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = popoverController
        popover.delegate = self

        model.onChange = { [weak self] in
            self?.refresh()
        }
        refresh()
        popover.contentSize = popoverController.preferredSize
    }

    func refresh() {
        guard let button = item.button else { return }
        button.image = nil
        button.attributedTitle = Theme.statusBarTitle(phase: model.phase, time: model.statusBarText)
        if popover.isShown {
            popoverController.reload()
        }
        if OverlayController.shared.isVisible {
            OverlayController.shared.refresh()
        }
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popoverController.reload()
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

    var preferredSize: NSSize {
        loadViewIfNeeded()
        return root.preferredSize
    }

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
        view = root
        root.buildIfNeeded()
        root.frame = NSRect(origin: .zero, size: root.preferredSize)
        preferredContentSize = root.preferredSize
    }

    func reload() {
        root.refresh()
    }
}

@MainActor
final class PopoverView: NSView {
    weak var model: TimerModel?

    private let phaseLabel = NSTextField(labelWithString: "时行")
    private let timeLabel = NSTextField(labelWithString: "25:00")
    private let guaNameLabel = NSTextField(labelWithString: "乾　第一卦")
    private let judgmentLabel = NSTextField(wrappingLabelWithString: "元亨利贞。")
    private let linesLabel = NSTextField(wrappingLabelWithString: "初九　潜龙勿用。")
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
    private var didBuild = false

    static let panelSize = NSSize(width: 400, height: 548)
    private static let horizontalInset: CGFloat = 20
    private static let guaWidth: CGFloat = 88
    private static let guaHeight: CGFloat = 114
    private static let guaGap: CGFloat = 14
    private static let innerWidth: CGFloat = panelSize.width - horizontalInset * 2
    private static let judgmentWidth: CGFloat = innerWidth - guaWidth - guaGap

    var preferredSize: NSSize { Self.panelSize }

    override var isFlipped: Bool { true }

    func buildIfNeeded() {
        guard !didBuild else { return }
        didBuild = true
        wantsLayer = true
        layer?.backgroundColor = Theme.paper.cgColor

        phaseLabel.font = Theme.kaiti(size: 17)
        phaseLabel.textColor = Theme.cinnabar
        timeLabel.font = Theme.songti(size: 24, weight: .light)
        timeLabel.textColor = Theme.ink
        timeLabel.alignment = .right
        guaNameLabel.font = Theme.kaiti(size: 20)
        guaNameLabel.textColor = Theme.ink
        guaNameLabel.alignment = .left
        guaNameLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        configureWrapping(judgmentLabel, size: 16, color: Theme.muted, width: Self.judgmentWidth)
        configureWrapping(linesLabel, size: 15, color: Theme.ink, width: Self.innerWidth)

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
            box.font = Theme.kaiti(size: 13)
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
        guaRow.alignment = .top
        guaRow.spacing = Self.guaGap
        guaRow.distribution = .fill
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: Self.guaWidth).isActive = true
        progress.heightAnchor.constraint(equalToConstant: Self.guaHeight).isActive = true
        progress.setContentHuggingPriority(.required, for: .vertical)
        progress.setContentCompressionResistancePriority(.required, for: .vertical)

        let linesScroll = NSScrollView()
        linesScroll.drawsBackground = false
        linesScroll.hasVerticalScroller = true
        linesScroll.autohidesScrollers = true
        linesScroll.borderType = .noBorder
        linesScroll.scrollerStyle = .overlay
        linesScroll.documentView = linesLabel
        linesScroll.translatesAutoresizingMaskIntoConstraints = false
        linesLabel.translatesAutoresizingMaskIntoConstraints = false

        let controls = NSStackView(views: [pauseButton, actionButton])
        controls.orientation = .horizontal
        controls.distribution = .fillEqually
        controls.spacing = 8
        pauseButton.heightAnchor.constraint(equalToConstant: 34).isActive = true
        actionButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let workRow = labeledRow("行", value: workValue, stepper: workStepper)
        let restRow = labeledRow("止", value: restValue, stepper: restStepper)
        let checks = NSStackView(views: [overlayBox, soundBox, loginBox])
        checks.orientation = .vertical
        checks.alignment = .leading
        checks.spacing = 4
        let settings = NSStackView(views: [workRow, restRow, checks])
        settings.orientation = .vertical
        settings.alignment = .leading
        settings.spacing = 6

        let restart = linkButton("重起", #selector(restartCycle))
        let quit = linkButton("退出", #selector(quitApp))
        let footer = NSStackView(views: [restart, NSView(), quit])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12

        let root = NSStackView(views: [
            topRow, guaRow, hairline(), linesScroll, hairline(), controls, settings, footer
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            topRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            guaRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            linesScroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            linesScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 148),
            controls.widthAnchor.constraint(equalTo: root.widthAnchor),
            settings.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
            workRow.widthAnchor.constraint(equalTo: settings.widthAnchor),
            restRow.widthAnchor.constraint(equalTo: settings.widthAnchor),
            checks.widthAnchor.constraint(equalTo: settings.widthAnchor),
            linesLabel.leadingAnchor.constraint(equalTo: linesScroll.contentView.leadingAnchor),
            linesLabel.trailingAnchor.constraint(equalTo: linesScroll.contentView.trailingAnchor),
            linesLabel.topAnchor.constraint(equalTo: linesScroll.contentView.topAnchor),
            linesLabel.widthAnchor.constraint(equalTo: linesScroll.contentView.widthAnchor)
        ])

        linesScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        linesScroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        refresh()
    }

    func refresh() {
        guard let model, didBuild else { return }
        phaseLabel.stringValue = model.phaseTitle
        timeLabel.stringValue = model.format(model.remaining)
        guaNameLabel.stringValue = model.currentHexagram.heading
        judgmentLabel.stringValue = model.currentHexagram.judgment
        linesLabel.stringValue = model.currentHexagram.yaoPassage
        judgmentLabel.preferredMaxLayoutWidth = Self.judgmentWidth
        linesLabel.preferredMaxLayoutWidth = Self.innerWidth
        linesLabel.invalidateIntrinsicContentSize()
        let lineHeight = max(linesLabel.intrinsicContentSize.height, 1)
        linesLabel.frame = NSRect(x: 0, y: 0, width: Self.innerWidth, height: lineHeight)
        progress.progress = 1
        progress.yaos = model.currentHexagram.yaos
        pauseButton.title = model.isPaused ? "再行" : "且止"
        actionButton.title = model.phase == .rest ? "仍行" : "入止"
        styleFillButton(pauseButton, prominent: false)
        styleFillButton(actionButton, prominent: true)
        workStepper.integerValue = model.workMinutes
        restStepper.integerValue = model.restMinutes
        workValue.stringValue = "\(model.workMinutes) 分钟"
        restValue.stringValue = "\(model.restMinutes) 分钟"
        overlayBox.state = model.overlayEnabled ? .on : .off
        soundBox.state = model.soundEnabled ? .on : .off
        loginBox.state = model.launchAtLogin ? .on : .off
    }

    private func configureWrapping(_ label: NSTextField, size: CGFloat, color: NSColor, width: CGFloat) {
        label.font = Theme.kaiti(size: size)
        label.textColor = color
        label.alignment = .left
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.usesSingleLineMode = false
        label.preferredMaxLayoutWidth = width
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
    }

    private func styleFillButton(_ button: NSButton, prominent: Bool) {
        button.bezelStyle = .flexiblePush
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 0
        button.layer?.backgroundColor = (prominent ? Theme.cinnabar : Theme.chip).cgColor
        button.font = Theme.kaiti(size: 16)
        button.contentTintColor = prominent ? Theme.silk : Theme.ink
        let color = prominent ? Theme.silk : Theme.ink
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: color,
                .font: Theme.kaiti(size: 16)
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
    override var intrinsicContentSize: NSSize { NSSize(width: 88, height: 114) }

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
