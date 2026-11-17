import UIKit

/// The details reached from the chat title, following the RN BotDetails/GroupDetails entry.
final class ConversationDetailsViewController: UITableViewController {
    var onEdit: (() -> Void)?

    private let target: ChatTarget
    private let state: JSONValue
    private let session: LinkSession
    private var memoryCount: Int?
    private var usageText: String?
    private var scheduleText: String?
    private var workDirOverride: String?
    private var permissionOverride: String?

    init(target: ChatTarget, state: JSONValue, session: LinkSession) {
        self.target = target
        self.state = state
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var record: JSONValue? {
        let key = target.kind == .bot ? "bots" : "rooms"
        guard case .array(let values)? = state[key] else { return nil }
        return values.first { $0["id"]?.stringValue == target.id }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = target.name
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Edit", style: .plain, target: self, action: #selector(editDetails)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52
        if target.kind == .bot { loadBotSummaries() }
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func editDetails() { onEdit?() }

    override func numberOfSections(in tableView: UITableView) -> Int {
        target.kind == .bot && state["browser"] != .bool(false) ? 4 : 3
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if target.kind == .bot { return ["Bot", "Work", "Activity", "Browser"][section] }
        return ["Group", "Members", "Conversation"][section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if target.kind == .bot { return [2, 4, 3, 1][section] }
        if section == 1 { return memberIDs.count }
        return section == 0 ? 2 : state["memory"] == .bool(false) ? 2 : 3
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "detail")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "detail")
        let selectable = target.kind == .bot
            ? indexPath.section == 3 || indexPath.section == 1
                || indexPath.section == 2 && indexPath.row == 0 && state["memory"] != .bool(false)
                || indexPath.section == 2 && indexPath.row == 2
            : indexPath.section == 2 && indexPath.row == 2
        cell.selectionStyle = selectable ? .default : .none
        cell.accessoryView = nil
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        let pair = target.kind == .bot ? botRow(indexPath) : groupRow(indexPath)
        cell.textLabel?.text = pair.0
        cell.detailTextLabel?.text = pair.1
        if selectable {
            cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if target.kind == .room && indexPath.section == 2 && indexPath.row == 2 {
            navigationController?.pushViewController(
                MemoryViewController(owner: .room(target.id), session: session), animated: true
            )
        } else if target.kind == .bot && indexPath.section == 2 && indexPath.row == 0
                    && state["memory"] != .bool(false) {
            navigationController?.pushViewController(
                MemoryViewController(owner: .bot(target.id), session: session), animated: true
            )
        } else if target.kind == .bot && indexPath.section == 2 && indexPath.row == 2 {
            let schedules = SchedulesViewController(
                botID: target.id, sessionID: record?["sessionId"]?.stringValue ?? target.id,
                session: session
            )
            navigationController?.pushViewController(schedules, animated: true)
        } else if target.kind == .bot && indexPath.section == 1 && indexPath.row == 1 {
            pickPermission(source: tableView.cellForRow(at: indexPath))
        } else if target.kind == .bot && indexPath.section == 1 && indexPath.row != 2 {
            onEdit?()
        } else if target.kind == .bot && indexPath.section == 1 && indexPath.row == 2 {
            let folder = FolderPickerViewController(
                current: workDirOverride ?? record?["workDir"]?.stringValue ?? "",
                owner: .bot(target.id), session: session
            )
            folder.onPicked = { [weak self] path in
                self?.workDirOverride = path
                self?.tableView.reloadData()
            }
            navigationController?.pushViewController(folder, animated: true)
        } else if target.kind == .bot && indexPath.section == 3 {
            let browser = BrowserHandoffViewController(
                botID: target.id, hold: state["browserHolds"]?[target.id] ?? .object([:]), session: session
            )
            navigationController?.pushViewController(browser, animated: true)
        }
    }

    private func botRow(_ path: IndexPath) -> (String, String) {
        let bot = record
        switch (path.section, path.row) {
        case (0, 0): return ("Name", bot?["name"]?.stringValue ?? target.name)
        case (0, 1): return ("Role", bot?["role"]?.stringValue ?? "—")
        case (1, 0): return ("Model", bot?["model"]?.stringValue ?? state["defaultModel"]?.stringValue ?? "Default")
        case (1, 1): return ("Permissions", permissionOverride ?? bot?["permission"]?.stringValue
                             ?? state["permissions"]?["defaultPreset"]?.stringValue ?? "Default")
        case (1, 2): return ("Working folder", workDirOverride ?? bot?["workDir"]?.stringValue ?? "Team workspace")
        case (1, 3): return ("Instructions", bot?["instructions"]?.stringValue ?? "Add in Bot settings")
        case (2, 0): return ("Memory", state["memory"] == .bool(false) ? "Unavailable"
                             : memoryCount.map { "\($0) entries" } ?? "—")
        case (2, 1): return ("Usage", usageText ?? "—")
        case (3, 0): return ("Open browser", "See the current page and hand it back to the Bot")
        default: return ("Scheduled tasks", scheduleText ?? "—")
        }
    }

    private var memberIDs: [String] { record?["members"]?.stringArrayValue ?? [] }

    private func pickPermission(source: UIView?) {
        guard case .array(let options)? = state["permissions"]?["options"] else { return }
        let sheet = UIAlertController(title: "Permissions", message: nil, preferredStyle: .actionSheet)
        for option in options {
            guard let value = option["value"]?.stringValue else { continue }
            sheet.addAction(UIAlertAction(title: option["name"]?.stringValue ?? value, style: .default) { [weak self] _ in
                guard let self else { return }
                Task {
                    do {
                        _ = try await BotAPI.call("update-bot", payload: .object([
                            "id": .string(self.target.id), "permission": .string(value),
                        ]), on: self.session)
                        self.permissionOverride = value
                        self.tableView.reloadData()
                    } catch {
                        let alert = UIAlertController(title: "Could not change permissions",
                                                      message: error.localizedDescription, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        present(sheet, animated: true)
    }

    private func groupRow(_ path: IndexPath) -> (String, String) {
        let room = record
        if path.section == 1 {
            let id = memberIDs[path.row]
            let bot: JSONValue?
            if case .array(let bots)? = state["bots"] {
                bot = bots.first { $0["id"]?.stringValue == id }
            } else { bot = nil }
            let name = bot?["name"]?.stringValue ?? id
            return (name, id == room?["admin"]?.stringValue ? "Admin" : bot?["role"]?.stringValue ?? "Member")
        }
        switch (path.section, path.row) {
        case (0, 0): return ("Name", room?["name"]?.stringValue ?? target.name)
        case (0, 1): return ("Notice", room?["notice"]?.stringValue ?? "Add in group settings")
        case (2, 0): return ("Who answers", room?["mode"]?.stringValue == "everyone" ? "Everyone" : "Admin leads")
        case (2, 1): return ("Members", "\(memberIDs.count)")
        default: return ("Memory", "Manage group memory")
        }
    }

    private func loadBotSummaries() {
        Task {
            if let memory = try? await BotAPI.call("memory-view", payload: .object([
                "botId": .string(target.id),
            ]), on: session), case .array(let entries)? = memory["entries"] {
                memoryCount = entries.count
                tableView.reloadData()
            }
        }
        Task {
            if let stats = try? await BotAPI.call("run-stats", payload: .object([
                "botId": .string(target.id),
            ]), on: session) {
                let usage = stats["tokenUsage"]
                let input = (usage?["uncachedInputTokens"]?.intValue ?? 0)
                    + (usage?["cacheReadTokens"]?.intValue ?? 0)
                    + (usage?["cacheWriteTokens"]?.intValue ?? 0)
                let output = usage?["outputTokens"]?.intValue ?? 0
                usageText = "\(input + output) tokens"
                tableView.reloadData()
            }
        }
        Task {
            if let schedules = try? await BotAPI.call("schedules", on: session),
               case .array(let tasks)? = schedules["tasks"] {
                let active = tasks.filter {
                    $0["botId"]?.stringValue == target.id && $0["status"]?.stringValue == "active"
                }
                scheduleText = active.isEmpty ? "None" : active.compactMap { $0["title"]?.stringValue }
                    .joined(separator: ", ")
                tableView.reloadData()
            }
        }
    }
}
