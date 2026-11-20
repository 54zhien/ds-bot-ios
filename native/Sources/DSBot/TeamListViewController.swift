import UIKit

struct ChatTarget: Equatable {
    enum Kind: Equatable { case bot, room }
    let kind: Kind
    let id: String
    let name: String
}

/// The interim home of the two glyphs the chat screen still references directly;
/// Icons.swift owns every other one. It goes away when that file is rewired.
class OriginalIconView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class OriginalSidebarIcon: OriginalIconView {
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.scaleBy(x: rect.width / 20, y: rect.height / 20)
        tintColor.setStroke()
        let outline = UIBezierPath(roundedRect: CGRect(x: 3, y: 4, width: 14, height: 12), cornerRadius: 2.5)
        outline.lineWidth = 1.8
        outline.stroke()
        let divider = UIBezierPath()
        divider.move(to: CGPoint(x: 8, y: 4))
        divider.addLine(to: CGPoint(x: 8, y: 16))
        divider.lineWidth = 1.8
        divider.stroke()
        context?.restoreGState()
    }
}

/// ChevronRightIcon path from mobile/src/ui/icons.tsx. Interim: three settings
/// screens still reference this class while their restyle is in flight.
final class OriginalChevronRightIcon: OriginalIconView {
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.scaleBy(x: rect.width / 20, y: rect.height / 20)
        tintColor.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 7.5, y: 4.5))
        path.addLine(to: CGPoint(x: 13, y: 10))
        path.addLine(to: CGPoint(x: 7.5, y: 15.5))
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        context?.restoreGState()
    }
}

/// SideIcon from mobile/src/ui/icons.tsx. It draws Icon.side's own geometry: the
/// hand-traced copy here spanned 3.5–18 and read 5% low, and one glyph wants one
/// source rather than two that drift.
final class OriginalSideIcon: OriginalIconView {
    override func draw(_ rect: CGRect) {
        Icon.side.draw(in: rect, color: tintColor)
    }
}

/// SearchIcon path from mobile/src/ui/icons.tsx: the lens and its handle.
final class OriginalSearchIcon: OriginalIconView {
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.scaleBy(x: rect.width / 20, y: rect.height / 20)
        tintColor.setStroke()
        let lens = UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 11, height: 11))
        lens.lineWidth = 1.8
        lens.stroke()
        let handle = UIBezierPath()
        handle.move(to: CGPoint(x: 13, y: 13))
        handle.addLine(to: CGPoint(x: 17, y: 17))
        handle.lineWidth = 1.8
        handle.lineCapStyle = .round
        handle.stroke()
        context?.restoreGState()
    }
}

