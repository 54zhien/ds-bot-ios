import UIKit

struct ChatTarget: Equatable {
    enum Kind: Equatable { case bot, room }
    let kind: Kind
    let id: String
    let name: String
}

/// SidebarIcon from mobile/src/ui/icons.tsx, 20×20 viewBox.
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

/// GearIcon path from mobile/src/ui/icons.tsx.
final class OriginalGearIcon: OriginalIconView {
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.scaleBy(x: rect.width / 20, y: rect.height / 20)
        tintColor.setStroke()
        let ring = UIBezierPath(ovalIn: CGRect(x: 7.4, y: 7.4, width: 5.2, height: 5.2))
        ring.lineWidth = 1.8
        ring.stroke()
        let outline = UIBezierPath()
        let points = [
            CGPoint(x: 7.85, y: 4.4), CGPoint(x: 8.14, y: 2.53), CGPoint(x: 11.86, y: 2.53),
            CGPoint(x: 12.15, y: 4.4), CGPoint(x: 13.78, y: 5.34), CGPoint(x: 15.54, y: 4.65),
            CGPoint(x: 17.4, y: 7.88), CGPoint(x: 15.93, y: 9.06), CGPoint(x: 15.93, y: 10.94),
            CGPoint(x: 17.4, y: 12.12), CGPoint(x: 15.54, y: 15.35), CGPoint(x: 13.78, y: 14.66),
            CGPoint(x: 12.15, y: 15.6), CGPoint(x: 11.86, y: 17.47), CGPoint(x: 8.14, y: 17.47),
            CGPoint(x: 7.85, y: 15.6), CGPoint(x: 6.22, y: 14.66), CGPoint(x: 4.46, y: 15.35),
            CGPoint(x: 2.6, y: 12.12), CGPoint(x: 4.07, y: 10.94), CGPoint(x: 4.07, y: 9.06),
            CGPoint(x: 2.6, y: 7.88), CGPoint(x: 4.46, y: 4.65), CGPoint(x: 6.22, y: 5.34),
        ]
        outline.move(to: points[0])
        for point in points.dropFirst() { outline.addLine(to: point) }
        outline.close()
        outline.lineWidth = 1.8
        outline.lineJoinStyle = .round
        outline.stroke()
        context?.restoreGState()
    }
}

/// ChevronRightIcon path from mobile/src/ui/icons.tsx.
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

/// SideIcon path from mobile/src/ui/icons.tsx.
final class OriginalSideIcon: OriginalIconView {
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.scaleBy(x: rect.width / 20, y: rect.height / 20)
        tintColor.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 17, y: 11.5))
        path.addCurve(to: CGPoint(x: 10.5, y: 18), controlPoint1: CGPoint(x: 17, y: 15.1),
                      controlPoint2: CGPoint(x: 14.1, y: 18))
        path.addLine(to: CGPoint(x: 4, y: 18))
        path.addLine(to: CGPoint(x: 6, y: 15.4))
        path.addCurve(to: CGPoint(x: 3.5, y: 10), controlPoint1: CGPoint(x: 4.4, y: 14.2),
                      controlPoint2: CGPoint(x: 3.5, y: 12.4))
        path.addCurve(to: CGPoint(x: 10, y: 3.5), controlPoint1: CGPoint(x: 3.5, y: 6.4),
                      controlPoint2: CGPoint(x: 6.4, y: 3.5))
        path.addCurve(to: CGPoint(x: 17, y: 11.5), controlPoint1: CGPoint(x: 14.2, y: 3.5),
                      controlPoint2: CGPoint(x: 17, y: 7))
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        let x = UIBezierPath()
        x.move(to: CGPoint(x: 8.8, y: 8.8))
        x.addLine(to: CGPoint(x: 11.2, y: 11.2))
        x.move(to: CGPoint(x: 11.2, y: 8.8))
        x.addLine(to: CGPoint(x: 8.8, y: 11.2))
        x.lineWidth = 1.8
        x.lineCapStyle = .round
        x.stroke()
        context?.restoreGState()
    }
}

