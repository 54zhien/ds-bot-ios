import UIKit

// The drawer's content, in the shape the form settled on: one list of conversations in
// two groups — the current and pinned ones on top with a single check, the rest below
// with a relative time — then the agent grid, then two controls that stay put while the
// list moves under them.
//
// No upstream for this shape: TeamList.tsx is one flat list with an unread dot and no
// time column, and zen's rail carries no list at all. What those two give is the row's
// own look; the rest is the phone design's, and every number is written down here so a
// screenshot can be checked against it:
//   side margin      Glass.margin (16) — the drawer head's margin, ShellB.tsx:71-79
//   row height       Glass.control + Glass.gap (52) — TeamRowCell's own minimum
//   row mark         36 — TeamRowCell:741-742
//   mark-to-name     10 — TeamRowCell:757
//   name             TypeScale.rowName (16/22), palette.ink
//   time             TypeScale.caption (12/16), palette.ink3
//   section head     SidebarSectionHeaderView (caption, ink3, 1-device-pixel rule)
//   grid tile mark   Glass.control (44) — it is a target, so at least the minimum
//   grid name        TypeScale.caption, palette.ink2
//   floating control SidebarRailGlass + RailButton, the 56pt circle the rail uses
//   block gap        16 = Glass.margin; section gap 8 = Glass.gap

/// One conversation as the drawer needs it. A Bot and a room are the same record; the
/// roster is what makes a room draw its cluster instead of a character.
struct SidebarConversation: Equatable {
    let target: ChatTarget
    let look: CharacterMarks.Look
    let members: [CharacterMarks.Look]
    /// Milliseconds, the wire's unit: team/demo-team.ts ships Date.now() values.
    let lastAt: TimeInterval
    let pinned: Bool

    init(target: ChatTarget, look: CharacterMarks.Look, members: [CharacterMarks.Look] = [],
         lastAt: TimeInterval, pinned: Bool = false) {
        self.target = target
        self.look = look
        self.members = members
        self.lastAt = lastAt
        self.pinned = pinned
    }
}

/// A character in the grid under the list.
struct SidebarAgent: Equatable {
    let target: ChatTarget
    let look: CharacterMarks.Look
}

/// One device pixel, the rule the section heads and StyleSheet.hairlineWidth share.
final class SidebarHairline: UIView {
    private var lineHeight: NSLayoutConstraint!

    /// The thickness the rule actually took, for the tests that check one pixel.
    var hairlineHeight: CGFloat { lineHeight.constant }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = ThemeStore.palette(trait: traitCollection).line
        lineHeight = heightAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale))
        lineHeight.isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyTheme()
    }

    private func applyTheme() {
        backgroundColor = ThemeStore.palette(trait: traitCollection).line
        lineHeight.constant = 1 / max(1, traitCollection.displayScale)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous)
            || traitCollection.displayScale != previous?.displayScale {
            applyTheme()
        }
    }
}

/// A conversation in the list. The accessory is the whole difference between the two
/// groups: the open one shows a check, an earlier one shows when it last moved.
final class SidebarConversationRow: UIControl {
    private let mark = MarkView(frame: .zero)
    private let nameLabel = UILabel()
    private let check = IconView(icon: .check, size: 20)
    private let timeLabel = UILabel()
    private var palette = Palette.make(dark: false)
    private var showsTime = false

    private(set) var conversation: SidebarConversation?
    private(set) var isCurrent = false
    var onSelect: ((SidebarConversation) -> Void)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        palette = ThemeStore.palette(trait: traitCollection)

        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        nameLabel.font = TypeScale.rowName.font
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        check.isUserInteractionEnabled = false
        check.translatesAutoresizingMaskIntoConstraints = false
        addSubview(check)