/// The mobile team's navigation data, in the same main/bot/room order as
/// mobile/src/screens/TeamList.tsx.
final class TeamListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }
    var onSelect: ((ChatTarget) -> Void)?
    /// The drawer is a child of the chat page, not a presentation, so closing it is the
    /// host's business: dismiss() on a child does nothing.
    var onClose: (() -> Void)?
    var onSettings: (() -> Void)?
    var onNeeds: (() -> Void)?
    var onCreateBot: (() -> Void)?
    var onCreateGroup: (() -> Void)?
    var onEditBot: ((String) -> Void)?
    var onEditGroup: ((String) -> Void)?
    private let state: JSONValue
    private let pendingCount: Int
    private struct Entry {
        let target: ChatTarget
        let preview: String
        let role: String
        let pinned: Bool
        let lastAt: Int
        let look: CharacterMarks.Look
        /// A room's roster, in the room's own order; empty for a Bot.
        let members: [CharacterMarks.Look]
        let waiting: Bool
        let working: Bool
    }
    private var sections: [(String, [Entry])] = []
    private var mainEntries: [Entry] = []
    private var query = ""
    private var palette = Palette.make(dark: false)
    private let gearButtonIcon = IconView(icon: .gear, size: Glass.iconXL)
    private let plusButtonIcon = IconView(icon: .plus, size: Glass.iconXL)
    private let table = UITableView(frame: .zero, style: .plain)
    private let drawerHead = UIStackView()
    private let headTitle = UILabel()
    private let searchPill = GlassPillView(height: Glass.control)
    private let pillIcon = OriginalSearchIcon()
    private let searchField = UITextField()
    private var searchControl: GlassControlView!
    private var newControl: GlassControlView!
    private var gear: GlassControlView?
    private var tableBelowHead: NSLayoutConstraint!
    private var tableBelowPill: NSLayoutConstraint!
    private var searching = false

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previous) else { return }
        refreshAppearance()
    }

    /// One path for both change signals: the trait and the theme notification. It rebuilds
    /// the header rather than repainting it, because the head is made of things that are
    /// built once — the tiles, their role chips and the head's glass controls. The real
    /// cause of a head that keeps the old palette is that `tableHeaderView` takes no part
    /// in `reloadData`: the rows below it move to the new palette and the header does not.
    func refreshAppearance() {
        // The controller's traits: its own appearance override is the one a host or a
        // test sets, and it updates this collection directly.
        palette = ThemeStore.palette(trait: traitCollection)
        gearButtonIcon.color = palette.ink2
        plusButtonIcon.color = palette.ink2
        headTitle.textColor = palette.ink
        searchField.textColor = palette.ink
        pillIcon.tintColor = palette.ink3
        view.backgroundColor = palette.sidebar
        rebuildHeader()
        table.reloadData()
    }

    @objc private func themeChanged() { refreshAppearance() }

    /// A header rebuild changes the table's content, so the offset is taken and put back:
    /// an appearance change must not scroll the list under the reader's finger.
    private func rebuildHeader() {
        let offset = table.contentOffset
        rebuild()
        table.contentOffset = offset
    }

    init(state: JSONValue) {
        self.state = state
        pendingCount = NeedsYouViewController.count(in: state)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        palette = ThemeStore.palette(trait: traitCollection)
        view.backgroundColor = palette.sidebar
        table.register(TeamRowCell.self, forCellReuseIdentifier: "team")
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 52
        table.sectionHeaderTopPadding = 0
        table.backgroundColor = .clear
        // TeamList.tsx:71: the list's own padding keeps rows above the footer fade.
        table.contentInsetAdjustmentBehavior = .never
        table.contentInset.bottom = Metrics.gearFade
        table.tableFooterView = UIView()
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)

        // ShellB.tsx:71-79: the drawer's head is the product name plus two glass
        // controls, not a navigation bar.
        drawerHead.axis = .horizontal
        drawerHead.alignment = .center
        drawerHead.spacing = Glass.gap
        drawerHead.isLayoutMarginsRelativeArrangement = true
        drawerHead.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: Glass.margin, bottom: 10, trailing: Glass.margin)
        drawerHead.translatesAutoresizingMaskIntoConstraints = false
        headTitle.text = "DS Bot"
        headTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        headTitle.textColor = palette.ink
        headTitle.setContentHuggingPriority(UILayoutPriority(249), for: .horizontal)
        drawerHead.addArrangedSubview(headTitle)
        searchControl = GlassControlView(label: tr("Search"), icon: OriginalSearchIcon())
        searchControl.addTarget(self, action: #selector(toggleSearch), for: .touchUpInside)
        drawerHead.addArrangedSubview(searchControl)
        newControl = GlassControlView(label: tr("New"), icon: plusButtonIcon)
        newControl.addTarget(self, action: #selector(showCreate), for: .touchUpInside)
        drawerHead.addArrangedSubview(newControl)
        view.addSubview(drawerHead)

        // ShellB.tsx:80-86: searching swaps the head control for a glass pill.
        searchPill.isHidden = true
        searchPill.translatesAutoresizingMaskIntoConstraints = false
        pillIcon.tintColor = palette.ink3
        pillIcon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        pillIcon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        searchPill.content.addArrangedSubview(pillIcon)
        searchField.font = .systemFont(ofSize: 15)
        searchField.textColor = palette.ink
        searchField.placeholder = tr("Search the team")
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.addTarget(self, action: #selector(searchChanged(_:)), for: .editingChanged)
        searchPill.content.addArrangedSubview(searchField)
        view.addSubview(searchPill)

        tableBelowHead = table.topAnchor.constraint(equalTo: drawerHead.bottomAnchor, constant: 0)
        tableBelowPill = table.topAnchor.constraint(equalTo: searchPill.bottomAnchor, constant: 8)
        tableBelowHead.isActive = true
        NSLayoutConstraint.activate([
            drawerHead.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            drawerHead.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawerHead.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchPill.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Glass.margin),
            searchPill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Glass.margin),
            searchPill.heightAnchor.constraint(equalToConstant: Glass.control),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // A theme the user picks is not a trait change, so both signals lead to the same
        // refresh; without this one the drawer keeps the palette it opened with.
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
        rebuild()
    }

    @objc private func openSettings() {
        let action = onSettings
        onClose?()
        action?()
    }
    @objc private func showCreate() {
        let sheet = NewChatSheetController()
        sheet.onChoose = { [weak self] choice in
            guard let self else { return }
            let botAction = onCreateBot
            let groupAction = onCreateGroup
            // ShellB.tsx:51: creating closes the drawer first, then navigates.
            sheet.dismiss(animated: true) {
                self.onClose?()
                if choice == .bot { botAction?() } else { groupAction?() }
            }
        }
        present(sheet, animated: true)
    }

    /// ShellB.tsx:115-121: settings is the drawer's footer control, concentric with
    /// the panel's corner. The presentation calls this once its fade sublayer is in
    /// place, so the addSubview here lands above the gradient.
    func installFooterGear() {
        guard gear?.superview == nil else { return }
        let control = GlassControlView(label: tr("Settings"), icon: gearButtonIcon)
        control.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        gear = control
        view.addSubview(control)
        positionFooterGear()
    }

    private func positionFooterGear() {
        let screenR = Metrics.screenRadius(bottomInset: view.safeAreaInsets.bottom, bounds: view.bounds)
        let inset = Metrics.gearInset(screenR: screenR)
        gear?.frame = CGRect(x: inset, y: view.bounds.height - inset - Glass.control,
                             width: Glass.control, height: Glass.control)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        positionFooterGear()
    }

    /// ShellB.tsx:73-86,:98: the head control swaps the pill in; a closed search
    /// drops its query, as TeamList only sees it while searching.
    @objc private func toggleSearch() {
        searching.toggle()
        searchPill.isHidden = !searching
        tableBelowHead.isActive = !searching
        tableBelowPill.isActive = searching
        if searching {
            searchField.becomeFirstResponder()
        } else {
            searchField.resignFirstResponder()
            searchField.text = nil
            query = ""
        }
        view.setNeedsLayout()
    }

    @objc private func searchChanged(_ field: UITextField) {
        query = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        rebuild()
    }

    private func rebuild() {
        let mains: Set<String>
        if case .array(let ids)? = state["mainBotIds"] {
            mains = Set(ids.compactMap(\.stringValue))
        } else {
            mains = Set([state["mainBotId"]?.stringValue].compactMap { $0 })
        }
        let bots: [JSONValue]
        if case .array(let values)? = state["bots"] { bots = values } else { bots = [] }
        let rooms: [JSONValue]
        if case .array(let values)? = state["rooms"] { rooms = values } else { rooms = [] }
        let approvals: [JSONValue]
        if case .array(let values)? = state["work"]?["approvals"] { approvals = values } else { approvals = [] }
        func visible(_ value: JSONValue) -> Bool {
            let name = value["name"]?.stringValue ?? ""
            return value["hidden"] != .bool(true)
                && (query.isEmpty || name.localizedCaseInsensitiveContains(query))
        }
        func entry(_ value: JSONValue, kind: ChatTarget.Kind) -> Entry? {
            guard let id = value["id"]?.stringValue else { return nil }
            let target = ChatTarget(kind: kind, id: id, name: value["name"]?.stringValue ?? id)
            let preview: String
            if kind == .bot {
                let session = value["sessionId"]?.stringValue ?? id
                let hasQuestion = state["questions"]?[session] != nil || state["views"]?[session] != nil
                let hasApproval = approvals.contains { $0["botId"]?.stringValue == id }
                let doing = state["work"]?["bots"]?[id] ?? state["activity"]?[id]
                let hasWaiting: Bool
                if let waiting = state["work"]?["waiting"]?[id] {
                    let waitingBots: [JSONValue]
                    let waitingRooms: [JSONValue]
                    if case .array(let values)? = waiting["bots"] { waitingBots = values } else { waitingBots = [] }
                    if case .array(let values)? = waiting["rooms"] { waitingRooms = values } else { waitingRooms = [] }
                    hasWaiting = !waitingBots.isEmpty || !waitingRooms.isEmpty
                } else {
                    hasWaiting = false
                }
                if hasQuestion || hasWaiting {
                    preview = tr("Waiting for your answer")
                } else if hasApproval {
                    preview = tr("Waiting for your approval")
                } else if let doing {
                    preview = workPhrase(doing) + "…"
                } else {
                    preview = value["preview"]?.stringValue ?? value["role"]?.stringValue ?? ""
                }
            } else if approvals.contains(where: { $0["roomId"]?.stringValue == id }) {
                preview = tr("Waiting for your approval")
            } else if case .array(let members)? = state["work"]?["rooms"]?[id], let first = members.first {
                let botID = first["botId"]?.stringValue
                let name = bots.first { $0["id"]?.stringValue == botID }?["name"]?.stringValue ?? ""
                let extra = members.count > 1 ? " +\(members.count - 1)" : ""
                preview = "\(name) · \(workPhrase(first))…\(extra)"
            } else {
                preview = value["preview"]?.stringValue ?? ""
            }
            // marks.tsx:80: the tile's marks read questions and the work table
            // directly; rows keep deriving theirs from the preview.
            let marks = kind == .bot
            let markSession = value["sessionId"]?.stringValue ?? id
            // marks.tsx:113-118: a room seats its members, so the row keeps them
            // as looks now rather than reaching back into the team state to draw.
            let members = kind == .room ? CharacterMarks.Look.members(of: value, team: state) : []
            return Entry(target: target, preview: preview, role: value["role"]?.stringValue ?? "",
                         pinned: value["pinned"] == .bool(true),
                         lastAt: value["lastAt"]?.intValue ?? value["createdAt"]?.intValue ?? 0,
                         look: CharacterMarks.Look(bot: value),
                         members: members,
                         waiting: marks && state["questions"]?[markSession] != nil,
                         working: marks && state["work"]?["bots"]?[id] != nil)
        }
        let main = bots.filter { visible($0) && mains.contains($0["id"]?.stringValue ?? "") }
            .compactMap { entry($0, kind: .bot) }
        let otherBots = bots.filter { visible($0) && !mains.contains($0["id"]?.stringValue ?? "") }
            .compactMap { entry($0, kind: .bot) }
        let groups = rooms.filter(visible).compactMap { entry($0, kind: .room) }
        let conversations = (otherBots + groups).sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.lastAt > $1.lastAt
        }
        mainEntries = main
        sections = [("Conversations", conversations)].filter { !$0.1.isEmpty }
        if bots.isEmpty && rooms.isEmpty { buildEmptyHeader() } else { buildMainTiles() }
        table.reloadData()
    }

    private func workPhrase(_ value: JSONValue) -> String {
        let tool = value.stringValue ?? value["tool"]?.stringValue ?? ""
        if value["switching"] == .bool(true) {
            return tr(value["folder"] == .bool(true) ? "Switching working folder" : "Moving to a fresh conversation")
        }
        let said = value["said"]?.stringValue ?? value["note"]?.stringValue ?? ""
        let own = said.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".。…")))
        if !own.isEmpty { return own }
        if tool.isEmpty { return tr("Thinking about it") }
        let lower = tool.lowercased()
        let phrase: String
        if lower.contains("search") && lower.contains("web") { phrase = "Searching online" }
        else if ["fetch", "browse", "browser", "web"].contains(where: lower.contains) { phrase = "Reading a page" }
        else if ["shell", "bash", "pwsh", "powershell", "exec", "command", "terminal"].contains(where: lower.contains) { phrase = "Running shell commands" }
        else if ["read", "view", "cat"].contains(where: lower.hasPrefix) { phrase = "Opening a file" }
        else if ["write", "edit", "patch", "create_file"].contains(where: lower.contains) { phrase = "Writing a file" }
        else if ["recall", "memory", "remember"].contains(where: lower.contains) { phrase = "Checking memory" }
        else { phrase = "On it" }
        let target = value["target"]?.stringValue ?? ""
        return target.isEmpty ? tr(phrase) : "\(tr(phrase)) · \(target)"
    }

    /// The team itself is empty: one line and one way forward, not a blank drawer.
    /// TeamList.tsx parks its empty text 40pt below the list top.
    private func buildEmptyHeader() {
        let width = table.bounds.width > 0 ? table.bounds.width : min(view.bounds.width * 0.85, 340)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        let column = UIStackView()
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(column)
        let text = UILabel()
        text.text = tr("No Bot yet")
        text.font = TypeScale.small.font
        text.textColor = palette.ink3
        text.textAlignment = .center
        column.addArrangedSubview(text)
        let create = UIButton(type: .system)
        create.setTitle(tr("New Bot"), for: .normal)
        create.titleLabel?.font = .systemFont(ofSize: TypeScale.rowName.size, weight: .semibold)
        create.setTitleColor(palette.accentInk, for: .normal)
        create.backgroundColor = palette.accent
        create.layer.cornerRadius = Radius.input
        create.contentEdgeInsets = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        create.heightAnchor.constraint(equalToConstant: Glass.control).isActive = true
        create.accessibilityLabel = tr("New Bot")
        create.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let action = self.onCreateBot
            self.dismiss(animated: true) { action?() }
        }, for: .touchUpInside)
        column.addArrangedSubview(create)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: header.topAnchor, constant: 40),
            column.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: header.leadingAnchor, constant: Glass.margin),
            column.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -Glass.margin),
        ])
        header.setNeedsLayout()
        header.layoutIfNeeded()
        let height = column.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height + 40
        header.frame.size.height = height
        table.tableHeaderView = header
    }

    private func buildMainTiles() {
        guard !mainEntries.isEmpty else { table.tableHeaderView = nil; return }
        let width = table.bounds.width > 0 ? table.bounds.width : min(view.bounds.width * 0.85, 340)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        let layout = UIStackView()
        layout.axis = .vertical
        layout.spacing = 8
        layout.isLayoutMarginsRelativeArrangement = true
        layout.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: Glass.margin, bottom: 10, trailing: Glass.margin)
        layout.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: header.topAnchor),
            layout.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: header.trailingAnchor),
        ])
        for start in stride(from: 0, to: mainEntries.count, by: 2) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            for entry in mainEntries[start..<min(start + 2, mainEntries.count)] {
                row.addArrangedSubview(mainTile(entry))
            }
            if row.arrangedSubviews.count == 1 {
                let spacer = UIView()
                row.addArrangedSubview(spacer)
            }
            layout.addArrangedSubview(row)
        }
        header.setNeedsLayout()
        header.layoutIfNeeded()
        let height = layout.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height
        header.frame.size.height = height
        table.tableHeaderView = header
    }

    /// The tile's height is its content, not a number beside it. The fixed 104 this
    /// replaced was 7.6pt short of what the tile holds, so the engine took the difference
    /// out of the role label: its frame fell below its own line and the glyphs were cut
    /// top and bottom. Every part below is used twice — once in a constraint, once in the
    /// sum — so the two cannot drift apart again.
    private enum TileMetrics {
        static let contentTop: CGFloat = 10     // TeamList.tsx:147
        static let contentBottom: CGFloat = 8   // TeamList.tsx:147
        static let avatar: CGFloat = 52         // TeamList.tsx:80
        static let avatarGap: CGFloat = 6       // TeamList.tsx:81
        static let nameGap: CGFloat = 3         // TeamList.tsx:82
        /// ceil(11pt SF line height 13.09) plus the role label's 2pt top and bottom.
        static let chipHeight: CGFloat = 18
        static let nameLine: CGFloat = 16       // ceil(13pt semibold line height 15.51)
        static var height: CGFloat {
            contentTop + avatar + avatarGap + nameLine + nameGap + chipHeight + contentBottom
        }
    }

    /// For the tests: the one place the derived height lives.
    static var tileHeight: CGFloat { TileMetrics.height }

    private func mainTile(_ entry: Entry) -> UIControl {
        let tile = UIControl()
        tile.backgroundColor = .clear
        tile.layer.cornerRadius = Radius.card
        // TeamList.tsx:147: a 1pt transparent rim keeps the pressed and rest
        // states the same width.
        tile.layer.borderWidth = 1
        tile.layer.borderColor = UIColor.clear.cgColor
        tile.heightAnchor.constraint(equalToConstant: Self.tileHeight).isActive = true
        tile.accessibilityIdentifier = "drawer.tile"
        tile.accessibilityLabel = "\(entry.target.name), \(tr("Main Bot"))"
        let content = UIStackView()
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        content.isUserInteractionEnabled = false
        tile.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            // TeamList.tsx:147: the tile pads 10 above its content and 8 below.
            content.topAnchor.constraint(equalTo: tile.topAnchor, constant: TileMetrics.contentTop),
            content.bottomAnchor.constraint(lessThanOrEqualTo: tile.bottomAnchor,
                                            constant: -TileMetrics.contentBottom),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: tile.leadingAnchor, constant: 6),
            content.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -6),
        ])
        // TeamList.tsx:80: the tile's mark is 52pt, larger than the row's 36.
        let avatar = CharacterAvatarView(look: entry.look)
        avatar.widthAnchor.constraint(equalToConstant: TileMetrics.avatar).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: TileMetrics.avatar).isActive = true
        content.addArrangedSubview(avatar)
        if entry.waiting || entry.working {
            // marks.tsx:69,:72,:78-85: 27% of the avatar in a transparent gap;
            // the question mark or the working dot, never a plate.
            let gap = UIView()
            gap.translatesAutoresizingMaskIntoConstraints = false
            gap.backgroundColor = .clear
            gap.isUserInteractionEnabled = false
            let mark = UIView()
            mark.translatesAutoresizingMaskIntoConstraints = false
            mark.layer.cornerRadius = 7
            mark.backgroundColor = entry.waiting ? palette.accent : palette.green
            gap.addSubview(mark)
            if entry.waiting {
                let q = UILabel()
                q.text = "?"
                q.font = .systemFont(ofSize: 9, weight: .semibold)
                q.textColor = .white
                q.textAlignment = .center
                q.translatesAutoresizingMaskIntoConstraints = false
                gap.addSubview(q)
                NSLayoutConstraint.activate([
                    q.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
                    q.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
                ])
            }
            NSLayoutConstraint.activate([
                gap.centerXAnchor.constraint(equalTo: avatar.trailingAnchor, constant: -10),
                gap.centerYAnchor.constraint(equalTo: avatar.bottomAnchor, constant: -10),
                gap.widthAnchor.constraint(equalToConstant: 18),
                gap.heightAnchor.constraint(equalToConstant: 18),
                mark.centerXAnchor.constraint(equalTo: gap.centerXAnchor),
                mark.centerYAnchor.constraint(equalTo: gap.centerYAnchor),
                mark.widthAnchor.constraint(equalToConstant: 14),
                mark.heightAnchor.constraint(equalToConstant: 14),
            ])
            tile.addSubview(gap)
        }
        // marks.tsx:87: a main bot wears the star at the avatar's corner, on top
        // of the marks, ringed so it reads against the tile's hover fill.
        let star = IconView(icon: .mainStar, size: 19, color: palette.star, ring: palette.hover)
        star.translatesAutoresizingMaskIntoConstraints = false
        star.isUserInteractionEnabled = false
        tile.addSubview(star)
        NSLayoutConstraint.activate([
            star.trailingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 3.6),
            star.bottomAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 3.6),
            // Without a size of its own the star has nothing to trail from.
            star.widthAnchor.constraint(equalToConstant: 19),
            star.heightAnchor.constraint(equalToConstant: 19),
        ])
        let name = UILabel()
        name.text = entry.target.name
        name.font = .systemFont(ofSize: TypeScale.small.size, weight: .semibold)
        name.textColor = palette.ink
        name.textAlignment = .center
        name.lineBreakMode = .byTruncatingTail
        // The name gives way first — its width truncates, its height never does, which
        // is TeamList.tsx:289-291's flexShrink on the name and none on the chip.
        name.setContentCompressionResistancePriority(.required, for: .vertical)
        name.accessibilityIdentifier = "drawer.tile.name"
        content.addArrangedSubview(name)
        // TeamList.tsx:81-82: 6 under the avatar, 3 above the role chip.
        content.setCustomSpacing(TileMetrics.avatarGap, after: avatar)
        content.setCustomSpacing(TileMetrics.nameGap, after: name)
        if !entry.role.isEmpty {
            // TeamList.tsx:82,:148: the role rides on an active chip.
            let chip = UIView()
            chip.backgroundColor = palette.active
            chip.layer.cornerRadius = Radius.item
            chip.accessibilityIdentifier = "drawer.tile.chip"
            // Its height is stated rather than inherited: the chip keeps one line of
            // 11pt type and the tile is sized around it, never the other way round.
            chip.heightAnchor.constraint(equalToConstant: TileMetrics.chipHeight).isActive = true
            chip.setContentCompressionResistancePriority(.required, for: .vertical)
            chip.setContentCompressionResistancePriority(.required, for: .horizontal)
            let role = UILabel()
            role.text = entry.role
            role.font = .systemFont(ofSize: 11)
            role.textColor = palette.ink2
            role.textAlignment = .center
            role.lineBreakMode = .byTruncatingTail
            role.accessibilityIdentifier = "drawer.tile.role"
            role.setContentCompressionResistancePriority(.required, for: .vertical)
            chip.addSubview(role)
            role.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                role.topAnchor.constraint(equalTo: chip.topAnchor, constant: 2),
                role.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -2),
                role.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 6),
                // Equal, not "at most": the chip is its text plus its two 6pt sides. With
                // the ≤ it had, the chip's own width had no lower bound at all, so nothing
                // stopped the engine from squeezing the label inside it.
                role.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -6),
            ])
            chip.widthAnchor.constraint(lessThanOrEqualToConstant: 92).isActive = true
            content.addArrangedSubview(chip)
        }
        tile.addAction(UIAction { [weak self] _ in self?.open(entry) }, for: .touchUpInside)
        return tile
    }

    private func open(_ entry: Entry) {
        UserDefaults.standard.set(Int(Date().timeIntervalSince1970 * 1_000),
                                  forKey: "dsbot.seen.\(entry.target.id)")
        onSelect?(entry.target)
    }

    private func rowState(_ preview: String) -> TeamRowCell.State {
        if preview == tr("Waiting for your answer") { return .waiting }
        if preview == tr("Waiting for your approval") { return .approval }
        if preview.hasSuffix("…") { return .working }
        return .none
    }

    private var sectionOffset: Int { pendingCount > 0 ? 1 : 0 }
    func numberOfSections(in tableView: UITableView) -> Int { sections.count + sectionOffset }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section < sectionOffset ? 1 : sections[section - sectionOffset].1.count
    }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section < sectionOffset ? nil : tr(sections[section - sectionOffset].0)
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "team", for: indexPath) as! TeamRowCell
        if indexPath.section < sectionOffset {
            cell.configureNeeds(title: "\(tr("Needs you")) · \(pendingCount)", ink: palette.accent, palette: palette)
            return cell
        }
        let entry = sections[indexPath.section - sectionOffset].1[indexPath.row]
        let seen = UserDefaults.standard.integer(forKey: "dsbot.seen.\(entry.target.id)")
        cell.configure(
            name: entry.target.name,
            preview: entry.preview.isEmpty ? tr(entry.target.kind == .room ? "Group chat" : "Bot") : entry.preview,
            look: entry.look, members: entry.members,
            unread: entry.lastAt > seen,
            state: rowState(entry.preview),
            palette: palette)
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section < sectionOffset {
            let action = onNeeds
            onClose?()
            action?()
            return
        }
        let entry = sections[indexPath.section - sectionOffset].1[indexPath.row]
        open(entry)
    }

    func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section >= sectionOffset else { return nil }
        let target = sections[indexPath.section - sectionOffset].1[indexPath.row].target
        let edit = UIContextualAction(style: .normal, title: tr("Edit")) { [weak self] _, _, done in
            guard let self else { done(false); return }
            let botAction = onEditBot
            let groupAction = onEditGroup
            onClose?()
            if target.kind == .bot {
                botAction?(target.id)
            } else {
                groupAction?(target.id)
            }
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [edit])
    }
}