/// CloseIcon path from mobile/src/ui/icons.tsx.
final class OriginalCloseIcon: OriginalIconView {
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.scaleBy(x: rect.width / 20, y: rect.height / 20)
        tintColor.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 5, y: 5))
        path.addLine(to: CGPoint(x: 15, y: 15))
        path.move(to: CGPoint(x: 15, y: 5))
        path.addLine(to: CGPoint(x: 5, y: 15))
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.stroke()
        context?.restoreGState()
    }
}

/// The mobile team's navigation data, in the same main/bot/room order as
/// mobile/src/screens/TeamList.tsx.
final class TeamListViewController: UITableViewController, UISearchResultsUpdating {
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }
    var onSelect: ((ChatTarget) -> Void)?
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
    }
    private var sections: [(String, [Entry])] = []
    private var mainEntries: [Entry] = []
    private var query = ""

    init(state: JSONValue) {
        self.state = state
        pendingCount = NeedsYouViewController.count(in: state)
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "DS Bot"
        let settings = UIButton(type: .system)
        settings.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        settings.accessibilityLabel = tr("Settings")
        settings.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        let icon = OriginalGearIcon(frame: CGRect(x: 10, y: 10, width: 24, height: 24))
        icon.isUserInteractionEnabled = false
        settings.addSubview(icon)
        let create = UIButton(type: .system)
        create.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        create.accessibilityLabel = tr("Create")
        create.addTarget(self, action: #selector(showCreate), for: .touchUpInside)
        let plus = OriginalPlusIcon(frame: CGRect(x: 10, y: 10, width: 24, height: 24))
        plus.isUserInteractionEnabled = false
        create.addSubview(plus)
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close)),
            UIBarButtonItem(customView: settings),
            UIBarButtonItem(customView: create),
        ]
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = tr("Search the team")
        navigationItem.searchController = search
        rebuild()
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func openSettings() {
        let action = onSettings
        dismiss(animated: true) { action?() }
    }
    @objc private func showCreate() {
        let sheet = UIAlertController(title: tr("Create"), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: tr("New Bot"), style: .default) { [weak self] _ in
            guard let self else { return }
            let action = onCreateBot
            dismiss(animated: true) { action?() }
        })
        sheet.addAction(UIAlertAction(title: tr("Group chat"), style: .default) { [weak self] _ in
            guard let self else { return }
            let action = onCreateGroup
            dismiss(animated: true) { action?() }
        })
        sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        present(sheet, animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
        func visible(_ value: JSONValue) -> Bool {
            let name = value["name"]?.stringValue ?? ""
            return value["hidden"] != .bool(true)
                && (query.isEmpty || name.localizedCaseInsensitiveContains(query))
        }
        func entry(_ value: JSONValue, kind: ChatTarget.Kind) -> Entry? {
            guard let id = value["id"]?.stringValue else { return nil }
            let target = ChatTarget(kind: kind, id: id, name: value["name"]?.stringValue ?? id)
            let preview = value["preview"]?.stringValue ?? value["role"]?.stringValue ?? ""
            return Entry(target: target, preview: preview, role: value["role"]?.stringValue ?? "",
                         pinned: value["pinned"] == .bool(true),
                         lastAt: value["lastAt"]?.intValue ?? value["createdAt"]?.intValue ?? 0)
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
        buildMainTiles()
        tableView.reloadData()
    }

    private func buildMainTiles() {
        guard !mainEntries.isEmpty else { tableView.tableHeaderView = nil; return }
        let width = tableView.bounds.width > 0 ? tableView.bounds.width : min(view.bounds.width * 0.85, 340)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        let layout = UIStackView()
        layout.axis = .vertical
        layout.spacing = 8
        layout.isLayoutMarginsRelativeArrangement = true
        layout.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16)
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
        tableView.tableHeaderView = header
    }

    private func mainTile(_ entry: Entry) -> UIControl {
        let tile = UIControl()
        tile.backgroundColor = .tertiarySystemGroupedBackground
        tile.layer.cornerRadius = 20
        tile.layer.borderWidth = 0.5
        tile.layer.borderColor = UIColor.separator.cgColor
        tile.heightAnchor.constraint(equalToConstant: 112).isActive = true
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
            content.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: tile.leadingAnchor, constant: 6),
            content.trailingAnchor.constraint(lessThanOrEqualTo: tile.trailingAnchor, constant: -6),
        ])
        let avatar = UILabel()
        avatar.text = String(entry.target.name.prefix(1)).uppercased()
        avatar.textAlignment = .center
        avatar.textColor = .white
        avatar.font = .systemFont(ofSize: 22, weight: .semibold)
        avatar.backgroundColor = .systemBlue
        avatar.layer.cornerRadius = 26
        avatar.clipsToBounds = true
        avatar.widthAnchor.constraint(equalToConstant: 52).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 52).isActive = true
        content.addArrangedSubview(avatar)
        let name = UILabel()
        name.text = entry.target.name
        name.font = .preferredFont(forTextStyle: .subheadline)
        name.textAlignment = .center
        name.lineBreakMode = .byTruncatingTail
        content.addArrangedSubview(name)
        if !entry.role.isEmpty {
            let role = UILabel()
            role.text = entry.role
            role.font = .preferredFont(forTextStyle: .caption2)
            role.textColor = .secondaryLabel
            role.textAlignment = .center
            role.lineBreakMode = .byTruncatingTail
            content.addArrangedSubview(role)
        }
        tile.addAction(UIAction { [weak self] _ in self?.open(entry) }, for: .touchUpInside)
        return tile
    }

    private func open(_ entry: Entry) {
        UserDefaults.standard.set(Int(Date().timeIntervalSince1970 * 1_000),
                                  forKey: "dsbot.seen.\(entry.target.id)")
        onSelect?(entry.target)
        dismiss(animated: true)
    }

    private var sectionOffset: Int { pendingCount > 0 ? 1 : 0 }
    override func numberOfSections(in tableView: UITableView) -> Int { sections.count + sectionOffset }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section < sectionOffset ? 1 : sections[section - sectionOffset].1.count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section < sectionOffset ? nil : tr(sections[section - sectionOffset].0)
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "team")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "team")
        if indexPath.section < sectionOffset {
            cell.textLabel?.text = "\(tr("Needs you")) · \(pendingCount)"
            cell.textLabel?.textColor = view.tintColor
            cell.detailTextLabel?.text = nil
            cell.accessoryType = .disclosureIndicator
            cell.accessoryView = nil
            return cell
        }
        let entry = sections[indexPath.section - sectionOffset].1[indexPath.row]
        cell.textLabel?.textColor = .label
        cell.textLabel?.text = entry.target.name + (entry.pinned ? " · \(tr("Pinned"))" : "")
        cell.detailTextLabel?.text = entry.preview.isEmpty
            ? tr(entry.target.kind == .room ? "Group chat" : "Bot") : entry.preview
        cell.accessoryType = .none
        cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        let seen = UserDefaults.standard.integer(forKey: "dsbot.seen.\(entry.target.id)")
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: entry.lastAt > seen ? .semibold : .regular)
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section < sectionOffset {
            let action = onNeeds
            dismiss(animated: true) { action?() }
            return
        }
        let entry = sections[indexPath.section - sectionOffset].1[indexPath.row]
        open(entry)
    }

    override func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section >= sectionOffset else { return nil }
        let target = sections[indexPath.section - sectionOffset].1[indexPath.row].target
        let edit = UIContextualAction(style: .normal, title: tr("Edit")) { [weak self] _, _, done in
            guard let self else { done(false); return }
            let botAction = onEditBot
            let groupAction = onEditGroup
            if target.kind == .bot {
                dismiss(animated: true) { botAction?(target.id) }
            } else {
                dismiss(animated: true) { groupAction?(target.id) }
            }
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [edit])
    }
}