        timeLabel.font = TypeScale.caption.font
        timeLabel.numberOfLines = 1
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: SidebarDrawerContent.rowHeight),
            mark.leadingAnchor.constraint(equalTo: leadingAnchor),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: SidebarDrawerContent.markSize),
            mark.heightAnchor.constraint(equalToConstant: SidebarDrawerContent.markSize),
            nameLabel.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            check.trailingAnchor.constraint(equalTo: trailingAnchor),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 20),
            check.heightAnchor.constraint(equalToConstant: 20),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ conversation: SidebarConversation, current: Bool, showsTime: Bool) {
        self.conversation = conversation
        self.showsTime = showsTime
        nameLabel.text = conversation.target.name
        mark.plate = palette.sidebar
        mark.configure(look: conversation.look, members: conversation.members)
        timeLabel.text = showsTime ? SidebarDrawerContent.relativeTime(conversation.lastAt) : nil
        accessibilityLabel = conversation.target.name
        setCurrent(current)
    }

    /// One flag for the whole list: the caller moves it, the row only draws it.
    func setCurrent(_ current: Bool) {
        isCurrent = current
        check.isHidden = !current
        timeLabel.isHidden = current || !showsTime
        accessibilityTraits = current ? [.button, .selected] : [.button]
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }

    @objc private func tapped() {
        guard let conversation else { return }
        onSelect?(conversation)
    }

    @objc private func themeChanged() { applyTheme() }

    private func applyTheme() {
        palette = ThemeStore.palette(trait: traitCollection)
        nameLabel.textColor = palette.ink
        timeLabel.textColor = palette.ink3
        check.color = palette.accent
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) { applyTheme() }
    }
}

/// The row that opens and closes the tail of the earlier group. It stays in place in
/// both states: a list that hides its own way back has no way back.
final class SidebarHistoryToggleRow: UIControl {
    private let label = UILabel()
    private let chevron = IconView(icon: .chevronRight, size: 14)
    private var palette = Palette.make(dark: false)

    private(set) var hiddenCount = 0
    private(set) var isExpanded = false
    var onToggle: (() -> Void)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        palette = ThemeStore.palette(trait: traitCollection)

        label.font = TypeScale.caption.font
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        chevron.isUserInteractionEnabled = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SidebarDrawerContent.rowHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -6),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(hiddenCount: Int, expanded: Bool) {
        self.hiddenCount = hiddenCount
        isExpanded = expanded
        label.text = NativeLanguage.text("Older · {count}", ["count": "\(hiddenCount)"])
        accessibilityLabel = label.text
        accessibilityValue = NativeLanguage.text(expanded ? "Expanded" : "Collapsed")
        // Pointing down when the tail is open, right when it is closed.
        chevron.transform = expanded ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
    }

    @objc private func tapped() { onToggle?() }

    @objc private func themeChanged() { applyTheme() }

    private func applyTheme() {
        palette = ThemeStore.palette(trait: traitCollection)
        label.textColor = palette.ink2
        chevron.color = palette.ink3
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) { applyTheme() }
    }
}

/// One character in the grid. A target, so it is at least 44 tall.
final class SidebarAgentTile: UIControl {
    private let mark = MarkView(frame: .zero)
    private let nameLabel = UILabel()
    private var palette = Palette.make(dark: false)

    private(set) var agent: SidebarAgent?
    var onSelect: ((SidebarAgent) -> Void)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        palette = ThemeStore.palette(trait: traitCollection)

        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)
        nameLabel.font = TypeScale.caption.font
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            mark.topAnchor.constraint(equalTo: topAnchor),
            mark.centerXAnchor.constraint(equalTo: centerXAnchor),
            mark.widthAnchor.constraint(equalToConstant: Glass.control),
            mark.heightAnchor.constraint(equalToConstant: Glass.control),
            nameLabel.topAnchor.constraint(equalTo: mark.bottomAnchor, constant: Glass.gap),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ agent: SidebarAgent) {
        self.agent = agent
        nameLabel.text = agent.target.name
        mark.plate = palette.sidebar
        mark.configure(look: agent.look)
        accessibilityLabel = agent.target.name
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }

    @objc private func tapped() {
        guard let agent else { return }
        onSelect?(agent)
    }

    private func applyTheme() {
        palette = ThemeStore.palette(trait: traitCollection)
        nameLabel.textColor = palette.ink2
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) { applyTheme() }
    }
}

/// Four to a row, as the phone's grid reads. Spacers keep the last row's columns the
/// same width as the ones above it instead of stretching three tiles across.
final class SidebarAgentGridView: UIView {
    static let columns = 4
    private let column = UIStackView()
    private var tiles: [SidebarAgentTile] = []
    var onSelect: ((SidebarAgent) -> Void)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        column.spacing = Glass.gap
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private(set) var agents: [SidebarAgent] = []
    var visibleTiles: [SidebarAgentTile] { tiles }

