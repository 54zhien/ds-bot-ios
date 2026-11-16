import UIKit

struct ChatTarget: Equatable {
    enum Kind: Equatable { case bot, room }
    let kind: Kind
    let id: String
    let name: String
}

/// SidebarIcon from mobile/src/ui/icons.tsx, 20×20 viewBox.
final class OriginalSidebarIcon: UIView {
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

/// The mobile team's navigation data, in the same main/bot/room order as
/// mobile/src/screens/TeamList.tsx.
final class TeamListViewController: UITableViewController, UISearchResultsUpdating {
    var onSelect: ((ChatTarget) -> Void)?
    private let state: JSONValue
    private struct Entry {
        let target: ChatTarget
        let preview: String
        let pinned: Bool
        let lastAt: Int
    }
    private var sections: [(String, [Entry])] = []
    private var query = ""

    init(state: JSONValue) {
        self.state = state
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "DS Bot"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search the team"
        navigationItem.searchController = search
        rebuild()
    }

    @objc private func close() { dismiss(animated: true) }

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
            return Entry(target: target, preview: preview, pinned: value["pinned"] == .bool(true),
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
        sections = [
            ("Main Bots", main),
            ("Conversations", conversations),
        ].filter { !$0.1.isEmpty }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].1.count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].0
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "team")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "team")
        let entry = sections[indexPath.section].1[indexPath.row]
        cell.textLabel?.text = entry.target.name + (entry.pinned ? " · Pinned" : "")
        cell.detailTextLabel?.text = entry.preview.isEmpty
            ? (entry.target.kind == .room ? "Group chat" : "Bot") : entry.preview
        cell.accessoryType = .disclosureIndicator
        let seen = UserDefaults.standard.integer(forKey: "dsbot.seen.\(entry.target.id)")
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: entry.lastAt > seen ? .semibold : .regular)
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = sections[indexPath.section].1[indexPath.row]
        UserDefaults.standard.set(Int(Date().timeIntervalSince1970 * 1_000), forKey: "dsbot.seen.\(entry.target.id)")
        onSelect?(entry.target)
        dismiss(animated: true)
    }
}
