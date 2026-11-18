import UIKit

final class NeedsYouViewController: UITableViewController {
    var onOpen: ((ChatTarget) -> Void)?

    private struct Row {
        let target: ChatTarget
        let summary: String
    }

    private let sections: [(String, [Row])]

    static func count(in state: JSONValue) -> Int {
        let questions: Int
        if case .object(let values)? = state["questions"] { questions = values.count } else { questions = 0 }
        let approvals: Int
        if case .array(let values)? = state["work"]?["approvals"] {
            approvals = values.filter { $0["answerable"] != .bool(false) }.count
        } else { approvals = 0 }
        let secrets: Int
        if case .object(let groups)? = state["secretRequests"] {
            secrets = groups.values.reduce(0) { total, value in
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
        func botTarget(_ id: String) -> ChatTarget {
            let bot = bots.first { $0["id"]?.stringValue == id }
            return ChatTarget(kind: .bot, id: id, name: bot?["name"]?.stringValue ?? id)
        }
        func sessionTarget(_ id: String) -> ChatTarget? {
            guard let bot = bots.first(where: {
                $0["sessionId"]?.stringValue == id || $0["id"]?.stringValue == id
            }), let botID = bot["id"]?.stringValue else { return nil }
            return botTarget(botID)
        }
        func approvalTarget(_ value: JSONValue) -> ChatTarget? {
            if let roomID = value["roomId"]?.stringValue {
                let room = rooms.first { $0["id"]?.stringValue == roomID }
                return ChatTarget(kind: .room, id: roomID, name: room?["name"]?.stringValue ?? roomID)
            }
            guard let botID = value["botId"]?.stringValue else { return nil }
            return botTarget(botID)
        }
        var questions: [Row] = []
        if case .object(let values)? = state["questions"] {
            for (sessionID, question) in values {
                if let target = sessionTarget(sessionID) {
                    questions.append(Row(target: target,
                                         summary: question["question"]?.stringValue ?? NativeLanguage.text("Question")))
                }
            }
        }
        var approvals: [Row] = []
        if case .array(let values)? = state["work"]?["approvals"] {
            for value in values {
                if let target = approvalTarget(value) {
                    let text = [value["tool"]?.stringValue, value["reason"]?.stringValue]
                        .compactMap { $0 }.joined(separator: " · ")
                    approvals.append(Row(target: target, summary: text))
                }
            }
        }
        var secrets: [Row] = []
        if case .object(let groups)? = state["secretRequests"] {
            for (botID, value) in groups {
                guard case .array(let requests) = value else { continue }
                for request in requests where request["status"]?.stringValue == "pending" {
                    let name = request["name"]?.stringValue ?? ""
                    secrets.append(Row(target: botTarget(botID),
                                       summary: name.isEmpty ? "A secret is needed" : "Asks for the secret \(name)"))
                }
            }
        }
        var handoffs: [Row] = []
        if case .object(let values)? = state["browserHolds"] {
            for (botID, hold) in values where hold["callId"]?.stringValue != nil {
                handoffs.append(Row(target: botTarget(botID), summary: hold["note"]?.stringValue
                                    ?? hold["reason"]?.stringValue ?? NativeLanguage.text("Browser handoff"))
            }
        }
        var views: [Row] = []
        if case .object(let values)? = state["views"] {
            for (sessionID, value) in values {
                if let target = sessionTarget(sessionID) {
                    views.append(Row(target: target, summary: value["title"]?.stringValue ?? NativeLanguage.text("View"))
                }
            }
        }
        sections = [("Questions", questions), ("Approvals", approvals), ("Secret requests", secrets),
                    ("Browser handoffs", handoffs), ("Cards", views)].filter { !$0.1.isEmpty }
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("Needs you")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                            target: self, action: #selector(close))
    }

    @objc private func close() { dismiss(animated: true) }

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].1.count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        NativeLanguage.text(sections[section].0)
    }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "pending-team")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "pending-team")
        let row = sections[path.section].1[path.row]
        cell.textLabel?.text = row.target.name
        cell.detailTextLabel?.text = row.summary
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        let target = sections[path.section].1[path.row].target
        onOpen?(target)
        dismiss(animated: true)
    }
}