/// One team row: avatar, name, preview, and the unread or state mark, at the sizes
/// mobile/src/screens/TeamList.tsx gives them.
final class TeamRowCell: UITableViewCell {
    enum State { case none, working, waiting, approval }

    /// The 36pt box every row's mark sits in: a character for a Bot, a cluster for
    /// a room. TeamList.tsx:105,:126 give both the same slot.
    private let avatar = UIView()
    private let mark = MarkView(frame: .zero)
    private let nameLabel = UILabel()
    private let previewLabel = UILabel()
    private let unreadDot = UIView()
    // The badge sits in a transparent gap: no ring, no plate behind it.
    private let gap = UIView()
    private let badge = UIView()
    private let badgeLabel = UILabel()
    private let workingDot = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        let hover = UIView()
        hover.layer.cornerRadius = Radius.row
        selectedBackgroundView = hover

        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.isAccessibilityElement = false
        mark.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(mark)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.lineBreakMode = .byTruncatingTail

        unreadDot.translatesAutoresizingMaskIntoConstraints = false
        unreadDot.layer.cornerRadius = 4

        gap.translatesAutoresizingMaskIntoConstraints = false
        gap.backgroundColor = .clear
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.layer.cornerRadius = 6
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.text = "?"
        badgeLabel.textAlignment = .center
        badgeLabel.font = .systemFont(ofSize: 8, weight: .semibold)
        workingDot.translatesAutoresizingMaskIntoConstraints = false
        workingDot.layer.cornerRadius = 4