    func configure(agents: [SidebarAgent]) {
        self.agents = agents
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tiles = []
        for start in stride(from: 0, to: agents.count, by: Self.columns) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = Glass.gap
            row.alignment = .top
            for index in start ..< start + Self.columns {
                if index < agents.count {
                    let tile = SidebarAgentTile()
                    tile.configure(agents[index])
                    tile.onSelect = { [weak self] agent in self?.onSelect?(agent) }
                    tiles.append(tile)
                    row.addArrangedSubview(tile)
                } else {
                    // A spacer, not a hidden view: an empty column still holds its width.
                    let spacer = UIView()
                    spacer.isUserInteractionEnabled = false
                    row.addArrangedSubview(spacer)
                }
            }
            column.addArrangedSubview(row)
        }
    }
}

/// The drawer itself: device head, the list in two groups, the grid, and the two controls
/// that float over it. The list scrolls; nothing else does.
final class SidebarDrawerContent: UIView {
    static let rowHeight: CGFloat = Glass.control + Glass.gap
    static let markSize: CGFloat = 36
    /// The earlier group shows this many before the rest folds behind the toggle.
    static let historyWindow = 10
    /// Room the floating pair takes at the bottom, plus the margin under it.
    static var floatInset: CGFloat { SidebarRailLayout.controlSize + Glass.margin * 2 }

    var onSelect: ((ChatTarget) -> Void)?
    var onSettings: (() -> Void)?
    var onSearch: (() -> Void)?

    let scrollView = UIScrollView()
    let settingsGlass: SidebarRailGlass
    let searchGlass: SidebarRailGlass
    let historyToggle = SidebarHistoryToggleRow()
    let grid = SidebarAgentGridView()
    let hairline = SidebarHairline()
    private let deviceHead = SidebarDeviceHeaderView()
    private let column = UIStackView()
    private let currentHead = SidebarSectionHeaderView()
    private let earlierHead = SidebarSectionHeaderView()
    private let currentSection = UIStackView()
    private let earlierSection = UIStackView()
    private let currentStack = UIStackView()
    private let earlierStack = UIStackView()
    private let floatRow = UIStackView()

    private(set) var currentRows: [SidebarConversationRow] = []
    private(set) var earlierRows: [SidebarConversationRow] = []
    private(set) var currentTarget: ChatTarget?
    private var conversations: [SidebarConversation] = []
    /// Not persisted: every visit starts with the recent window and the tail folded.
    private(set) var isHistoryExpanded = false

    init() {
        settingsGlass = SidebarRailGlass(button: RailButton(symbol: "gearshape",
                                                           identifier: "sidebar.settings"))
        searchGlass = SidebarRailGlass(button: RailButton(symbol: "magnifyingglass",
                                                         identifier: "sidebar.search"))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        buildScroll()
        buildColumn()
        buildFloatingControls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Building

    private func buildScroll() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset.bottom = Self.floatInset
        scrollView.verticalScrollIndicatorInsets.bottom = Self.floatInset
        addSubview(scrollView)

        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 0
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Glass.gap, leading: Glass.margin, bottom: Glass.margin, trailing: Glass.margin)
        column.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(column)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            column.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            column.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func buildColumn() {
        for stack in [currentStack, earlierStack] {
            stack.axis = .vertical
            stack.spacing = 0
        }
        currentSection.axis = .vertical
        currentSection.spacing = 0
        currentSection.addArrangedSubview(currentHead)
        currentSection.addArrangedSubview(currentStack)
        earlierSection.axis = .vertical
        earlierSection.spacing = 0
        earlierSection.addArrangedSubview(earlierHead)
        earlierSection.addArrangedSubview(earlierStack)
        earlierSection.addArrangedSubview(historyToggle)

        historyToggle.onToggle = { [weak self] in self?.toggleHistory() }

        column.addArrangedSubview(deviceHead)
        column.addArrangedSubview(currentSection)
        column.addArrangedSubview(earlierSection)
        column.addArrangedSubview(hairline)
        column.addArrangedSubview(grid)
        column.setCustomSpacing(Glass.margin, after: deviceHead)
        column.setCustomSpacing(Glass.gap, after: currentSection)
        column.setCustomSpacing(Glass.margin, after: earlierSection)
        column.setCustomSpacing(Glass.margin, after: hairline)

        grid.onSelect = { [weak self] agent in self?.onSelect?(agent.target) }
    }

