import UIKit

/// NeedsYou.tsx as a bare sheet: a sectioned list over the page colour, with the
/// sheet's own 66pt head clearance, a marked badge per section and avatars that
/// carry the waiting question, no navigation chrome.
final class NeedsYouViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onOpen: ((ChatTarget) -> Void)?

    private struct Row {
        let target: ChatTarget
        let bot: JSONValue?
        let summary: String
    }
    private struct Section {
        let title: String
        let mark: String
        let rows: [Row]
    }

    private let sections: [Section]
    private let table = UITableView(frame: .zero, style: .plain)
    private var palette = Palette.make(dark: false)
    private var emptyLabel: UILabel?

    static func count(in state: JSONValue) -> Int {
        let questions: Int
        if case .object(let values)? = state["questions"] { questions = values.count } else { questions = 0 }
        let approvals: Int
        if case .array(let values)? = state["work"]?["approvals"] {
            approvals = values.filter { $0["answerable"] != .bool(false) }.count
        } else { approvals = 0 }
        let secrets: Int
        if case .object(let groups)? = state["secretRequests"] {
            secrets = groups.values.reduce(0) { total, value -> Int in
                guard case .array(let requests) = value else { return total }
                return total + requests.filter { $0["status"]?.stringValue == "pending" }.count
            }
        } else { secrets = 0 }
        let handoffs: Int
        if case .object(let values)? = state["browserHolds"] {
            handoffs = values.values.filter { $0["callId"]?.stringValue != nil }.count
        } else { handoffs = 0 }
        let views: Int
        if case .object(let values)? = state["views"] { views = values.count } else { views = 0 }
        return questions + approvals + secrets + handoffs + views
    }

    init(state: JSONValue) {
        let bots: [JSONValue]
        if case .array(let values)? = state["bots"] { bots = values } else { bots = [] }
        let rooms: [JSONValue]
        if case .array(let values)? = state["rooms"] { rooms = values } else { rooms = [] }
        func botOf(_ id: String) -> JSONValue? {
            bots.first { $0["id"]?.stringValue == id }
        }
        func botOfSession(_ sessionID: String) -> JSONValue? {
            bots.first { $0["sessionId"]?.stringValue == sessionID || $0["id"]?.stringValue == sessionID }
        }
        var questions: [Row] = []
        if case .object(let values)? = state["questions"] {
            for (sessionID, question) in values {
                guard let bot = botOfSession(sessionID) else { continue }
                let id = bot["id"]?.stringValue ?? sessionID
                questions.append(Row(target: ChatTarget(kind: .bot, id: id, name: bot["name"]?.stringValue ?? id),
                                     bot: bot,
                                     summary: question["question"]?.stringValue ?? NativeLanguage.text("Question")))
            }
        }
        var approvals: [Row] = []
        if case .array(let values)? = state["work"]?["approvals"] {
            for value in values {
                let bot = value["botId"]?.stringValue.flatMap(botOf)
                let roomID = value["roomId"]?.stringValue
                let target: ChatTarget?
                if let roomID {
                    let name = rooms.first { $0["id"]?.stringValue == roomID }?["name"]?.stringValue ?? roomID
                    target = ChatTarget(kind: .room, id: roomID, name: name)
                } else if let bot {
                    let id = bot["id"]?.stringValue ?? ""
                    target = ChatTarget(kind: .bot, id: id, name: bot["name"]?.stringValue ?? id)
                } else { target = nil }
                guard let target else { continue }
                let text = [value["tool"]?.stringValue, value["reason"]?.stringValue]
                    .compactMap { $0 }.joined(separator: " · ")
                approvals.append(Row(target: target, bot: bot, summary: text))
            }
        }
        var secrets: [Row] = []
        if case .object(let groups)? = state["secretRequests"] {
            for (botID, value) in groups {
                guard case .array(let requests) = value else { continue }
                for request in requests where request["status"]?.stringValue == "pending" {
                    let name = request["name"]?.stringValue ?? ""
                    secrets.append(Row(
                        target: ChatTarget(kind: .bot, id: botID, name: botOf(botID)?["name"]?.stringValue ?? botID),
                        bot: botOf(botID),
                        summary: name.isEmpty
                            ? NativeLanguage.text("A secret is needed")
                            : NativeLanguage.text("Asks for the secret {name}", ["name": name])))
                }
            }
        }
        var handoffs: [Row] = []
        if case .object(let values)? = state["browserHolds"] {
            for (botID, hold) in values where hold["callId"]?.stringValue != nil {
                handoffs.append(Row(
                    target: ChatTarget(kind: .bot, id: botID, name: botOf(botID)?["name"]?.stringValue ?? botID),
                    bot: botOf(botID),
                    summary: hold["note"]?.stringValue
                        ?? hold["reason"]?.stringValue ?? NativeLanguage.text("Browser handoff")))
            }
        }
        var views: [Row] = []
        if case .object(let values)? = state["views"] {
            for (sessionID, view) in values {
                guard let bot = botOfSession(sessionID) else { continue }
                let id = bot["id"]?.stringValue ?? sessionID
                views.append(Row(target: ChatTarget(kind: .bot, id: id, name: bot["name"]?.stringValue ?? id),
                                 bot: bot,
                                 summary: view["title"]?.stringValue ?? NativeLanguage.text("View")))
            }
        }
        sections = [
            Section(title: NativeLanguage.text("Questions"), mark: "?", rows: questions),
            Section(title: NativeLanguage.text("Approvals"), mark: "!", rows: approvals),
            Section(title: NativeLanguage.text("Secret requests"), mark: "🔑", rows: secrets),
            Section(title: NativeLanguage.text("Browser handoffs"), mark: "🌐", rows: handoffs),
            Section(title: NativeLanguage.text("Cards"), mark: "▣", rows: views),
        ].filter { !$0.rows.isEmpty }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        palette = ThemeStore.palette(trait: traitCollection)
        view.backgroundColor = palette.main
        table.dataSource = self
        table.delegate = self
        table.register(NeedsRowCell.self, forCellReuseIdentifier: "needs")
        table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 56
        table.sectionHeaderTopPadding = 0
        table.backgroundColor = .clear
        // NeedsYou.tsx:55: the content starts SHEET_HEAD below the sheet's top.
        table.contentInsetAdjustmentBehavior = .never
        table.contentInset.top = Metrics.sheetHead
        table.tableFooterView = UIView()
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // NeedsYou.tsx:79: one quiet line, 60 below the content's start; the state
        // itself is the answer, so there is no button to press.
        if sections.isEmpty {
            let empty = UILabel()
            empty.text = NativeLanguage.text("Nothing needs you")
            empty.font = TypeScale.small.font
            empty.textColor = palette.ink3
            empty.textAlignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.topAnchor.constraint(equalTo: view.topAnchor, constant: Metrics.sheetHead + 60),
                empty.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                empty.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            emptyLabel = empty
        }
    }

    /// ShellB.tsx:339: the sheet takes the half and the full detents, grabber out.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        palette = ThemeStore.palette(trait: traitCollection)
        view.backgroundColor = palette.main
        emptyLabel?.textColor = palette.ink3
        table.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    /// NeedsYou.tsx:58-65,:85-86: the mark sits in a hover badge before the title.
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UIView()
        header.backgroundColor = palette.main
        let badge = UILabel()
        badge.text = sections[section].mark
        badge.font = TypeScale.caption.font
        badge.textColor = palette.ink2
        badge.textAlignment = .center
        badge.backgroundColor = palette.hover
        badge.layer.cornerRadius = Radius.tag
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = sections[section].title
        title.font = .systemFont(ofSize: TypeScale.caption.size, weight: .semibold)
        title.textColor = palette.ink3
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(badge)
        header.addSubview(title)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Glass.margin),
            badge.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
            title.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: Glass.gap),
            title.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -Glass.margin),
        ])
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 38 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "needs", for: indexPath) as! NeedsRowCell
        let row = sections[indexPath.section].rows[indexPath.row]
        cell.configure(name: row.target.name, summary: row.summary,
                       look: row.bot.map { CharacterMarks.Look(bot: $0) }, palette: palette)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let row = sections[indexPath.section].rows[indexPath.row]
        onOpen?(row.target)
        dismiss(animated: true)
    }
}