        contentView.addSubview(avatar)
        contentView.addSubview(nameLabel)
        contentView.addSubview(previewLabel)
        contentView.addSubview(unreadDot)
        contentView.addSubview(gap)
        gap.addSubview(badge)
        gap.addSubview(workingDot)
        badge.addSubview(badgeLabel)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: Glass.control + Glass.gap),
            mark.leadingAnchor.constraint(equalTo: avatar.leadingAnchor),
            mark.trailingAnchor.constraint(equalTo: avatar.trailingAnchor),
            mark.topAnchor.constraint(equalTo: avatar.topAnchor),
            mark.bottomAnchor.constraint(equalTo: avatar.bottomAnchor),
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Glass.margin),
            avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 36),
            avatar.heightAnchor.constraint(equalToConstant: 36),
            gap.centerXAnchor.constraint(equalTo: avatar.trailingAnchor, constant: -1),
            gap.centerYAnchor.constraint(equalTo: avatar.bottomAnchor, constant: -1),
            gap.widthAnchor.constraint(equalToConstant: 16),
            gap.heightAnchor.constraint(equalToConstant: 16),
            badge.centerXAnchor.constraint(equalTo: gap.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: gap.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 12),
            badge.heightAnchor.constraint(equalToConstant: 12),
            badgeLabel.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            workingDot.centerXAnchor.constraint(equalTo: gap.centerXAnchor),
            workingDot.centerYAnchor.constraint(equalTo: gap.centerYAnchor),
            workingDot.widthAnchor.constraint(equalToConstant: 8),
            workingDot.heightAnchor.constraint(equalToConstant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: unreadDot.leadingAnchor, constant: -8),
            previewLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            previewLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            previewLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            unreadDot.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Glass.margin),
            unreadDot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, preview: String, look: CharacterMarks.Look, members: [CharacterMarks.Look],
                   unread: Bool, state: State, palette: Palette) {
        nameLabel.attributedText = NSAttributedString(string: name, attributes: TypeScale.rowName.attributes)
        nameLabel.textColor = palette.ink
        previewLabel.attributedText = NSAttributedString(string: preview, attributes: TypeScale.rowPreview.attributes)
        previewLabel.textColor = palette.ink2
        // A cell recycled from the Needs row has its mark hidden, not removed.
        mark.isHidden = false
        // TeamList.tsx:126: a room's ring is the drawer's own colour.
        mark.plate = palette.sidebar
        mark.configure(look: look, members: members)
        unreadDot.isHidden = !unread
        unreadDot.backgroundColor = palette.accent
        selectedBackgroundView?.backgroundColor = palette.hover
        gap.isHidden = state == .none
        badge.isHidden = state != .waiting
        workingDot.isHidden = state != .working
        // RN draws the working mark as an 8pt green dot (TeamList.tsx).
        workingDot.backgroundColor = palette.green
        badge.backgroundColor = palette.accent
        badgeLabel.textColor = palette.accentInk
        isAccessibilityElement = true
        accessibilityLabel = name + ", " + preview
    }

    func configureNeeds(title: String, ink: UIColor, palette: Palette) {
        nameLabel.attributedText = NSAttributedString(string: title, attributes: TypeScale.rowName.attributes)
        nameLabel.textColor = ink
        previewLabel.attributedText = nil
        mark.isHidden = true
        unreadDot.isHidden = true
        gap.isHidden = true
        selectedBackgroundView?.backgroundColor = palette.hover
        isAccessibilityElement = true
        accessibilityLabel = title
    }
}