    private func buildFloatingControls() {
        floatRow.axis = .horizontal
        floatRow.spacing = Glass.gap
        floatRow.alignment = .center
        floatRow.translatesAutoresizingMaskIntoConstraints = false
        floatRow.addArrangedSubview(settingsGlass)
        floatRow.addArrangedSubview(searchGlass)
        addSubview(floatRow)
        settingsGlass.button?.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        searchGlass.button?.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            floatRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Glass.margin),
            floatRow.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor,
                                             constant: -Glass.margin),
        ])
    }

    // MARK: - Content

    /// The device, the conversations and the agents in one call: the drawer has one
    /// source, so it cannot show one half of the picture and miss the other.
    func configure(deviceName: String?, connected: Bool,
                   conversations: [SidebarConversation], current: ChatTarget?,
                   agents: [SidebarAgent]) {
        deviceHead.configure(name: deviceName, connected: connected)
        currentTarget = current
        self.conversations = conversations
        currentHead.configure(title: NativeLanguage.text("Current"))
        earlierHead.configure(title: NativeLanguage.text("Earlier conversation"))
        grid.configure(agents: agents)
        reload()
    }

    func toggleHistory() {
        isHistoryExpanded.toggle()
        reload()
    }

    /// The check is a single value, so the list moves it rather than each row owning one.
    func select(_ row: SidebarConversationRow) {
        guard let conversation = row.conversation else { return }
        currentTarget = conversation.target
        for other in currentRows + earlierRows { other.setCurrent(other === row) }
        onSelect?(conversation.target)
    }

    private func reload() {
        let open = conversations.filter { $0.target == currentTarget }
        let pinned = conversations
            .filter { $0.pinned && $0.target != currentTarget }
            .sorted { $0.lastAt > $1.lastAt }
        let earlier = conversations
            .filter { !$0.pinned && $0.target != currentTarget }
            .sorted { $0.lastAt > $1.lastAt }

        currentRows = rebuild(currentStack, with: open + pinned, showsTime: false)
        let shown = isHistoryExpanded ? earlier : Array(earlier.prefix(Self.historyWindow))
        earlierRows = rebuild(earlierStack, with: shown, showsTime: true)

        let hidden = max(0, earlier.count - Self.historyWindow)
        historyToggle.configure(hiddenCount: hidden, expanded: isHistoryExpanded)
        historyToggle.isHidden = hidden == 0
        earlierSection.isHidden = earlier.isEmpty
        currentSection.isHidden = currentRows.isEmpty
        grid.isHidden = grid.agents.isEmpty
        hairline.isHidden = grid.isHidden || (currentRows.isEmpty && earlierRows.isEmpty)
    }

    private func rebuild(_ stack: UIStackView, with conversations: [SidebarConversation],
                         showsTime: Bool) -> [SidebarConversationRow] {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        return conversations.map { conversation -> SidebarConversationRow in
            let row = SidebarConversationRow()
            row.configure(conversation, current: conversation.target == currentTarget,
                          showsTime: showsTime)
            row.onSelect = { [weak self, weak row] _ in
                guard let self, let row else { return }
                self.select(row)
            }
            stack.addArrangedSubview(row)
            return row
        }
    }

    // MARK: - Actions

    @objc private func settingsTapped() { onSettings?() }
    @objc private func searchTapped() { onSearch?() }

    // MARK: - Time

    /// No upstream for this column, so the platform's formatter is the source. It is
    /// pinned to the app's language rather than the device's, because every other word
    /// in the drawer comes from NativeLanguage.
    static func relativeTime(_ lastAt: TimeInterval, now: Date = Date()) -> String {
        guard lastAt > 0 else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        formatter.locale = Locale(identifier: NativeLanguage.isChinese ? "zh_Hans" : "en")
        return formatter.localizedString(for: Date(timeIntervalSince1970: lastAt / 1000),
                                         relativeTo: now)
    }
}