/// NeedsYou.tsx:66-77,:87: a 56pt row with a 44pt avatar that always carries the
/// waiting question, the name over the summary, and a hover fill when pressed.
private final class NeedsRowCell: UITableViewCell {
    private let avatar = CharacterAvatarView()
    private let gap = UIView()
    private let badge = UIView()
    private let q = UILabel()
    private let nameLabel = UILabel()
    private let summaryLabel = UILabel()
    private let body = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        let hover = UIView()
        selectedBackgroundView = hover

        avatar.translatesAutoresizingMaskIntoConstraints = false

        // marks.tsx:69,:72,:78-81: the question is 27% of the avatar in a
        // transparent gap at the corner; a NeedsYou row always asks one.
        gap.translatesAutoresizingMaskIntoConstraints = false
        gap.backgroundColor = .clear
        gap.isUserInteractionEnabled = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.layer.cornerRadius = 6
        q.text = "?"
        q.font = .systemFont(ofSize: 8, weight: .semibold)
        q.textColor = .white
        q.textAlignment = .center
        q.translatesAutoresizingMaskIntoConstraints = false
        gap.addSubview(badge)
        badge.addSubview(q)

        body.axis = .vertical
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(nameLabel)
        body.addArrangedSubview(summaryLabel)

        contentView.addSubview(avatar)
        contentView.addSubview(gap)
        contentView.addSubview(body)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Glass.margin),
            avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),
            gap.centerXAnchor.constraint(equalTo: avatar.trailingAnchor, constant: -9),
            gap.centerYAnchor.constraint(equalTo: avatar.bottomAnchor, constant: -9),
            gap.widthAnchor.constraint(equalToConstant: 16),
            gap.heightAnchor.constraint(equalToConstant: 16),
            badge.centerXAnchor.constraint(equalTo: gap.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: gap.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 12),
            badge.heightAnchor.constraint(equalToConstant: 12),
            q.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            q.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            body.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            body.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            body.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -Glass.margin),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, summary: String, look: CharacterMarks.Look?, palette: Palette) {
        nameLabel.attributedText = NSAttributedString(string: name, attributes: TypeScale.rowName.attributes)
        nameLabel.textColor = palette.ink
        summaryLabel.attributedText = NSAttributedString(string: summary, attributes: TypeScale.rowPreview.attributes)
        summaryLabel.textColor = palette.ink2
        // NeedsYou.tsx:71: a row with no bot keeps the avatar's space, empty.
        avatar.isHidden = look == nil
        if let look { avatar.look = look }
        badge.backgroundColor = palette.accent
        selectedBackgroundView?.backgroundColor = palette.hover
        isAccessibilityElement = true
        accessibilityLabel = name + ", " + summary
    }
}