/// ShellB.tsx:100-114,:389-392: the drawer's create card — a scrimmed sheet at the
/// bottom with one row per thing to create, not a system action sheet.
private final class NewChatSheetController: UIViewController {
    enum Choice { case bot, group }
    var onChoose: ((Choice) -> Void)?

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let palette = ThemeStore.palette(trait: traitCollection)
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        let scrim = UITapGestureRecognizer(target: self, action: #selector(close))
        view.addGestureRecognizer(scrim)

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = palette.card
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = palette.line.cgColor
        Shadow.level3.apply(to: card.layer)
        view.addSubview(card)

        let newBot = row(icon: .plus, text: NativeLanguage.text("Create new Bot"), choice: .bot, palette: palette)
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = palette.line
        let group = row(icon: .people, text: NativeLanguage.text("Create group chat"), choice: .group, palette: palette)
        card.addSubview(newBot)
        card.addSubview(divider)
        card.addSubview(group)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            newBot.topAnchor.constraint(equalTo: card.topAnchor),
            newBot.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            newBot.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            newBot.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            divider.topAnchor.constraint(equalTo: newBot.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 64),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            group.topAnchor.constraint(equalTo: divider.bottomAnchor),
            group.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            group.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            group.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
    }

    /// ShellB.tsx:391: a 56pt row, a 36pt icon box on a hover fill, settingsRow text.
    private func row(icon: Icon, text: String, choice: Choice, palette: Palette) -> UIControl {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.accessibilityLabel = text
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.backgroundColor = palette.hover
        box.layer.cornerRadius = 18
        // material.tsx rimSkin: the rim shows in the dark, not in the light.
        box.layer.borderWidth = 1
        box.layer.borderColor = traitCollection.userInterfaceStyle == .dark
            ? palette.line.cgColor : UIColor.clear.cgColor
        let glyph = IconView(icon: icon, size: 18, color: palette.ink)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(glyph)
        control.addSubview(box)
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(string: text, attributes: TypeScale.settingsRow.attributes)
        label.textColor = palette.ink
        control.addSubview(label)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 14),
            box.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 36),
            box.heightAnchor.constraint(equalToConstant: 36),
            glyph.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: control.trailingAnchor, constant: -14),
        ])
        // RN dims a pressed row's fill, not its contents.
        control.addTarget(self, action: #selector(pressedRow(_:)), for: [.touchDown, .touchDragEnter])
        control.addTarget(self, action: #selector(restoredRow(_:)), for: [.touchDragExit, .touchCancel, .touchUpInside])
        control.addAction(UIAction { [weak self] _ in self?.choose(choice) }, for: .touchUpInside)
        return control
    }

    @objc private func pressedRow(_ control: UIControl) {
        control.backgroundColor = ThemeStore.palette(trait: traitCollection).hover
    }

    @objc private func restoredRow(_ control: UIControl) {
        control.backgroundColor = .clear
    }

    private func choose(_ choice: Choice) {
        let action = onChoose
        dismiss(animated: true) { action?(choice) }
    }

    @objc private func close() { dismiss(animated: true) }
}
